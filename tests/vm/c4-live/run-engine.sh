#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
case "$(uname -s -m)" in
    'Linux x86_64') ;;
    *) echo 'c4-engine: skipped (requires Linux x86-64)'; exit 0 ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
# Allow callers to supply sanitizer flags and a different C compiler.
${CC:-cc} ${CFLAGS:--O2} -std=gnu11 -Wall -Wextra -Werror -pthread \
    -UNDEBUG -DSAMALTAK_NO_PLATFORM -DSAMALTAK_C4_TEST -Ivm -I"${SAMALTAK_VM_GEN:-vm/gen}" \
    vm/c4_heap.c tests/vm/c4-live/engine_test.c -o "$tmp/engine-test"
for test in close cache-close shadow oracle weak-close weak-shadow weak-idle lazy-publish lazy-mark lazy-enumeration pinned-fit pinned-clear-split moving moving-general moving-oracle moving-saturated interval-oracle interval-saturated \
    code-bytes forward-strong forward-claimed forward-weak forward-weak-read forward-after-ack forward-pinned-overlap enumeration enumeration-limit enumeration-log-limit cache-enumeration raw-read-ok; do
    timeout -k 1 15 "$tmp/engine-test" "$test"
    echo "c4-engine: $test passed"
done

# Each invalid scope must fail at its contract check, not by timeout or
# by a stale read after the poll or forwarding has already run.
ulimit -c 0
reject() {
    rc=0
    timeout -k 1 15 "$tmp/engine-test" "$1" >"$tmp/raw-read.log" 2>&1 || rc=$?
    if [ "$rc" -ne 134 ] || ! grep -Fxq "C4 heap invariant: $2" "$tmp/raw-read.log"; then
        cat "$tmp/raw-read.log" >&2
        exit 1
    fi
    echo "c4-engine: $1 rejected"
}
reject raw-read-unpaired 'unbalanced synchronous raw read exit'
reject raw-read-nest 'invalid synchronous raw read entry'
reject raw-read-start 'cycle start during synchronous raw read'
reject raw-read-close 'close poll during synchronous raw read'
reject raw-read-move 'relocation poll during synchronous raw read'
reject raw-read-forward 'forwarding during synchronous raw read'
reject interval-reject-class 'invalid movable role in class store'
reject interval-reject-literals 'moving handle in raw method storage'
reject interval-reject-bytes 'moving handle in raw method storage'
reject interval-reject-borrow 'code storage must be a live pinned raw body'
reject interval-reject-wrong-class 'unsupported format, extent or weak layout'
