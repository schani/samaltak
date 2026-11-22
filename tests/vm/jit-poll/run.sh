#!/bin/sh
# Linux: link the request/ack test against a translated NO_PLATFORM=1 build.
# Usage: [CC=cc] run.sh path/to/vm [object-dir [runner args...]]
# object-dir defaults to path/to/vm/build/obj-headless; runner can be QEMU.
set -eu
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
vm=$1
shift
objects=${1:-$vm/build/obj-headless}
if [ "$#" -gt 0 ]; then shift; fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
link_test() {
    "${CC:-cc}" -std=gnu11 -D_GNU_SOURCE -DSAMALTAK_NO_PLATFORM -I"$vm/gen" -I"$vm" "$here/requests.c" \
        "$objects"/gen/*.o "$@" \
        -Wl,--wrap=main,--wrap=platform_interface_poll -pthread -lm -o "$tmp/requests"
}
if [ -f "$objects/c4_heap.o" ]; then
    link_test "$objects/c4_heap.o"
else
    link_test
fi
"$@" "$tmp/requests"
