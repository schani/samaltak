#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
image=$(realpath "${1:?stage-2 image required}")
dir=tests/vm/c4-platform-sdl
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset DISPLAY WAYLAND_DISPLAY C4_SDL_LEGACY
export SAMALTAK_C4_STATS=1 C4_SDL_DENIED="$tmp/denied"
run() {
    test=$1; shift
    rc=0
    timeout -k 2 45 "$@" "$image" --headless --eval "$(cat "$dir/$test.st")" \
        >"$tmp/out" 2>"$tmp/err" || rc=$?
    cat "$tmp/out" "$tmp/err"
    [ "$rc" -eq 0 ]
}
vm=vm/build/c4-sdl/samaltak
for mode in --c4 --c4-moving; do
    run allowlist "$vm" "$mode" --jit none
    grep -Fxq 'C4 SDL allowlist ok' "$tmp/out"
    run events vm/build/c4-sdl-fixture/samaltak "$mode" --jit none --max-heap 192 --eden 1
    grep -Fxq 'SDL event contract ok' "$tmp/out"
    grep -Fxq 'C4 SDL staged pixels survived a C4 cycle' "$tmp/err"
    grep -Eq '^c4: .*cycles_completed=[1-9][0-9]* .*weak_cleared=[1-9][0-9]* .*failed=0 ' "$tmp/err"
    if [ "$mode" = --c4-moving ]; then
        grep -Eq '^c4-moving: .* moved=[1-9][0-9]* ' "$tmp/err"
    fi
done
export C4_SDL_LEGACY=1
run events vm/build/c4-sdl-legacy/samaltak --jit none --eden 1
grep -Fxq 'SDL event contract ok' "$tmp/out"

# Invalid interactive invocations should fail *before* display init. Use the
# detector binary so even a regression cannot turn this into a display test.
vm=vm/build/c4-sdl-fixture/samaltak
reject() {
    want=$1; shift
    if timeout -k 1 10 "$vm" "$@" >"$tmp/reject" 2>&1 || ! grep -Fq -- "$want" "$tmp/reject"; then
        cat "$tmp/reject" >&2
        exit 1
    fi
}
reject 'requires --c4 or --c4-moving' "$image" --headless
for mode in --c4 --c4-moving; do
    reject 'requires --jit none explicitly' "$mode" "$image" --headless
    reject 'requires image --eval <expression>' "$mode" --jit none "$image"
    reject 'requires image --eval <expression>' "$mode" --jit none "$image" --eval
    reject 'requires image --eval <expression>' "$mode" --jit none "$image" --eval ''
    reject 'requires image --eval <expression>' "$mode" --jit none "$image" --eval --test
    reject 'requires image --eval <expression>' "$mode" --jit none "$image" --test --eval '1'
    reject 'requires image --eval <expression>' "$mode" --jit none "$image" --app --eval '1'
    reject 'requires image --eval <expression>' "$mode" --jit none "$image" --eval '1' --stage2 out.image
done
reject 'requires --jit none' --c4 --jit baseline "$image" --headless
reject 'requires --jit none' --c4-moving --jit opt "$image" --headless
reject '--c4-moving-forward requires Linux x86-64 with NO_PLATFORM=1' --c4-moving-forward --jit none "$image" --headless
echo 'c4-platform-sdl: headless contracts passed'
