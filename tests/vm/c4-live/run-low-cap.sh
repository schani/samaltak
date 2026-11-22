#!/bin/sh
# Usage: tests/vm/c4-live/run-low-cap.sh STANDARD_STAGE2_IMAGE [C4_VM] [c4|c4-moving|c4-moving-forward]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m)" in
    'Linux x86_64') ;;
    *) echo 'c4-low-cap: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a standard stage-2 image}
runtime=${2:-vm/build/c4/samaltak}
mode=${3:-c4}
out=${OUT:-build}/c4-low-cap
case "$mode" in
    c4) ;;
    c4-moving) out=$out-moving ;;
    c4-moving-forward) out=$out-moving-forward ;;
    *) echo 'c4-low-cap: expected c4, c4-moving, or c4-moving-forward' >&2; exit 2 ;;
esac

# Run the same two tests, then check legacy collector counters in that process.
probe="
    | result counters |
    result := TestCase runNamed: #('ByteSearchTest').
    counters := Smalltalk vm primStatistics.
    (counters first = 0 and: [counters second = 0])
        ifFalse: [self error: 'legacy collection in C4'].
    Smalltalk quit: (result hasPassed ifTrue: [0] ifFalse: [1])"
mkdir -p "$out"
if ! SAMALTAK_C4_STATS=1 timeout -k 2 90 "$runtime" "--$mode" --jit none --eden 1 --max-heap 128 \
    "$image" --headless --eval "$probe" >"$out/run.out" 2>"$out/run.err" ||
    ! grep -Eq '^2 run, 2 passed, 0 failed, 0 errors in [0-9]+ ms$' "$out/run.out" ||
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
                stat["high_water_bytes"] <= 0 || stat["high_water_bytes"] > 134217728) exit 1
        }
    ' "$out/run.err"; then
    cat "$out/run.out" "$out/run.err" >&2
    exit 1
fi
echo "c4-low-cap: $mode (legacy GC counters zero)"
cat "$out/run.out"
grep '^c4: phase=' "$out/run.err"
