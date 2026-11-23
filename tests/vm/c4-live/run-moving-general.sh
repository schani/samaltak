#!/bin/sh
# Usage: tests/vm/c4-live/run-moving-general.sh STANDARD_STAGE2_IMAGE [C4_VM]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m):${C4_ARM64_VALIDATION:-0}" in
    'Linux x86_64:0'|'Linux x86_64:1'|'Linux aarch64:1') ;;
    *) echo 'c4-moving-general: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a standard stage-2 image}
runtime=${2:-vm/build/c4/samaltak}
out=${OUT:-build}/c4-moving-general
mkdir -p "$out"
if ! SAMALTAK_C4_STATS=1 timeout -k 2 45 "$runtime" --c4-moving --jit none --eden 1 --max-heap 128 \
    "$image" --headless --eval "$(cat tests/vm/c4-live/moving-general.st)" >"$out/run.out" 2>"$out/run.err" ||
    ! grep -Fxq 'C4 moving Associations and Messages ok' "$out/run.out" ||
    ! awk '
        /^c4(-moving)?:/ {
            lines++
            for (i = 2; i <= NF; ++i) {
                split($i, kv, "=")
                stat[kv[1]] = kv[2] + 0
            }
        }
        END {
            if (lines != 2 || stat["moved_association"] < 1 || stat["moved_message"] < 1 ||
                stat["cycles_completed"] < 2 || stat["weak_cleared"] < 2 || stat["failed"] ||
                stat["released"] < 1 || stat["source_reused"] < 1 ||
                stat["max_inspected"] < 1 || stat["max_inspected"] > 64 ||
                stat["max_copied"] < 32 || stat["max_copied"] > 4096) exit 1
        }
    ' "$out/run.err"; then
    cat "$out/run.out" "$out/run.err" >&2
    exit 1
fi
cat "$out/run.out" "$out/run.err"
