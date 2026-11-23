#!/bin/sh
# Usage: run-pointer-forward.sh STAGE2_IMAGE HEADLESS_VM
set -eu
cd "$(dirname "$0")/../../.."
image=${1:?pass a standard stage-2 image}
vm=${2:?pass a headless VM}
out=${OUT:-build}/c4-pointer-forward
mkdir -p "$out"
run() {
    log=$out/$1.log
    test=$2
    shift 2
    SAMALTAK_C4_STATS=1 timeout -k 2 60 "$vm" "$@" --eden 1 --max-heap 512 "$image" \
        --headless --eval "$(cat tests/vm/c4-live/pointer-forward$test.st)" >"$log" 2>&1 ||
        { cat "$log" >&2; exit 1; }
}
run legacy '' --jit none
grep -Fxq 'pointer forward ok' "$out/legacy.log"
tiers='none baseline'
if [ "${C4_ARM64_INTERPRETER_TEST:-0}" = 1 ]; then tiers=none; fi
for tier in $tiers; do
    run "$tier" '' --c4 --jit "$tier" --jit-threshold 0
    grep -Fxq 'pointer forward ok' "$out/$tier.log"
    awk '
      /^c4: phase=/ {
        for (i=2; i<=NF; ++i) { split($i,k,"="); s[k[1]]=k[2]+0 }
        ran=(s["cycles_completed"]>=3 && s["weak_cleared"]>0 && s["reused"]>0 && s["failed"]==0)
      }
      END { exit !ran }' "$out/$tier.log"
    if [ "$tier" = baseline ]; then
        grep -Eq '^c4-jit: checkpoints=[1-9][0-9]* ' "$out/$tier.log"
    fi
    run "$tier-rejections" -rejections --c4 --jit "$tier" --jit-threshold 0
    grep -Fxq 'pointer rejections ok' "$out/$tier-rejections.log"
    run "$tier-moving" -moving --c4-moving --jit "$tier" --jit-threshold 0
    grep -Fxq 'pointer moving rejects ok' "$out/$tier-moving.log"
done
if [ "${C4_ARM64_INTERPRETER_TEST:-0}" = 1 ]; then
    echo 'c4-pointer-forward: legacy/interpreter differential and rejection gates passed'
else
    echo 'c4-pointer-forward: legacy/interpreter/baseline differential and rejection gates passed'
fi
