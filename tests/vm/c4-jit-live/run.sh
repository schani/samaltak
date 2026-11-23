#!/bin/sh
# Use the full stage-2 image built by the platform VM.
set -eu
cd "$(dirname "$0")/../../.."
image=${1:?pass the full stage-2 image}
vm=${2:?pass the C4 headless VM}
out=${OUT:-build}/c4-jit-live
mkdir -p "$out"
for mode in c4 c4-moving; do
    SAMALTAK_C4_STATS=1 timeout -k 2 120 "$vm" "--$mode" --jit baseline --jit-threshold 0 --jit-osr 0 \
        --eden 1 --max-heap 128 "$image" --headless --eval "$(cat tests/vm/c4-jit-live/live.st)" \
        >"$out/$mode.out" 2>"$out/$mode.err" || { cat "$out/$mode.out" "$out/$mode.err"; exit 1; }
    grep -Fxq "'c4-jit-live ok'" "$out/$mode.out" || { cat "$out/$mode.out" "$out/$mode.err"; exit 1; }
    awk '
        /^c4-jit: checkpoints=/ {sub(/^checkpoints=/, "", $2); sub(/^publishing_exits=/, "", $3); native=($2+0 > 0 && $3+0 > 0)}
        /^c4: phase=/ {
            for (i=2; i<=NF; ++i) {split($i, kv, "="); s[kv[1]]=kv[2]+0}
            if (s["cycles_completed"] >= 2 && s["closed"] >= 2 &&
                s["weak_cleared"] > 0 && s["reused"] > 0 && s["failed"] == 0) ok=1
        }
        END {exit !(ok && native)}' "$out/$mode.err" || { cat "$out/$mode.err"; exit 1; }
done
