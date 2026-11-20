#!/bin/sh
# CI probe, not for merging. usage: run.sh ROUNDS MINUTES STRICT
# Each round: AgentWindowTest and AgentAskProbeTest in one VM under the deoptimization stress flags.
# Stops after ROUNDS rounds or MINUTES minutes. STRICT=yes: exit 1 if any round failed.
set -u
rounds=$1
deadline=$(($(date +%s) + $2 * 60))
strict=$3
make image >/tmp/probe-make.log 2>&1 || { tail -30 /tmp/probe-make.log; exit 2; }
i=0
bad=0
while [ $i -lt "$rounds" ] && [ "$(date +%s)" -lt $deadline ]; do
  i=$((i + 1))
  start=$(date +%s)
  tests/st_suite.sh build/samaltak.image --jit opt --jit-threshold 0 --jit-flags eager,deopt -- AgentWindowTest AgentAskProbeTest >/tmp/probe-round.log 2>&1
  code=$?
  [ $code -eq 0 ] || bad=$((bad + 1))
  grep -E '^(FAIL|ERROR)|[0-9]+ run, |st_suite' /tmp/probe-round.log | sort | uniq -c
  echo "round $i: exit $code, $(($(date +%s) - start)) s"
done
echo "PROBE: $i rounds, $bad with failures"
[ "$strict" = yes ] && [ $bad -gt 0 ] && exit 1
exit 0
