#!/bin/sh
# Usage: tests/vm/c4-live/run-context.sh STANDARD_STAGE2_IMAGE [C4_VM]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m)" in
    'Linux x86_64') ;;
    *) echo 'c4-context: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a standard stage-2 image built by the platform VM}
runtime=${2:-vm/build/c4/samaltak}
out=${OUT:-build}/c4-context
mkdir -p "$out"

fail() {
    cat "$out/$1.log" >&2
    echo "c4-context: $1 failed" >&2
    exit 1
}

timeout -k 2 30 "$runtime" --c4 --eden 8 --max-heap 128 "$image"     --headless --eval "$(cat tests/vm/c4-live/context.st)" >"$out/reflection.log" 2>&1 ||
    fail reflection
grep -Fxq 'C4 Context reflection ok' "$out/reflection.log" || fail reflection

rc=0
timeout -k 2 30 "$runtime" --c4 --eden 8 --max-heap 128 "$image"     --headless --eval "$(cat tests/vm/c4-live/context-method.st)" >"$out/method.log" 2>&1 ||
    rc=$?
[ "$rc" -eq 70 ] &&
    grep -Fxq 'running in heap base' "$out/method.log" &&
    grep -Fxq 'samaltak: fatal: C4 cannot replace compiled method storage' "$out/method.log" ||
    fail method
timeout -k 2 30 "$runtime" --jit none --eden 8 --max-heap 128 "$image" \
    --headless --eval "$(cat tests/vm/c4-live/context-method.st)" >"$out/method-legacy.log" 2>&1 ||
    fail method-legacy
grep -Fxq 'running in heap base' "$out/method-legacy.log" || fail method-legacy

for mode in c4 legacy; do
    case "$mode" in c4) set -- --c4 ;; legacy) set -- --jit none ;; esac
    timeout -k 2 30 "$runtime" "$@" --eden 8 --max-heap 128 "$image" \
        --headless --test MarriedContextTest >"$out/$mode.log" 2>&1 || fail "$mode"
    awk '/^[1-9][0-9]* run,/ && $1 == $3 && $5 == 0 && $7 == 0 && !/skipped/ { passed++ }
        END { exit passed != 1 }' "$out/$mode.log" || fail "$mode"
done
echo 'c4-context: reflection, heap base method guard, and MarriedContextTest passed'
