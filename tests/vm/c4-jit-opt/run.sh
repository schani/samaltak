#!/bin/sh
# Linux x86-64. Use the normal NO_PLATFORM=1 VM and an unmodified stage-2 image.
set -eu
cd "$(dirname "$0")/../../.."
image=${1:?pass the stage-2 image}
vm=${2:-vm/build/c4/samaltak}
out=${OUT:-build}/c4-jit-opt
fixtures=tests/vm/c4-jit-opt
mkdir -p "$out"
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_OPT_SLICE SAMALTAK_OPT_LOOP SAMALTAK_OPT_ADMISSION \
    SAMALTAK_OPT_TRACE SAMALTAK_OPT_SLICE_TRACE SAMALTAK_PERF_MAP SAMALTAK_C4_STATS
ulimit -c 0
run() {
    fixture=$1 heap=$2
    shift 2
    log="$out/$heap-$fixture.log"
    if ! timeout -k 2 75 "$vm" "--$heap" --jit opt "$@" "$image" --headless \
        --eval "$(cat "$fixtures/$fixture.st")" >"$log" 2>&1; then
        cat "$log" >&2
        return 1
    fi
}
for heap in c4 c4-moving; do
    # Defaults, no selection or reporting environment.
    run entries "$heap"
    grep -Fxq 'C4 automatic opt entries, exits and edits ok' "$out/$heap-entries.log"
    # Only the existing stats reporter is enabled; the ordinary thresholds are unchanged.
    SAMALTAK_C4_STATS=1 run pressure "$heap" --eden 1 --max-heap 96
    grep -Fxq 'C4 automatic opt pressure ok' "$out/$heap-pressure.log"
    awk -v moving="$heap" '
        /^c4-opt: / || /^c4: phase=/ || /^c4-moving: / {
            for (i = 2; i <= NF; i++) {
                split($i, kv, "=")
                data[kv[1]] = kv[2] + 0
            }
        }
        END {
            if (!data["compiled"] || !data["returns"] || data["entries"] < data["returns"] ||
                data["cycles_completed"] < 2 || !data["weak_cleared"] || !data["reused"] ||
                data["failed"] || (moving == "c4-moving" && (!data["moved"] || !data["released"])))
                exit 1
        }
    ' "$out/$heap-pressure.log"
done
echo 'c4-opt: automatic tier-up, side exits, edits, weak pressure and moving passed'
