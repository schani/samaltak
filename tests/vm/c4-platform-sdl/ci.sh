#!/bin/sh
# CI only. Never run against a desktop session.
set -eu
cd "$(dirname "$0")/../../.."
test "${CI:-}" = true || { echo 'C4 SDL display test is CI-only' >&2; exit 2; }
test -n "${DISPLAY:-}" || { echo 'C4 SDL CI: missing DISPLAY' >&2; exit 2; }
test "${SDL_VIDEO_DRIVER:-}" = x11
image=$(realpath "${1:?stage-2 image required}")
vm=vm/build/c4-sdl/samaltak
dir=tests/vm/c4-platform-sdl
tmp=$(mktemp -d)
pid=
cleanup() {
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; fi
    for file in "$tmp/no-display" "$tmp/dummy" "$tmp/out" "$tmp/err"; do [ ! -f "$file" ] || cat "$file"; done
    rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 2' INT TERM
${CC:-cc} -std=c11 -Wall -Wextra -o "$tmp/xpixel" "$dir/xpixel.c" -lX11
if env -u DISPLAY -u WAYLAND_DISPLAY timeout 10 "$vm" --c4 --jit none "$image" --eval '1' >"$tmp/no-display" 2>&1; then
    echo 'C4 SDL silently ran without a display' >&2
    exit 1
fi
grep -Fq 'C4 SDL display unavailable:' "$tmp/no-display"
if SDL_VIDEO_DRIVER=dummy timeout 10 "$vm" --c4 --jit none "$image" --eval '1' >"$tmp/dummy" 2>&1; then
    echo 'C4 SDL silently ran on the dummy driver' >&2
    exit 1
fi
grep -Fq 'a real X11 or Wayland display is required' "$tmp/dummy"

until_ok() {
    attempt=0
    until "$@"; do
        attempt=$((attempt + 1))
        [ "$attempt" -lt 150 ] || { echo "C4 SDL timed out: $*" >&2; return 1; }
        kill -0 "$pid"
        sleep 0.1
    done
}
xdotool mousemove 1 1
C4_SDL_ACK="$tmp/ack" SAMALTAK_C4_STATS=1 timeout -k 2 55 \
    "$vm" --c4-moving --jit none --max-heap 192 --eden 1 "$image" --eval "$(cat "$dir/interactive.st")" \
    >"$tmp/out" 2>"$tmp/err" &
pid=$!
until_ok grep -Fxq 'C4 SDL ready' "$tmp/out"
win=$(timeout 10 xdotool search --sync --onlyvisible --name '^C4 SDL CI witness$')
until_ok "$tmp/xpixel" "$win" 213 37 61
xdotool mousemove --window "$win" 61 39
until_ok grep -Fxq 'C4 SDL motion and repaint' "$tmp/out"
until_ok "$tmp/xpixel" "$win" 42 193 79
touch "$tmp/ack"
wait "$pid"
pid=
grep -Fxq 'C4 SDL interactive ok' "$tmp/out"
grep -Eq '^c4: .*cycles_completed=[1-9][0-9]* .*failed=0 ' "$tmp/err"
grep -Eq '^c4-moving: .* moved=[1-9][0-9]* ' "$tmp/err"
