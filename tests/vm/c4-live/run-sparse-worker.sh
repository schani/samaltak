#!/bin/sh
# Usage: tests/vm/c4-live/run-sparse-worker.sh STANDARD_STAGE2_IMAGE [C4_VM]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m):${C4_ARM64_VALIDATION:-0}" in
    'Linux x86_64:0'|'Linux x86_64:1'|'Linux aarch64:1') ;;
    *) echo 'c4-sparse-worker: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a standard stage-2 image}
runtime=${2:-vm/build/c4/samaltak}
out=${OUT:-build}/c4-sparse-worker
mkdir -p "$out"
cap=${C4_WORKER_CAP:-128}
for mode in ${C4_WORKER_MODES:-weak strong}; do
    case "$mode" in weak|strong|dense) ;; *) exit 2 ;; esac
    code=$(sed -e "s/Smalltalk at: #C4WorkerSlots/${C4_WORKER_SLOTS:-1048576}/" \
        -e "s/Smalltalk at: #C4WorkerMode/#$mode/" \
        -e "s/C4WORKERROUNDS/${C4_WORKER_ROUNDS:-32}/" \
        -e "s/C4WORKERDELAY/${C4_WORKER_DELAY:-75}/" tests/vm/c4-live/sparse-worker.st)
    log=$out/$mode
    if ! SAMALTAK_C4_STATS=1 timeout -k 2 90 "$runtime" --c4 --jit none --eden 1 --max-heap "$cap" \
        "$image" --headless --eval "$code" >"$log.out" 2>"$log.err" ||
        ! grep -Fxq 'C4 sparse worker ok' "$log.out" ||
        ! awk -v cap="$cap" '
            /^c4: phase=/ || /^c4-publish:/ {
                for (i = 2; i <= NF; ++i) {
                    split($i, kv, "=")
                    stat[kv[1]] = kv[2] + 0
                }
            }
            END {
                if (stat["cycles_completed"] < 2 || stat["reused"] < 1 ||
                    stat["weak_cleared"] < 1 || stat["reclaimed_bytes"] < 1048576 ||
                    !("failed" in stat) || stat["failed"] != 0 ||
                    stat["high_water_bytes"] > cap * 1048576 ||
                    stat["max_refs"] > 69 || stat["max_chunk_init_refs"] > 64 ||
                    stat["chunk_inits"] < 2) exit 1
            }
        ' "$log.err"; then
        cat "$log.out" "$log.err" >&2
        exit 1
    fi
    echo "c4-sparse-worker: $mode passed"
    grep -E '^c4: phase=|^c4-publish:' "$log.err"
done
