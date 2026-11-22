#!/bin/sh
# Usage: run.sh STANDARD_STAGE2_IMAGE [normal|blocked]
set -eu
cd "$(dirname "$0")/../../.."
image=$(realpath "${1:?pass the standard stage-2 image}")
variant=${2:-normal}
testdir=tests/vm/c4-platform-files
case "$variant" in
    normal) vm=vm/build/c4-platform-files/samaltak ;;
    blocked) vm=vm/build/c4-platform-blocked/samaltak ;;
    *) exit 2 ;;
esac
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
unset DISPLAY WAYLAND_DISPLAY
export SAMALTAK_C4_STATS=1
for mode in --c4 --c4-moving; do
    SAMALTAK_C4_SCRATCH="$scratch/$mode"
    export SAMALTAK_C4_SCRATCH
    mkdir "$SAMALTAK_C4_SCRATCH"
    mkfifo "$SAMALTAK_C4_SCRATCH/host-fifo"
    rc=0
    timeout -k 2 45 "$vm" "$mode" --max-heap 160 --eden 1 \
        "$image" --headless --eval "$(cat "$testdir/files.st")" \
        >"$scratch/out" 2>"$scratch/err" || rc=$?
    cat "$scratch/out" "$scratch/err"
    test "$rc" -eq 0
    grep -Fxq 'C4 platform files ok' "$scratch/out"
    grep -Eq '^c4: .*cycles_completed=[1-9][0-9]* .*weak_cleared=[1-9][0-9]* .*failed=0 ' "$scratch/err"
    if [ "$mode" = --c4-moving ]; then
        grep -Eq '^c4-moving: .* moved=[1-9][0-9]* ' "$scratch/err"
    fi
    if [ "$variant" = blocked ]; then
        grep -Fxq 'C4 worker reached close during file read' "$scratch/err"
    fi
    test ! -e "$SAMALTAK_C4_SCRATCH/must-not-exist"
done
if [ "$variant" = normal ]; then
    reject() {
        want=$1; shift
        if timeout -k 2 5 "$vm" "$@" >"$scratch/reject" 2>&1 ||
            ! grep -Fq -- "$want" "$scratch/reject"; then
            cat "$scratch/reject" >&2
            exit 1
        fi
    }
    reject 'requires --c4 or --c4-moving' "$image" --headless
    reject 'requires --headless' --c4 "$image"
    reject 'require --jit none' --c4 --jit baseline "$image" --headless
    reject 'require --jit none' --c4-moving --jit opt "$image" --headless
fi
echo "c4-platform-files: $variant passed"
