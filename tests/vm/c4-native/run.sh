#!/bin/sh
# Usage: [OUT=build] [VM=path/to/samaltak] [RUNS=10] tests/vm/c4-native/run.sh [stage2.image]
set -eu
cd "$(dirname "$0")/../../.."
src=tests/vm/c4-native
root=${OUT:-build}
out=$root/c4-native-test
vm=${VM:-vm/build/samaltak}
image=${1:-"$root/samaltak.image"}
runs=${RUNS:-1}
if [ "$#" -gt 1 ] || ! [ "$runs" -gt 0 ] 2>/dev/null; then
    echo 'usage: RUNS=<positive integer> tests/vm/c4-native/run.sh [stage2.image]' >&2
    exit 2
fi
case "$out" in
    *"'"*) echo "c4-native: OUT must not contain a single quote" >&2; exit 2 ;;
esac

mkdir -p -- "$out"
if ! timeout -k 2 60 "$vm" "$image" --headless \
    --load "$src/C4NativeArena.st" --load "$src/C4NativeTest.st" \
    --eval "[(VMTranslator modules: {C4NativeArena. C4NativeTest} header: 'c4_native') writeTo: '$out'. 'c4-native translated'] on: Error do: [:e | e messageText]" \
    >"$out/translate.log" 2>&1 || ! grep -qx "'c4-native translated'" "$out/translate.log"; then
    cat "$out/translate.log" >&2
    exit 1
fi

# Word splitting allows standard compiler/linker flag lists (including -fsanitize=...).
${CC:-cc} -std=gnu11 -D_GNU_SOURCE -pthread -Wall -Wextra -Wno-unused-parameter ${CFLAGS:--O2 -g} \
    "$out/c4_native_arena.c" "$out/c4_native_test.c" ${LDFLAGS:-} -o "$out/c4-native-test"

i=0
while [ "$i" -lt "$runs" ]; do
    timeout -k 2 30 "$out/c4-native-test"
    i=$((i + 1))
done
