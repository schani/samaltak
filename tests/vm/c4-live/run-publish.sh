#!/bin/sh
# Usage: tests/vm/c4-live/run-publish.sh STANDARD_STAGE2_IMAGE [C4_VM]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m):${C4_ARM64_VALIDATION:-0}" in
    'Linux x86_64:0'|'Linux x86_64:1'|'Linux aarch64:1') ;;
    *) echo 'c4-publish: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a standard stage-2 image}
runtime=${2:-vm/build/c4/samaltak}
out=${OUT:-build}/c4-publish
mkdir -p "$out"
for slots in 8192 1048576; do
    code=$(sed "s/Smalltalk at: #C4PublishSlots/$slots/" tests/vm/c4-live/publish.st)
    log=$out/$slots
    if ! SAMALTAK_C4_STATS=1 timeout -k 2 90 "$runtime" --c4 --jit none --eden 1 --max-heap 128 \
        "$image" --headless --eval "$code" >"$log.out" 2>"$log.err" ||
        ! grep -Fxq 'C4 bounded publication ok' "$log.out" ||
        ! awk '
            /^c4:/ {
                for (i = 2; i <= NF; ++i) {
                    split($i, kv, "=")
                    stat[kv[1]] = kv[2] + 0
                }
            }
            /^c4-publish:/ {
                count++
                for (i = 2; i <= NF; ++i) {
                    split($i, kv, "=")
                    stat[kv[1]] = kv[2] + 0
                }
            }
            END {
                if (count != 1 || stat["max_refs"] < 1 || stat["max_refs"] > 69 ||
                    stat["max_chunk_init_refs"] < 1 || stat["max_chunk_init_refs"] > 64 ||
                    stat["chunk_inits"] < 2 || stat["cycles_completed"] < 2 ||
                    stat["weak_cleared"] < 1 || !("failed" in stat) || stat["failed"] != 0) exit 1
            }
        ' "$log.err"; then
        cat "$log.out" "$log.err" >&2
        exit 1
    fi
    printf '%s slots: ' "$slots"
    grep '^c4-publish:' "$log.err"
done
