#!/bin/sh
# Usage: [OUT=build] [VM=platform-vm] [C4_VM=headless-vm] [LEGACY_VM=baseline-vm]
#        [COMPARE_LEGACY=1] tests/vm/c4-live/run.sh [latency]
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m):${C4_ARM64_VALIDATION:-0}" in
    'Linux x86_64:0'|'Linux x86_64:1'|'Linux aarch64:1') ;;
    *) echo 'c4-live: skipped (requires Linux x86-64)'; exit 0 ;;
esac
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != latency ]; }; then
    echo 'usage: tests/vm/c4-live/run.sh [latency]' >&2
    exit 2
fi

out=${OUT:-build}/c4-live
image=$out/mini.image
cap_mb=64
eden_mb=1
mkdir -p "$out"

fail() {
    echo "c4-live: $* (logs in $out)" >&2
    exit 1
}

if [ -z "${VM:-}" ]; then
    "${MAKE:-make}" -C vm NO_PLATFORM=
    [ -f vm/build/.variant-platform ] || fail 'mini image builder requires a platform VM (SDL3)'
    VM=vm/build/samaltak
fi
if [ -z "${C4_VM:-}" ]; then
    "${MAKE:-make}" -C vm BUILD=build/c4 NO_PLATFORM=1
    C4_VM=vm/build/c4/samaltak
fi
legacy_vm=${LEGACY_VM:-$C4_VM}

# ImageBuilder uses platform file primitives, but the run itself is headless.
unset SAMALTAK_C4_STATS SAMALTAK_VERIFY_GC SAMALTAK_VERIFY_MARK
rm -f "$image"
if ! PACKAGES= timeout -k 2 180 boot/build-image.sh vm/tests/mini "$image" "$VM" >"$out/boot.log" 2>&1 ||
    [ ! -s "$image" ]; then
    cat "$out/boot.log" >&2
    fail 'could not build mini image'
fi

run_vm() { # vm log-name test vm-options...
    runtime=$1 log=$2 fixture=$3
    shift 3
    rc=0
    timeout -k 2 90 "$runtime" "$@" --eden "$eden_mb" --max-heap "$cap_mb" "$image" --headless "$fixture" \
        >"$out/$log.out" 2>"$out/$log.err" || rc=$?
    if [ "$rc" -ne 0 ]; then
        cat "$out/$log.out" "$out/$log.err" >&2
        fail "$log exited $rc"
    fi
}

check_stdout() { # log-name expected-file (or - for stdin)
    diff -u "$2" "$out/$1.out" || fail "$1 stdout mismatch"
}

latency() { # label vm vm-options...
    label=$1 runtime=$2
    shift 2
    run_vm "$runtime" "$label-latency" C4Latency "$@"
    check_stdout "$label-latency" - <<'EXPECTED'
--- C4Latency
checksum: 7200
EXPECTED
    # Keep raw samples in the .err file; summarize fixed-size batches, not whole-process time.
    awk '$1 == "latency_us" && NF == 2 && $2 ~ /^[0-9]+$/ { print $2 }' "$out/$label-latency.err" >"$out/$label-latency.us"
    [ "$(wc -l <"$out/$label-latency.us")" -eq 1000 ] || fail "$label did not report 1000 latency samples"
    LC_ALL=C sort -n "$out/$label-latency.us" | awk -v label="$label" '
        NR == 500 { p50 = $1 }
        NR == 950 { p95 = $1 }
        NR == 990 { p99 = $1 }
        NR == 999 { p999 = $1 }
        END {
            printf "%s batch latency (us, n=%d): p50=%d p95=%d p99=%d p99.9=%d max=%d\n",
                label, NR, p50, p95, p99, p999, $1
        }
    '
}

# Preserve the x86 default-tier smoke while opting into ARM64 explicitly.
run_c4() {
    if [ "${C4_ARM64_VALIDATION:-0}" = 1 ]; then
        "$@" --c4 --jit none
    else
        "$@" --c4
    fi
}

if [ "${1:-}" = latency ]; then
    latency legacy "$legacy_vm" --jit none
    run_c4 latency c4 "$C4_VM"
    exit 0
fi

expect_fatal() { # log-name diagnostic vm-args...
    log=$1 diagnostic=$2
    shift 2
    rc=0
    timeout -k 2 10 "$C4_VM" "$@" >"$out/$log.out" 2>"$out/$log.err" || rc=$?
    if [ "$rc" -ne 70 ] || ! grep -Fxq "samaltak: fatal: $diagnostic" "$out/$log.err"; then
        cat "$out/$log.out" "$out/$log.err" >&2
        fail "$log: expected rejection, exited $rc"
    fi
}

if [ "${C4_ARM64_VALIDATION:-0}" = 1 ]; then
    expect_fatal c4-jit-rejected 'C4 on ARM64 requires explicit --jit none' \
        --c4 --jit opt "$image" --headless C4Pressure
fi
expect_fatal c4-nonheadless-rejected '--c4 requires --headless' --c4 "$image"

run_c4 run_vm "$C4_VM" c4-oom C4OOM
check_stdout c4-oom - <<'EXPECTED'
--- C4OOM
Error: basicNew: failed 1
C4 OOM ok
EXPECTED

SAMALTAK_C4_STATS=1 run_c4 run_vm "$C4_VM" c4-pressure C4Pressure
# C4Pressure accounts for 128 * 384 * 4 KiB = 192 MiB of successful
# allocations, excluding the live graph and frame objects.
check_stdout c4-pressure - <<'EXPECTED'
--- C4Pressure
payload bytes: 201326592
C4 pressure ok
EXPECTED
if ! awk -v cap="$((cap_mb * 1024 * 1024))" '
    /^c4: phase=/ {
        count++
        for (i = 2; i <= NF; ++i) {
            split($i, pair, "=")
            if (pair[2] ~ /^[0-9]+$/) stat[pair[1]] = pair[2] + 0
        }
    }
    END {
        # At 3x cap allocated and at most 1x still in the arena, at least 2x was reclaimed.
        if (count != 1 || stat["allocated"] < 49152 || stat["reused"] <= 1024 ||
            stat["cycles_completed"] < 2 || stat["reclaimed_bytes"] < 2 * cap ||
            !("failed" in stat) || stat["failed"] != 0 ||
            stat["high_water_bytes"] <= 0 || stat["high_water_bytes"] > cap) exit 1
    }
' "$out/c4-pressure.err"; then
    cat "$out/c4-pressure.err" >&2
    fail 'missing C4 statistics or insufficient collection, reclamation, or reuse'
fi
grep '^c4: phase=' "$out/c4-pressure.err"

if [ "${COMPARE_LEGACY:-0}" = 1 ]; then
    run_vm "$legacy_vm" legacy-pressure C4Pressure --jit none
    check_stdout legacy-pressure "$out/c4-pressure.out"
fi

# Generic interpreter/kernel coverage, limited to the primitives supported by C4.
for test in Arith Float Strings Closures Unwind Context Perform; do
    run_c4 run_vm "$C4_VM" "c4-$test" "$test"
    check_stdout "c4-$test" "vm/tests/expected/$test.txt"
done
echo 'c4-live: guards, pressure, and kernel smoke passed'
