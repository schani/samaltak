#!/bin/sh
# Usage: tests/vm/c4-live/run-weak.sh STANDARD_STAGE2_IMAGE [C4_VM]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m):${C4_ARM64_INTERPRETER_TEST:-0}" in
    'Linux x86_64:0'|'Linux x86_64:1'|'Linux aarch64:1') ;;
    *) echo 'c4-weak: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a standard stage-2 image built by the platform VM}
runtime=${2:-vm/build/c4/samaltak}
out=${OUT:-build}/c4-weak
mkdir -p "$out"
if ! SAMALTAK_C4_STATS=1 timeout -k 2 30 "$runtime" --c4 --eden 8 --max-heap 128 \
    "$image" --headless --eval "$(cat tests/vm/c4-live/weak.st)" >"$out/run.out" 2>"$out/run.err" ||
    ! grep -Fxq "C4 weak and idle finalization ok" "$out/run.out" ||
    ! awk '
        /^c4: phase=/ {
            count++
            for (i = 2; i <= NF; ++i) {
                split($i, kv, "=")
                if (kv[2] ~ /^[0-9]+$/) stat[kv[1]] = kv[2] + 0
            }
        }
        END {
            # The weak-only ByteArray is over 2 MiB, with the 8 MiB trigger still live.
            if (count != 1 || stat["cycles_completed"] < 1 || stat["weak_cleared"] < 1 ||
                stat["reclaimed_bytes"] < (2097153 + 16) ||
                !("failed" in stat) || stat["failed"] != 0) exit 1
        }
    ' "$out/run.err"; then
    cat "$out/run.out" "$out/run.err" >&2
    exit 1
fi
echo 'c4-weak: standard image, weak reclamation, and idle finalization passed'
