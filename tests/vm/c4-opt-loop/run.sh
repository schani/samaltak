#!/bin/sh
set -eu
umask 077
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
cd "$here/../../.."
root=$PWD
image=$(realpath "${1:?pass a full stage-2 image}")
test -f "$image"
mkdir -p "${OUT:-build}"
out=$(mktemp -d "$(realpath "${OUT:-build}")/c4-opt-loop.XXXXXX")
mkdir "$out/tmp"
export LC_ALL=C TMPDIR="$out/tmp"
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_OPT_SLICE SAMALTAK_OPT_SLICE_TRACE SAMALTAK_OPT_LOOP \
    OPT_LOOP_PROBE OPT_LOOP_GC OPT_LOOP_MOVING
ulimit -c 0
echo "loop test logs: $out"
cc=${CC:-cc}
variant=c4-opt-loop-test
bin=${LOOP_BUILD:-"$out/native"}
if [ -z "${LOOP_BUILD:-}" ]; then
    CFLAGS="-O2 -g1" make -C vm -j"${JOBS:-2}" CC="$cc" NO_PLATFORM=1 NO_PGO=1 \
        C4_OPT_LOOP_TEST=1 BUILD="$bin" BRIEF=1 >"$out/build.log" 2>&1
fi
"$cc" -O2 -Ivm/gen -Ivm -DSAMALTAK_NO_PLATFORM -c "$here/probe.c" -o "$out/probe.o"
find "$bin/obj-$variant" -name '*.o' -print0 | sort -z |
    xargs -0 sh -c 'cc=$1 bin=$2 probe=$3; shift 3; "$cc" -o "$bin" "$probe" "$@" \
      -Wl,--wrap=try_slice_loop,--wrap=replay_slice,--wrap=jit_runtime_tier_up,--wrap=opt_runtime_tier_up,--wrap=c4_heap_should_collect,--wrap=c4_heap_begin,--wrap=c4_heap_root,--wrap=c4_heap_end_roots,--wrap=c4_heap_finish_poll \
      -lm -lpthread' sh "$cc" "$out/probe-vm" "$out/probe.o"
plain=$(cat "$here/loop.st")
witness=$(sed "s@\"WEAK_WITNESS\"@check value: ((weak at: 1) notNil and: [(weak at: 1) x = 41 and: [(weak at: 1) y = 67]]) value: 'live Point lost'. check value: (weak at: 2) isNil value: 'weak-only Point survived'.@" "$here/loop.st")
probe() {
    file=$1; eval=$2; shift 2
    timeout -k 2 25 "$out/probe-vm" --jit none --eden 16 --max-heap 128 "$@" "$image" --headless \
        --eval "$eval" >"$out/$file.out" 2>"$out/$file.err"
    grep -Fxq 'checked loop parity ok' "$out/$file.out"
}
for lane in c4 c4-moving c4-moving-forward legacy; do
    set --
    [ "$lane" = legacy ] || set -- "--$lane"
    probe "$lane-control" "$plain" "$@"
    if grep -Eq '^opt-slice|^loop probe' "$out/$lane-control.err"; then exit 1; fi
    case $lane in
        c4) unset OPT_LOOP_MOVING ;;
        c4-moving) export OPT_LOOP_MOVING=1 ;;
        *)
            SAMALTAK_OPT_LOOP=1 probe "$lane-disabled" "$plain" "$@"
            if grep -Eq '^opt-slice|^loop probe' "$out/$lane-disabled.err"; then exit 1; fi
            continue ;;

    esac
    SAMALTAK_OPT_LOOP=1 OPT_LOOP_PROBE=1 OPT_LOOP_GC=1 SAMALTAK_OPT_SLICE_TRACE=1 \
        SAMALTAK_C4_STATS=1 probe "$lane-loop" "$witness" "$@"
    cmp "$out/$lane-control.out" "$out/$lane-loop.out"
    err="$out/$lane-loop.err"
    grep -Eq '^opt-slice installed .* nativeBytes=[1-9][0-9]*$' "$err"
    grep -Eq '^opt-slice exit=1 id=[0-9]+ pc=12 depth=10$' "$err"
    grep -Eq '^opt-slice exit=2 id=[0-9]+ pc=12 depth=10$' "$err"
    grep -Eq '^opt-slice exit=3 id=[0-9]+ pc=26 depth=11$' "$err"
    grep -Fxq 'loop probe: same activation reentered after GC' "$err"
    grep -Fxq 'opt-slice blocked by root publication' "$err"
    grep -Eq '^loop probe: sealed point_roots=1 code_roots=[1-9][0-9]*$' "$err"
    grep -Eq '^loop probe: 48x2ms polls, actual ' "$err"
    grep -Fxq 'opt-slice retire' "$err"
    awk '
        /^loop fixture: edit$/ {edit=1}
        /^loop fixture: restore$/ {edit=0; restore=1}
        edit && /^opt-slice (installed|exit)/ {bad=1}
        restore && /^opt-slice installed/ {installed=1}
        END {if (bad || !installed) exit 1}
    ' "$err"
done
for lane in c4 c4-moving c4-moving-forward; do
    status=0
    SAMALTAK_OPT_LOOP=1 timeout -k 2 10 "$bin/samaltak" --jit opt "--$lane" "$image" --headless \
        --eval 'Smalltalk quit: 0' >"$out/policy-$lane.log" 2>&1 || status=$?
    [ "$status" = 70 ]
done
echo 'loop test passed'
