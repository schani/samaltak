# Native ARM64 selective-worker gate

Validation branch only. Nothing runs on main, a PR, a branch update, or a rerun.
One approval authorizes one new `validate/linux-arm-bg-selective-<full candidate SHA>`
branch in `schani/samaltak`. Cherry-pick this single harness commit onto that exact
candidate (not onto main). Before publishing, verify the candidate integrates the
deterministic lifecycle fixture in `tests/vm/jit_worker_test.sh`, leaves AWFY
unchanged, and has no other workflow triggered by the validation branch.
The harness commit must have exactly the SHA in the branch name as its sole parent.
Run neither a second CI attempt nor a separate machine without approval.

`bg-jit-ab.py` is byte-identical to Git blob `d46764aeb22adca3f666a6ccbfdb256406267794`
from commit `8ab6d7d56f5a9410adf4a9d5881d494fe203bcc7` (run `45835219359`).
It supplies distinct guest-core admission, the ESRCH-tolerant thread mask check,
the fresh VM invocation, AWFY validation and wait4 process accounting. Guest-visible
core separation does not prove host core separation or reservation.

- A is `bfba965cab254aaf6d208139e54b3488d9cc0863`; B and C are the same exact
  candidate binary, default-off and ordinary `--jit-flags bg`, respectively.
  All timing uses A's shared full image and AWFY. Four lifecycle fixture runs
  instead use B's own freshly built image and committed fixtures.
- Each workload (DeltaBlue, CD, Json, NBody) gets 2 A/A, 4 A/B and 4 B/C
  balanced pairs in seeded interleaved rounds. Each leg is a fresh process
  with 30 checked laps. No test or trace controls in timing.
- Report startup wall (launch through first checked output, includes file-in and
  lap one), whole-process CPU (all threads), and steady lap wall separately.
  Retain all pair ratios, per-leg results, host/noise snapshots, and install counts.
- Hard failures: wrong/incomplete workload or lifecycle, nonzero B workload
  background counts, no normal installs anywhere in C, or a repeatable >5%
  regression across all four pairs with A/A inside the 5% ratio band and no
  host noise for that workload/comparison. Noisy metrics still complete and are
  reported as inconclusive, not passes for promotion.
- One hosted runner/job, 35-minute cap, no matrix or automatic reruns. Build with
  up to four workers; benchmark on two guest cores. At most 80 timed VM launches
  with a six-minute launch window and 90-second per-VM safety timeout, plus four
  lifecycle invocations (30 seconds each + 5 seconds kill grace). Evidence
  retained for seven days. No automatic promotion.
