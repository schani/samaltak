#!/bin/sh
# Standalone Linux x86-64 headless draft. Requires a full stage-2 image.
set -eu
umask 077
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
cd "$here/../../.."
root=$PWD
image=$(realpath "${1:?pass a full stage-2 image}")
test -f "$image"
[ "$(uname -s):$(uname -m)" = Linux:x86_64 ] || { echo "requires Linux x86-64" >&2; exit 1; }
mkdir -p "${OUT:-build}"
out=$(mktemp -d "$(realpath "${OUT:-build}")/c4-opt-slice.XXXXXX")
mkdir "$out/tmp"
export TMPDIR="$out/tmp" LC_ALL=C
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_OPT_SLICE SAMALTAK_OPT_SLICE_TRACE \
    SAMALTAK_OPT_ADMISSION SAMALTAK_OPT_TRACE SAMALTAK_PERF_MAP SAMALTAK_C4_STATS \
    OPT_SLICE_EXPECT_NATIVE OPT_SLICE_WITNESS
ulimit -c 0
echo "slice test logs: $out"
trap 's=$?; if [ "$s" -ne 0 ]; then echo "slice test failed: see $out" >&2; fi' EXIT

# Non-LTO keeps calls and the ordinary tier-up stub target wrappable.
cc=${CC:-cc}
build() (
    name=$1 opt=$2 variant=$3
    cd "$root/vm"
    CFLAGS="-O2 -g1" make -j"${JOBS:-4}" CC="$cc" NO_PLATFORM=1 NO_PGO=1 \
        C4_OPT_SLICE_TEST="$opt" BUILD="$out/$name" BRIEF=1 >"$out/build-$name.log" 2>&1
    "$cc" -O2 -Igen -I. -DSAMALTAK_NO_PLATFORM -c "$here/probe.c" -o "$out/probe-$name.o"
    # mktemp's output is the only object root; each build has its own variant.
    find "$out/$name/obj-$variant" -type f -name '*.o' -print0 | sort -z |
        xargs -0 sh -c '
            cc=$1 bin=$2 probe=$3; shift 3
            "$cc" -o "$bin" "$probe" "$@" \
                -Wl,--wrap=replay_slice,--wrap=jit_runtime_tier_up,--wrap=opt_runtime_tier_up,--wrap=c4_heap_should_collect,--wrap=c4_heap_begin,--wrap=c4_heap_root,--wrap=c4_heap_end_roots,--wrap=c4_heap_move_poll \
                -lm -lpthread
        ' sh "$cc" "$out/$name/probe-vm" "$out/probe-$name.o"
)
build off 0 headless
build on 1 c4-opt-slice-test

probe() {
    bin=$1 log=$2 st=$3; shift 3
    timeout -k 2 60 "$out/$bin/probe-vm" --jit none "$@" "$image" --headless \
        --eval "$(cat "$here/$st.st")" >"$out/$log.out" 2>"$out/$log.err"
}
quiet() {
    if grep -Ei 'opt-slice|opt-admission|slice probe:|tier.up' "$out/$1.err"; then
        echo "unexpected slice/ordinary tier-up activity in $1" >&2
        exit 1
    fi
}
exit_rows() {
    for why in "$@"; do
        grep -Fxq "slice probe: native return reason=$why" "$out/$log.err"
        grep -Eq "^opt-slice exit=$why id=[0-9]+ pc=[0-9]+ depth=[0-9]+$" "$out/$log.err"
    done
}
for lane in legacy c4 c4-moving c4-moving-forward; do
    set --
    [ "$lane" = legacy ] || set -- "--$lane"
    probe off "$lane-control" probe "$@"
    grep -Fxq 'checked prefix parity ok' "$out/$lane-control.out"
    quiet "$lane-control"
    for selector in sliceAdd: sliceSub:keep:; do
        log="$lane-off-${selector%%:*}"
        SAMALTAK_OPT_SLICE="$selector" SAMALTAK_OPT_SLICE_TRACE=1 SAMALTAK_OPT_ADMISSION=1 \
            probe off "$log" probe "$@"
        cmp "$out/$lane-control.out" "$out/$log.out"
        quiet "$log"
    done
    probe on "$lane-no-selector" probe "$@"
    cmp "$out/$lane-control.out" "$out/$lane-no-selector.out"
    quiet "$lane-no-selector"
    for selector in sliceAdd: sliceSub:keep:; do
        log="$lane-on-${selector%%:*}"
        if [ "$lane" = c4-moving-forward ]; then
            SAMALTAK_OPT_SLICE="$selector" SAMALTAK_OPT_SLICE_TRACE=1 probe on "$log" probe "$@"
            quiet "$log"
        else
            OPT_SLICE_EXPECT_NATIVE=1 SAMALTAK_OPT_SLICE="$selector" SAMALTAK_OPT_SLICE_TRACE=1 \
                probe on "$log" probe "$@"
            grep -Eq '^opt-slice installed .* nativeBytes=[1-9][0-9]*$' "$out/$log.err"
            grep -Eq '^opt-slice machine=[0-9a-f]+$' "$out/$log.err"
            exit_rows 1 2 3
        fi
        cmp "$out/$lane-control.out" "$out/$log.out"
    done
done

log=c4-wide
OPT_SLICE_EXPECT_NATIVE=1 SAMALTAK_OPT_SLICE_TRACE=1 \
    SAMALTAK_OPT_SLICE=sliceWide:b:c:d:e:f:g:h:i:j:k:l: probe on "$log" bounds --c4
grep -Fxq 'checked prefix wide parity ok' "$out/$log.out"
grep -Eq '^opt-slice slots=13 ' "$out/$log.err"
exit_rows 1 2 3
log=c4-reject
SAMALTAK_OPT_SLICE=sliceReject: probe on "$log" bounds --c4
grep -Fxq 'checked prefix wide parity ok' "$out/$log.out"
quiet "$log"

for selector in sliceAdd: sliceLiteral:; do
    log="edits-${selector%%:*}"
    OPT_SLICE_EXPECT_NATIVE=1 SAMALTAK_OPT_SLICE="$selector" probe on "$log" edits --c4
    grep -Fxq 'checked prefix edits ok' "$out/$log.out"
    exit_rows 3
    awk '/^opt-slice installed / {++n; if (n==2 && !retired) exit 1}
         /^opt-slice retire$/ {if (n==1) retired=1}
         END {if (!(n==2 && retired)) exit 1}' "$out/$log.err"
done

log=moving-witness
OPT_SLICE_WITNESS=1 OPT_SLICE_EXPECT_NATIVE=1 SAMALTAK_C4_STATS=1 \
    SAMALTAK_OPT_SLICE_TRACE=1 SAMALTAK_OPT_SLICE=sliceSub:keep: \
    probe on "$log" witness --c4-moving --eden 16 --max-heap 128
grep -Fxq 'checked prefix moving witness ok' "$out/$log.out"
grep -Fxq 'opt-slice blocked by root publication' "$out/$log.err"
for msg in 'physical=17 ' 'sealed watched_roots=1 code_roots=2 partial=[1-9]' \
           'relocated ' 'fresh reentry after move$'; do
    grep -Eq "^opt-slice witness $msg" "$out/$log.err"
done
exit_rows 0 3
# The explicit request belongs to the first entry, not a later timer tick.
grep -m1 '^slice probe: native return reason=' "$out/$log.err" |
    grep -Fxq 'slice probe: native return reason=0'

for bin in off on; do
    for mode in none baseline opt; do
        case $mode in
            none) set -- ;;
            baseline) set -- --jit-threshold 0 ;;
            opt) set -- --jit-threshold 0 --jit-flags eager ;;
        esac
        SAMALTAK_OPT_ADMISSION=1 SAMALTAK_OPT_SLICE=sliceAdd: SAMALTAK_OPT_SLICE_TRACE=1 \
            timeout -k 2 90 "$out/$bin/samaltak" --jit "$mode" "$@" "$image" --headless \
            --test IntegerTest StringTest CollectionTest CompilerTest >"$out/$bin-legacy-$mode.log" 2>&1
        grep -Eq '^132 run, 132 passed, 0 failed, 0 errors' "$out/$bin-legacy-$mode.log"
        if grep -Ei '^opt-slice|^opt-admission' "$out/$bin-legacy-$mode.log"; then exit 1; fi
    done
    log="$out/$bin-policy-c4-moving-forward.log"
    status=0
    SAMALTAK_OPT_SLICE=sliceAdd: timeout -k 2 10 "$out/$bin/samaltak" --c4-moving-forward \
        --jit opt "$image" --headless --eval 'Smalltalk quit: 0' >"$log" 2>&1 || status=$?
    [ "$status" -eq 70 ]
    grep -Fxq 'samaltak: fatal: --c4-moving-forward requires --jit none' "$log"
done
echo "slice test passed: native replay, no ordinary tier-up, inactive controls and C4 publication"
