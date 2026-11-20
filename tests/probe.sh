#!/bin/sh
# CI probe, not for merging. usage: tests/probe.sh MODE
#   only         DebuggerUITest>>testWatchpointStopsTheWindowManagerWithAStandIn alone, again and again for BUDGET
#                seconds, each in a fresh VM, deopt stress flags
#   only-load    the same with busy loops on every core
#   race-divert  the same, a window's Process stalling in Watchpoint class>>diversionFor: (SAMALTAK_PROBE)
#   race-store   the same, a window's Process stalling in Watchpoint class>>performStore:
#   class        DebuggerUITest whole, again and again
#   files        FileBrowserTest and the retained drawing tests, again and again
#   leak         the whole suite once; DebuggerUITest's tearDown is cut short in one test (SAMALTAK_PROBE=leak)
set -u
cd "$(dirname "$0")/.."
MODE=$1
BUDGET=${BUDGET:-1500}
FLAGS="--jit opt --jit-threshold 0 --jit-flags eager,deopt"
IMAGE=build/samaltak.image

if [ "$MODE" = leak ] || [ "$MODE" = leak-raw ]; then
  # shellcheck disable=SC2086
  tests/st_suite.sh $IMAGE $FLAGS
  echo "probe leak: suite exit $? (the forced error is the point of this probe)"
  exit 0
fi

CLASSES=DebuggerUITest
case "$MODE" in
  only|only-load|race-divert|race-store) export SAMALTAK_PROBE_ONLY=testWatchpointStopsTheWindowManagerWithAStandIn ;;
  class) ;;
  files) CLASSES="FileBrowserTest RetainedDrawingTest DisplaySegmentTest WindowRoutingTest" ;;
  *) echo "unknown mode $MODE"; exit 2 ;;
esac
case "$MODE" in race-*) BUDGET=600 ;; esac

if [ "$MODE" = only-load ]; then
  for _ in $(seq "$(nproc)"); do ( while :; do :; done ) & done
  trap 'kill $(jobs -p) 2>/dev/null' EXIT
fi

runs=0
failed=0
start=$(date +%s)
LOG=$(mktemp)
while [ $(( $(date +%s) - start )) -lt "$BUDGET" ]; do
  runs=$((runs + 1))
  t0=$(date +%s)
  # shellcheck disable=SC2086
  if tests/st_suite.sh $IMAGE $FLAGS -- $CLASSES >"$LOG" 2>&1; then
    echo "probe run $runs: ok, $(( $(date +%s) - t0 )) s: $(grep -E '^[0-9]+ run, ' "$LOG" | tail -1)"
    grep -E '^PROBE|Compositor error|InputDispatcher' "$LOG" || true
  else
    failed=$((failed + 1))
    echo "probe run $runs: FAILED, $(( $(date +%s) - t0 )) s"
    cat "$LOG"
  fi
done
echo "probe $MODE: $runs runs, $failed failed"
[ "$failed" -eq 0 ]
