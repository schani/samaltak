#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
image=${1:?pass the stage-2 image with the C4 enumeration bridge}
vm=${2:?pass the C4 headless VM}
out=${OUT:-build}/c4-jit-enumeration
mkdir -p "$out"
for mode in c4 c4-moving; do
    for fixture in enumeration code-roots; do
        case "$fixture" in
            enumeration) src=tests/vm/c4-live/enumeration.st; expected='heap enumeration ok' ;;
            code-roots) src=tests/vm/c4-jit-live/code-roots.st; expected='c4-jit code roots ok' ;;
        esac
        log=$out/$mode-$fixture.log
        SAMALTAK_C4_STATS=1 timeout -k 2 120 "$vm" "--$mode" --jit baseline --jit-threshold 0 --jit-osr 0 \
            --eden 1 --max-heap 128 "$image" --headless --eval "$(cat "$src")" c4-enum >"$log" 2>&1 ||
            { cat "$log"; exit 1; }
        grep -Fxq "$expected" "$log" || { cat "$log"; exit 1; }
        grep -Eq '^c4-jit: checkpoints=[1-9][0-9]* ' "$log" || { cat "$log"; exit 1; }
        if [ "$fixture" = code-roots ]; then
            awk '/^c4: phase=/ {for (i=2; i<=NF; ++i) {split($i, kv, "="); s[kv[1]]=kv[2]+0}
                ok=(s["cycles_completed"] >= 2 && s["weak_cleared"] > 0 && s["failed"] == 0)}
                END {exit !ok}' "$log" || { cat "$log"; exit 1; }
        fi
        echo "c4-jit $mode $fixture: passed"
        cat "$log"
    done
done
