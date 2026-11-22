#!/bin/sh
# Usage: tests/vm/c4-live/run-moving.sh STANDARD_STAGE2_IMAGE [C4_VM]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m)" in
    'Linux x86_64') ;;
    *) echo 'c4-moving: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a standard stage-2 image}
runtime=${2:-vm/build/c4/samaltak}
out=${OUT:-build}/c4-moving
mkdir -p "$out"
if ! SAMALTAK_C4_STATS=1 timeout -k 2 45 "$runtime" --c4-moving --eden 1 --max-heap 128 \
    "$image" --headless --eval "$(cat tests/vm/c4-live/moving.st)" >"$out/run.out" 2>"$out/run.err" ||
    ! grep -Fxq 'C4 moving Points ok' "$out/run.out" ||
    ! awk '
        /^c4-moving:/ {
            count++
            for (i = 2; i <= NF; ++i) {
                split($i, kv, "=")
                stat[kv[1]] = kv[2] + 0
            }
        }
        END {
            if (count != 1 || stat["moved"] < 1 || stat["released"] < 1 ||
                stat["source_reused"] < 1 || stat["max_inspected"] < 1 ||
                stat["max_inspected"] > 64 || stat["max_copied"] < 32 ||
                stat["max_copied"] > 4096) exit 1
        }
    ' "$out/run.err"; then
    cat "$out/run.out" "$out/run.err" >&2
    exit 1
fi
grep '^c4-moving:' "$out/run.err"
echo 'c4-moving: live identity, stores, weak edges and region reuse passed'
