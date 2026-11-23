#!/bin/sh
# Usage: tests/vm/c4-live/run-enumeration.sh STAGE2_IMAGE [C4_VM]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m):${C4_ARM64_INTERPRETER_TEST:-0}" in
    'Linux x86_64:0'|'Linux x86_64:1'|'Linux aarch64:1') ;;
    *) echo 'c4-enumeration: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a stage-2 image with the C4 enumeration image bridge}
runtime=${2:-vm/build/c4/samaltak}
out=${OUT:-build}/c4-enumeration
mkdir -p "$out"
case_source=$(cat tests/vm/c4-live/enumeration.st)
for mode in legacy c4 c4-moving; do
    case "$mode" in
        legacy) set -- --jit none "$image" --headless --eval "$case_source" ;;
        *) set -- "--$mode" --eden 1 --max-heap 128 "$image" --headless --eval "$case_source" c4-enum ;;
    esac
    if ! timeout -k 2 60 "$runtime" "$@" >"$out/$mode.out" 2>"$out/$mode.err" ||
        ! grep -Fxq 'heap enumeration ok' "$out/$mode.out"; then
        cat "$out/$mode.out" "$out/$mode.err" >&2
        exit 1
    fi
    echo "c4-enumeration: $mode passed"
done
