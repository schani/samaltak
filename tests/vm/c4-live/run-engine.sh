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
    -UNDEBUG -DSAMALTAK_NO_PLATFORM -DSAMALTAK_C4_TEST -Ivm -Ivm/gen \
    vm/c4_heap.c tests/vm/c4-live/engine_test.c -o "$tmp/engine-test"
for test in close shadow oracle; do
    timeout -k 1 15 "$tmp/engine-test" "$test"
    echo "c4-engine: $test passed"
done
