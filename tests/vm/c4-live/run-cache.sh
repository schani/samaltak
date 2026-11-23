#!/bin/sh
# Usage: tests/vm/c4-live/run-cache.sh STANDARD_STAGE2_IMAGE [C4_VM]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m):${C4_ARM64_INTERPRETER_TEST:-0}" in
    'Linux x86_64:0'|'Linux x86_64:1'|'Linux aarch64:1') ;;
    *) echo 'c4-cache: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a stage-2 image built by the platform VM}
runtime=${2:-vm/build/c4/samaltak}
out=${OUT:-build}/c4-cache
mkdir -p "$out"
tiers='none baseline'
if [ "${C4_ARM64_INTERPRETER_TEST:-0}" = 1 ]; then tiers=none; fi
for mode in --c4 --c4-moving; do
    for tier in $tiers; do
        log=$out/${mode#--}-$tier.log
        native=false
        if [ "$tier" = baseline ]; then native=true; fi
        script=$(sed "s/CHECK_BASELINE/$native/" tests/vm/c4-live/cache.st)
        if ! SAMALTAK_C4_STATS=1 timeout -k 2 60 "$runtime" "$mode" \
                --jit "$tier" --jit-threshold 0 --jit-osr 0 --eden 1 --max-heap 128 "$image" \
                --headless --eval "$script" >"$log" 2>&1 ||
                ! grep -Fxq 'C4 epoch dispatch ok' "$log" ||
                ! grep -Eq '^c4: phase=.* failed=0( |$)' "$log" ||
                { [ "$tier" = baseline ] && ! grep -Eq '^c4-jit: checkpoints=[1-9][0-9]* ' "$log"; }; then
            cat "$log" >&2
            exit 1
        fi
        echo "c4-cache: $mode $tier passed"
    done
done
