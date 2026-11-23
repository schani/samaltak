#!/bin/sh
# Usage: tests/vm/c4-live/run-span-pressure.sh STANDARD_STAGE2_IMAGE [C4_VM]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m)" in
    'Linux x86_64') ;;
    *) echo 'c4-span-pressure: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a standard stage-2 image}
runtime=${2:-vm/build/c4/samaltak}
out=${OUT:-build}/c4-span-pressure
mkdir -p "$out"
log=$out/run.log

# 16 refills of 4096 * 8184 bytes, in a 96 MiB arena. The fixture retains
# separators and checks both endpoint bytes and logical sizes of every object.
if ! SAMALTAK_C4_STATS=1 timeout -k 2 90 "$runtime" --c4 --jit none --eden 1 --max-heap 96 \
        "$image" --headless --eval "$(cat tests/vm/c4-live/span-pressure.st)" >"$log" 2>&1 ||
   ! grep -Fxq 'C4 span pressure ok' "$log" ||
   ! awk '
        /^c4: phase=/ {
            ++reports
            for (i = 2; i <= NF; ++i) {
                split($i, kv, "=")
                stat[kv[1]] = kv[2] + 0
            }
        }
        END {
            if (reports != 1 || !("failed" in stat) || stat["failed"] != 0 ||
                stat["cycles_completed"] < 16 || stat["reused"] < 65536 ||
                stat["reclaimed_bytes"] < 500000000 ||
                stat["high_water_bytes"] <= 0 || stat["high_water_bytes"] > 96 * 1048576) exit 1
        }
    ' "$log"; then
    cat "$log" >&2
    exit 1
fi
grep -E '^C4 span pressure ok$|^c4: phase=' "$log"
