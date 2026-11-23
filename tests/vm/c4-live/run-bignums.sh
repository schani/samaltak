#!/bin/sh
# Usage: run-bignums.sh STAGE2_IMAGE [C4_VM]
set -eu
cd "$(dirname "$0")/../../.."
image=${1:?pass a full stage-2 image}
vm=${2:-vm/build/c4/samaltak}
out=${OUT:-build}/c4-bignums
mkdir -p "$out"
unset DISPLAY WAYLAND_DISPLAY
ulimit -c 0

for spec in c4:none c4:baseline c4-moving:none c4-moving:baseline c4-moving-forward:none; do
    mode=${spec%:*}
    tier=${spec#*:}
    log=$out/$mode-$tier.log
    if ! SAMALTAK_C4_STATS=1 timeout -k 2 90 "$vm" "--$mode" --jit "$tier" --jit-threshold 0 \
        --eden 1 --max-heap 128 "$image" --headless --eval "$(cat tests/vm/c4-live/bignums.st)" >"$log" 2>&1 ||
        ! grep -Fxq 'C4 bignums ok' "$log" ||
        ! awk -v tier="$tier" '
            /^c4: phase=/ {
                for (i = 2; i <= NF; i++) {
                    split($i, kv, "=")
                    s[kv[1]] = kv[2]+0
                }
                gc = (s["cycles_completed"] >= 2 && s["reused"] > 0 && "failed" in s && s["failed"] == 0)
            }
            /^c4-jit: checkpoints=/ {
                split($2, kv, "=")
                jit = (tier == "baseline" ? kv[2]+0 > 0 : kv[2]+0 == 0)
            }
            END { exit !(gc && jit) }
        ' "$log"; then
        cat "$log" >&2
        exit 1
    fi
    echo "c4-bignums: $mode/$tier passed"
done
