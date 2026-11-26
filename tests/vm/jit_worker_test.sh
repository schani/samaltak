#!/bin/sh
# Usage: tests/vm/jit_worker_test.sh IMAGE [VM]
# The positive lane REQUIRES a real worker (two allowed CPUs on Linux).
set -eu
IMAGE=${1:?supply a full image}
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
VM=${2:-"$ROOT/vm/build/samaltak"}
TMP=$(mktemp -d)
LOG=$TMP/log
trap 'rm -rf "$TMP"' EXIT
unset DISPLAY WAYLAND_DISPLAY SAMALTAK_OPT_TRACE SAMALTAK_OPT_SENDS SAMALTAK_OPT_LIMIT
export SAMALTAK_OPT_BG_TEST=1 SAMALTAK_VERIFY_GC=1
run() {
    result=$1; flags=$2; src=$3; shift 3
    if ! "$@" "$VM" --jit opt --jit-threshold 0 --jit-flags "$flags" "$IMAGE" --headless \
        --load "$ROOT/tests/vm/jit_worker.st" --eval \
        "[Profiler default stop. $src] on: Error do: [:e | Smalltalk vm stderrWrite: e messageText, (String with: Character lf). Smalltalk quit: 1]" >"$LOG" 2>&1 ||
        { [ "$result" = true ] && ! grep -Fxq true "$LOG"; }; then
        cat "$LOG" >&2
        echo "jit_worker_test: $src failed ($flags)" >&2
        exit 1
    fi
}
# Timer sampling can tier up an unrelated loop and take back the worker's scratch.
# Stop it in each process; drive scratch contention explicitly in its own lane.
run true eager,-inline 'JitWorkerProof fallback: -2'
run true eager,-inline,bg 'JitWorkerProof install. JitWorkerProof collections. JitWorkerProof invalidation. JitWorkerProof interleavedDiscards'
run true eager,-inline,bg 'JitWorkerProof scratchContention'
run quit eager,-inline,bg 'JitWorkerProof quitWithJob. Smalltalk quit: 1'
SAMALTAK_OPT_LIMIT=999999 run true eager,-inline,bg 'JitWorkerProof fallback: -1'
if [ "$(uname -s)" = Linux ] && command -v taskset >/dev/null 2>&1; then
    cpu=$(awk '/^Cpus_allowed_list:/ {split($2,c,/[-,]/); print c[1]}' /proc/self/status)
    run true eager,-inline,bg 'JitWorkerProof fallback: -1' taskset -c "$cpu"
fi
case $(uname -s) in
    Linux) link=-shared; ext=so ;;
    Darwin) link=-dynamiclib; ext=dylib ;;
    *) echo 'jit_worker_test: unsupported host' >&2; exit 1 ;;
esac
lib="$TMP/wrapped.$ext"
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror "$link" -fPIC -o "$lib" "$ROOT/tests/vm/wrapped_ffi_fixture.c"
SAMALTAK_NATIVE_GRANTS="wrapped|wrapped_step|i32(i32)|$lib" \
    run true eager,-inline,bg 'JitWorkerProof boundFfi'
echo 'jit_worker_test: real worker, stale discard, scratch contention, quit and synchronous fallback passed'
