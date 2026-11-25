#!/bin/sh
# A VM with a display that gets SIGTERM quits (SDL makes the signal a quit event, the World quits) with 128 + 15 and
# says so on stderr, with the sender: before, it exited with 0, so a test run that someone's pkill cut short looked
# like one that ended normally, only without its summary (st_suite: no test summary (exit 0)).
# usage: tests/tools/quit_signal_test.sh [image]   (default: build/samaltak.image)
set -u
cd "$(dirname "$0")/../.."
IMAGE=${1:-build/samaltak.image}
CTL=tools/samaltak-ctl
export SAMALTAK_SESSION=quit-signal-test-$$
SESSIONS=${TMPDIR:-/tmp}/samaltak-ctl
TMP=$(mktemp -d)
pid=
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
check() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: expected [$2], got [$3]"; fi
}
contains() { # name haystack needle
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1: [$3] not in [$2]" ;; esac
}
cleanup() {
  [ -n "$pid" ] && kill -KILL "$pid" 2>/dev/null
  rm -rf "$TMP" "$SESSIONS/$SAMALTAK_SESSION.json"
}
trap cleanup EXIT

# The VM is this shell's child, so that wait sees its exit status; samaltak-ctl reaches it through a session file.
vm/build/samaltak "$IMAGE" --hidden --control --control-port 0 --control-port-file "$TMP/port" >"$TMP/log" 2>&1 &
pid=$!
i=0; until [ -s "$TMP/port" ] || [ $i -ge 600 ]; do i=$((i + 1)); sleep 0.1; done
[ -s "$TMP/port" ] || { cat "$TMP/log"; echo "FAIL the VM did not start"; exit 1; }
mkdir -p "$SESSIONS"
printf '{"pid": %s, "port": %s}\n' "$pid" "$(cat "$TMP/port")" >"$SESSIONS/$SAMALTAK_SESSION.json"
# the ref condition fails at once until the World registers its snapshot root
i=0; until $CTL wait '@w6' 10000 >/dev/null 2>&1 || [ $i -ge 100 ]; do i=$((i + 1)); sleep 0.1; done
check "the World is up" "6" "$($CTL snapshot --depth 1 | grep -c '^window')"

kill -TERM "$pid"
wait "$pid"
check "SIGTERM: exit status 143" "143" "$?"
pid=
contains "SIGTERM: says so, with the sender" "$(cat "$TMP/log")" "samaltak: quit on SIGTERM from pid $$ ("

[ $fails -eq 0 ] && echo "quit signal test: all passed" || { cat "$TMP/log"; echo "quit signal test: $fails failed"; }
[ $fails -eq 0 ]
