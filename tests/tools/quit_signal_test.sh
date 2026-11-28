#!/bin/sh
# A signal quits the World with 128 + the signal number, and reports the sender on stderr.
# usage: tests/tools/quit_signal_test.sh [image]   (default: build/samaltak.image)
set -eu
cd "$(dirname "$0")/../.."
IMAGE=${1:-build/samaltak.image}
CTL=tools/samaltak-ctl
umask 077
TMP=$(mktemp -d)
export TMPDIR="$TMP" SAMALTAK_SESSION=quit-signal-test
pid=
cleanup() {
  [ -z "$pid" ] || kill -KILL "$pid" 2>/dev/null || :
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

fail() { echo "FAIL SIG$signal: $1"; cat "$TMP/log"; exit 1; }
run_case() {
  signal=$1 expected=$2
  shift 2
  rm -f "$TMP/port"
  python3 -c 'import secrets; print(secrets.token_hex(16))' >"$TMP/token"
  # Reset the SIGINT ignored by background shell jobs, then exec so wait sees the VM's status.
  python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execv(sys.argv[1], sys.argv[1:])' \
    vm/build/samaltak "$IMAGE" --control --control-port 0 --control-port-file "$TMP/port" \
    --control-token-file "$TMP/token" "$@" >"$TMP/log" 2>&1 &
  pid=$!
  timeout 60 sh -c 'until [ -s "$1" ]; do kill -0 "$2" 2>/dev/null || exit 1; sleep 0.1; done' sh "$TMP/port" "$pid" ||
    fail "the VM did not start"
  "$CTL" connect --port "$(cat "$TMP/port")" --token-file "$TMP/token" >/dev/null ||
    fail "could not connect"
  # The World hosts the control server once its input dispatcher is ready. The wait command
  # advances the work clock if needed, then pauses it again before replying.
  timeout 30 "$CTL" wait '{"eval":"ControlServer current host notNil"}' 20000 >/dev/null ||
    fail "the World did not start"

  kill -s "$signal" "$pid" || fail "could not send the signal"
  timeout 20 sh -c 'while kill -0 "$1" 2>/dev/null; do sleep 0.1; done' sh "$pid" ||
    fail "the VM did not quit"
  status=0
  wait "$pid" || status=$?
  pid=
  [ "$status" = "$expected" ] || fail "expected exit status $expected, got $status"
  grep -Fq "samaltak: quit on SIG$signal from pid $$ (" "$TMP/log" || fail "missing quit diagnostic with sender PID"
  echo "ok   SIG$signal: exit status $expected and sender PID"
}

run_case TERM 143 --hidden
# A visible World must finish its quit fade even with the clock paused.
run_case INT 130 --work-clock --window-size 640x400
echo "quit signal test: all passed"
