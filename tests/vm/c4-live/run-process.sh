#!/bin/sh
# Usage: tests/vm/c4-live/run-process.sh STANDARD_STAGE2_IMAGE C4_VM
set -eu
cd "$(dirname "$0")/../../.."
image=${1:?pass a standard stage-2 image}
runtime=${2:?pass the ordinary NO_PLATFORM=1 C4 VM}
out=${OUT:-build}/c4-process
mkdir -p "$out"
unset DISPLAY WAYLAND_DISPLAY
export SAMALTAK_C4_STATS=1
# Report counters from the very same VM that ran the suite.
suite=$(cat <<'ST'
| result stats |
result := ProcessTest run.
stats := Smalltalk vm statistics.
Smalltalk vm stdoutWrite: 'process-gc: ', stats fullGCs printString, ' ', stats scavenges printString, (String with: Character lf).
Smalltalk quit: ((result hasPassed and: [result skipped isEmpty and: [result runCount > 0]])
	ifTrue: [0] ifFalse: [1])
ST
)
for jit in none baseline; do
    for mode in legacy c4 c4-moving; do
        set -- --jit "$jit"
        if [ "$jit" = baseline ]; then set -- "$@" --jit-threshold 0; fi
        if [ "$mode" != legacy ]; then set -- --"$mode" "$@"; fi
        log="$out/$mode-$jit.log"
        if ! timeout -k 2 90 "$runtime" "$@" "$image" --headless --eval "$suite" >"$log" 2>&1; then
            cat "$log" >&2
            exit 1
        fi
        if [ "$mode" = legacy ]; then
            grep -Eq '^process-gc: [1-9][0-9]* [0-9]+$' "$log"
        else
            grep -Fxq 'process-gc: 0 0' "$log"
            awk '
                /^c4: phase=/ {
                    count++
                    for (i = 2; i <= NF; ++i) {
                        split($i, kv, "=")
                        stat[kv[1]] = kv[2] + 0
                    }
                }
                END {
                    if (count != 1 || stat["cycles_completed"] < 2 ||
                        stat["weak_cleared"] < 1 || stat["reused"] < 1 ||
                        !("failed" in stat) || stat["failed"] != 0) exit 1
                }
            ' "$log"
        fi
        printf '%s (%s): ' "$mode" "$jit"
        grep '^[1-9][0-9]* run, ' "$log"
    done
done
