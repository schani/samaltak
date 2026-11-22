#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
image=${1:?pass the full stage-2 image}
vm=${2:?pass the C4 headless VM}
out=${OUT:-build}/c4-jit-forward
mkdir -p "$out"
for mode in c4 c4-moving; do
    log=$out/$mode.log
    SAMALTAK_C4_STATS=1 timeout -k 2 90 "$vm" "--$mode" --jit baseline --jit-threshold 0 --jit-osr 0 \
        --eden 1 --max-heap 128 "$image" --headless --eval "$(cat tests/vm/c4-jit-live/forward.st)" \
        >"$log" 2>&1 || { cat "$log"; exit 1; }
    grep -Fxq 'c4-jit forwarding ok' "$log" || { cat "$log"; exit 1; }
    awk '
      /^c4: phase=/ {
        for (i=2; i<=NF; ++i) {split($i, kv, "="); s[kv[1]]=kv[2]+0}
        gc=(s["cycles_completed"] >= 2 && s["reused"] > 0 && s["failed"] == 0)
      }
      /^c4-jit: checkpoints=/ {sub(/^checkpoints=/, "", $2); native=($2+0 > 0)}
      END {exit !(gc && native)}' "$log" || { cat "$log"; exit 1; }
    cat "$log"
done
