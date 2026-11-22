#!/bin/sh
# Usage: run-moving-forward.sh STAGE2_IMAGE [C4_VM] [enabled|old]
# Set C4_MOVING_FORWARD_WITNESS=1 only with the link-only witness VM.
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m)" in
    'Linux x86_64') ;;
    *) echo 'c4-moving-forward: skipped (requires Linux x86-64)'; exit 0 ;;
esac
image=${1:?pass a full stage-2 image}
runtime=${2:-vm/build/c4/samaltak}
expect=${3:-enabled}
case "$expect" in
    enabled) interval=1 ;;
    old) interval=0 ;;
    *) echo 'c4-moving-forward: expected enabled or old' >&2; exit 2 ;;
esac
out=${OUT:-build}/c4-moving-forward-$expect
mkdir -p "$out"
unset DISPLAY WAYLAND_DISPLAY
ulimit -c 0

fail() {
    echo "c4-moving-forward: failed ($1)" >&2
    cat "$out/$1.log" >&2
    exit 1
}
run() {
    name=$1
    fixture=$2
    shift 2
    SAMALTAK_C4_STATS=1 timeout -k 2 90 "$runtime" "$@" --eden 1 --max-heap 128 \
        "$image" --headless --eval "$(cat "tests/vm/c4-live/$fixture.st")" >"$out/$name.log" 2>&1 ||
        fail "$name"
}

for tier in baseline opt; do
    rc=0
    timeout -k 2 30 "$runtime" --c4-moving-forward --jit "$tier" "$image" --headless \
        >"$out/reject-$tier.log" 2>&1 || rc=$?
    [ "$rc" = 70 ] && grep -Fxq 'samaltak: fatal: --c4-moving-forward requires --jit none' \
        "$out/reject-$tier.log" || fail "reject-$tier"
done
run default pointer-forward-moving --c4-moving --jit none
grep -Fxq 'pointer moving rejects ok' "$out/default.log" || fail default

# Exercise the opt-in with no explicit tier: it must default to the interpreter.
# The fixture verifies legacy GC counters, identity/hash, exact enumeration,
# weak clearance, and image-side tier, class and method-backing rejection.
run live moving-forward --c4-moving-forward
grep -Fxq 'moving forward ok' "$out/live.log" || fail live
awk -v interval="$interval" '
    {
        for (k in s) delete s[k]
        for (i=2; i<=NF; ++i) {
            split($i, kv, "=")
            if (kv[2] ~ /^[0-9]+$/) s[kv[1]] = kv[2]+0
        }
    }
    /^c4: phase=/ {
        gc++
        good_gc = ("failed" in s && s["failed"] == 0 && s["cycles_completed"] >= 3 &&
               s["weak_cleared"] >= 2 && s["reused"] > 0 &&
               s["high_water_bytes"] > 0 && s["high_water_bytes"] <= 134217728)
    }
    /^c4-moving:/ {
        move++
        good_move = (s["moved_point"] > 0 && s["released"] > 0 && s["source_reused"] > 0 &&
                 s["reserve_bytes"] == 16384 && s["max_inspected"] > 0 &&
                 s["max_inspected"] <= 64 && s["max_copied"] >= 32 && s["max_copied"] <= 4096)
    }
    /^c4-interval:/ {
        image++
        good_image = ("enabled" in s && s["enabled"] == interval &&
                  (interval ? s["reserve_bytes"] == 16384 : !("pool_bytes" in s)))
    }
    /^c4-jit:/ {
        interpreter++
        good_interpreter = ("checkpoints" in s && s["checkpoints"] == 0)
    }
    END {
        exit !(gc == 1 && move == 1 && image == 1 && interpreter == 1 &&
               good_gc && good_move && good_image && good_interpreter)
    }
' "$out/live.log" || fail live
if [ "${C4_MOVING_FORWARD_WITNESS:-0}" = 1 ]; then
    grep -Eq '^c4-witness: two-slot forwarded Point physically moved .* donor resolves to same hashed header$' \
        "$out/live.log" || fail live
fi
cat "$out/live.log"
echo "c4-moving-forward: $expect image passed (interpreter, identity, weak and enumeration)"
