#!/bin/sh
# Usage: tests/vm/c4-live/run-low-cap.sh STANDARD_STAGE2_IMAGE [C4_VM]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m)" in
    'Linux x86_64') ;;
    *) echo 'c4-low-cap: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a standard stage-2 image}
runtime=${2:-vm/build/c4/samaltak}
out=${OUT:-build}/c4-low-cap
mkdir -p "$out"
if ! SAMALTAK_C4_STATS=1 timeout -k 2 90 "$runtime" --c4 --eden 1 --max-heap 128 \
    "$image" --headless --test ByteSearchTest >"$out/run.out" 2>"$out/run.err" ||
    ! grep -Eq '^2 run, 2 passed, 0 failed, 0 errors' "$out/run.out" ||
    ! awk '
        /^c4: phase=/ {
            count++
            for (i = 2; i <= NF; ++i) {
                split($i, kv, "=")
                if (kv[2] ~ /^[0-9]+$/) stat[kv[1]] = kv[2] + 0
            }
        }
        END {
            if (count != 1 || stat["cycles_completed"] < 2 || stat["reused"] < 1 ||
                !("failed" in stat) || stat["failed"] != 0 ||
                stat["high_water_bytes"] > 134217728) exit 1
        }
    ' "$out/run.err"; then
    cat "$out/run.out" "$out/run.err" >&2
    exit 1
fi
cat "$out/run.out"
grep '^c4: phase=' "$out/run.err"
