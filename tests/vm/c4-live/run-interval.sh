#!/bin/sh
# Usage: run-interval.sh STAGE2_IMAGE C4_VM [enabled|old|witness]
set -eu
cd "$(dirname "$0")/../../.."
image=${1:?pass a full stage-2 image}
runtime=${2:?pass the C4 headless VM}
expect=${3:-enabled}
out=${OUT:-build}/c4-interval-$expect
mkdir -p "$out"
tiers='none baseline'
if [ "${C4_ARM64_VALIDATION:-0}" = 1 ]; then tiers=none; fi
for jit in $tiers; do
    log=$out/$jit.log
    SAMALTAK_C4_STATS=1 timeout -k 2 90 "$runtime" --c4-moving --jit "$jit" --jit-threshold 0         --eden 1 --max-heap 128 "$image" --headless --eval "$(cat tests/vm/c4-live/interval.st)"         >"$log" 2>&1 || { cat "$log"; exit 1; }
    grep -Fxq 'C4 Interval ok' "$log"
    awk -v old="$(test "$expect" != old || echo 1)" -v baseline="$(test "$jit" != baseline || echo 1)" '
        { delete s; for (i=2; i<=NF; ++i) { split($i,k,"="); s[k[1]]=k[2]+0 } }
        /^c4: phase=/ { gc=(s["cycles_completed"]>=2 && s["weak_cleared"]>0 && s["failed"]==0) }
        /^c4-moving:/ { p=(s["moved_point"]>0 && s["max_inspected"]>0 && s["max_inspected"]<=64 &&
                         s["max_copied"]>=32 && s["max_copied"]<=4096) }
        /^c4-interval:/ {
            if (old) v=(s["enabled"]==0 && !("pool_bytes" in s))
            else v=(s["enabled"]==1 && s["pool_bytes"]==65536 && s["reserve_bytes"]==16384 &&
                    s["moved"]>0 && s["released"]>0 && s["source_reused"]>0)
        }
        /^c4-jit:/ { native=(s["checkpoints"]>0) }
        END { exit !(gc && p && v && (!baseline || native)) }
    ' "$log" || { cat "$log"; exit 1; }
    if [ "$expect" = witness ]; then
        grep -Fxq 'c4-witness: exact Interval body moved with stable header' "$log"
    fi
    cat "$log"
done
