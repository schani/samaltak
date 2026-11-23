#!/usr/bin/env bash
# Explicit validation entry point. A stock VM must reject both C4 modes.
set -euo pipefail
cd "$(dirname "$0")/../../.."
runtime=${1:?pass the C4_ARM64_INTERPRETER=1 VM}
stock=${2:?pass the unmodified-policy arm64 VM}
bootstrap=${3:?pass the platform image builder (headless invocation only)}
image=${4:?pass the standard stage-2 image}
old=${5:?pass the compatibility stage-2 image}
shift 5
case "$(uname -s -m):${RUN_UNDER_QEMU:-0}" in
    'Linux aarch64:0') printf '%s\n' 'validation: native Linux arm64' ;;
    'Linux x86_64:1') printf '%s\n' 'validation: QEMU only (not native evidence)' ;;
    *) echo 'unsupported validation host' >&2; exit 2 ;;
esac
export OUT=${OUT:-build/c4-arm64-validation}
export C4_ARM64_VALIDATION=1
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_VERIFY_GC SAMALTAK_VERIFY_MARK SAMALTAK_C4_STATS
ulimit -c 0
d=tests/vm/c4-live
mkdir -p "$OUT/logs"
policy() {
    local mode tier vm log
    deny() {
        local vm=$1 msg=$2 rc=0 got
        shift 2
        got=$(timeout -k 2 10 "$vm" "$@" 2>&1) || rc=$?
        printf 'rc=%s %s\n' "$rc" "$got"
        [[ $rc == 70 && $got == "samaltak: fatal: $msg" ]]
    }
    for mode in --c4 --c4-moving; do
        deny "$stock" '--c4 requires Linux x86-64 with NO_PLATFORM=1 or C4_PLATFORM_FILES=1' \
            "$mode" --jit none "$image" --headless || return 1
        deny "$runtime" '--c4 requires --headless' "$mode" --jit none "$image" || return 1
        deny "$runtime" '--c4 requires a positive --eden threshold' "$mode" --jit none --eden 0 "$image" --headless || return 1
        deny "$runtime" 'C4 on ARM64 requires explicit --jit none' \
            "$mode" "$image" --headless || return 1
        # VM options must precede the image; an image argument is not an opt-in.
        deny "$runtime" 'C4 on ARM64 requires explicit --jit none' \
            "$mode" "$image" --headless --jit none || return 1
        for tier in baseline opt; do
            deny "$runtime" 'C4 on ARM64 requires explicit --jit none' \
                "$mode" --jit "$tier" "$image" --headless || return 1
        done
        log="$OUT/policy-${mode#--}-none.log"
        SAMALTAK_C4_STATS=1 timeout -k 2 30 "$runtime" "$mode" --jit none "$image" --headless --eval "
                | base opt |
                Smalltalk vm jitMode = #none ifFalse: [Smalltalk quit: 1].
                base := [Smalltalk vm jitMode: #baseline. false] on: Error do: [:e | true].
                opt := [Smalltalk vm jitMode: #opt. false] on: Error do: [:e | true].
                (base and: [opt and: [Smalltalk vm jitMode = #none]]) ifFalse: [Smalltalk quit: 1].
                'C4 arm64 interpreter policy ok'
        " >"$log" 2>&1 || return 1
        grep -Fxq "'C4 arm64 interpreter policy ok'" "$log" || return 1
        grep -q '^c4: phase=' "$log" || return 1
        grep -Fxq 'c4-jit: checkpoints=0 publishing_exits=0' "$log" || return 1
    done
    for vm in "$stock" "$runtime"; do
        deny "$vm" '--c4-moving-forward requires Linux x86-64 with NO_PLATFORM=1' \
            --c4-moving-forward --jit none "$image" --headless || return 1
    done
    SAMALTAK_C4_STATS=1 timeout -k 2 30 "$runtime" --jit none "$image" --headless \
        --eval "'arm64 legacy interpreter ok'" >"$OUT/legacy.log" 2>&1 || return 1
    grep -Fxq "'arm64 legacy interpreter ok'" "$OUT/legacy.log" || return 1
    ! grep -q '^c4: phase=' "$OUT/legacy.log"
}
one() {
    case "$1" in
        policy) policy ;;
        translated-native) VM="$bootstrap" tests/vm/c4-native/run.sh "$image" ;;
        engine|stack-move) "$d/run-$1.sh" ;;
        mini) VM="$bootstrap" C4_VM="$runtime" "$d/run.sh" ;;
        context-old) OUT="$OUT/compat" "$d/run-context.sh" "$old" "$runtime" ;;
        interval-old) "$d/run-interval.sh" "$old" "$runtime" old ;;
        byte-pinned) "$d/run-low-cap.sh" "$image" "$runtime" c4 ;;
        byte-moving) "$d/run-low-cap.sh" "$image" "$runtime" c4-moving ;;
        weak|context|moving|moving-general|publish|become|pointer-forward|enumeration|cache|interval|span-pressure)
            "$d/run-$1.sh" "$image" "$runtime" ;;
        *) echo "unknown gate: $1" >&2; return 2 ;;
    esac
}
if [[ $# == 0 ]]; then
    set -- policy engine stack-move translated-native mini context context-old weak moving moving-general \
        publish become pointer-forward enumeration cache interval interval-old span-pressure byte-pinned byte-moving
fi
echo -e 'gate\tstatus\tseconds' >"$OUT/status.tsv"
failed=0
for gate in "$@"; do
    rc=0
    start=$SECONDS
    {
        cat /proc/pressure/cpu
        TIMEFORMAT='%3R real %3U user %3S sys'
        time one "$gate"
    } >"$OUT/logs/$gate.log" 2>&1 || rc=$?
    printf '%s\t%d\t%d\n' "$gate" "$rc" "$((SECONDS - start))" | tee -a "$OUT/status.tsv"
    ((rc == 0)) || { failed=1; cat "$OUT/logs/$gate.log"; }
done
exit "$failed"
