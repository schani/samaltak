#!/bin/sh
# Usage: tests/vm/c4-live/run-become.sh STANDARD_STAGE2_IMAGE [C4_VM]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m)" in
    'Linux x86_64') ;;
    *) echo 'c4-become: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a standard stage-2 image}
runtime=${2:-vm/build/c4/samaltak}
legacy=${LEGACY_VM:-"$runtime"}
out=${OUT:-build}/c4-become
mkdir -p "$out"

fail() {
    cat "$out/$1.log" >&2
    echo "c4-become: $1 failed" >&2
    exit 1
}

for mode in legacy c4 c4-moving; do
    case "$mode" in
        legacy) set -- "$legacy" --jit none ;;
        *) set -- "$runtime" "--$mode" ;;
    esac
    SAMALTAK_C4_STATS=1 timeout -k 2 45 "$@" --eden 1 --max-heap 512 "$image" \
        --headless --eval "$(cat tests/vm/c4-live/become.st)" >"$out/$mode.log" 2>&1 ||
        fail "$mode"
    grep -Fxq 'become aliases ok' "$out/$mode.log" || fail "$mode"
    if [ "$mode" != legacy ]; then
        awk '
          /^c4:/ {
            count++
            for (i = 2; i <= NF; ++i) {
              split($i, kv, "=")
              stat[kv[1]] = kv[2] + 0
            }
          }
          END {
            exit (count != 1 || stat["cycles_completed"] < 3 || stat["reused"] < 1 ||
                  stat["weak_cleared"] < 1 || stat["failed"] != 0)
          }
        ' "$out/$mode.log" || fail "$mode"
    fi
done

timeout -k 2 45 "$runtime" --c4 --eden 1 --max-heap 512 "$image" --headless \
    --eval "$(cat tests/vm/c4-live/become-rejections.st)" >"$out/rejections.log" 2>&1 ||
    fail rejections
grep -Fxq 'become rejections ok' "$out/rejections.log" || fail rejections

# Gate the regressions without depending on an unrelated StringTest wall-clock assertion.
timeout -k 2 45 "$runtime" --c4 --eden 1 --max-heap 512 "$image" --headless --eval '
    | result |
    result := TestResult new.
    #(testSqueakAndPharoProtocol testWideStrings) do: [:selector |
        result runCase: (StringTest new setTestSelector: selector; yourself)].
    result printString
' >"$out/strings.log" 2>&1 || fail strings
grep -Fq '2 run, 2 passed, 0 failed, 0 errors' "$out/strings.log" || fail strings
echo 'c4-become: legacy/live/moving aliases, rejection gates and both StringTest regressions passed'
