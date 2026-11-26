#!/usr/bin/env python3
"""Pair A/B in one macOS job, using the same committed AWFY driver."""
import csv
import os
import re
import signal
import statistics as stats
import subprocess
import sys
from pathlib import Path
from time import sleep

LAPS = 12
WORK = ("Mandelbrot:500", "NBody:250000", "Richards:7")
ORDERS = ("AB", "BA", "AB", "BA")
GAIN, REGRESSION = 2, 5  # percent; negative B/A delta = faster B


def measurements(path, name):
    data = path.read_text()
    rows = re.findall(rf"^{re.escape(name)},([0-9]+),(-?[0-9]+)$", data, re.M)
    times = [int(us) for _, us in rows]
    if [int(lap) for lap, _ in rows] != list(range(1, LAPS + 1)) or min(times) <= 0:
        raise ValueError(f"{path}: missing, unordered, duplicated or nonpositive CPU laps")
    if not re.search(rf"^# stats {name}\b.*\boptMethodsCompiled=[1-9][0-9]*\b", data, re.M):
        raise ValueError(f"{path}: no optimized method compilation recorded")
    return times[0], stats.median(times[LAPS // 2:])


def run_checked(cmd, cwd, log, env):
    with log.open("w") as f:
        p = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=f, stderr=subprocess.STDOUT,
                             start_new_session=True)
        try:
            status = p.wait(timeout=180)
        except subprocess.TimeoutExpired:
            # AWFY is a pipeline; kill the process group, not just its shell.
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
            raise RuntimeError(f"{log.name}: timed out")
    if status:
        raise RuntimeError(f"{log.name}: exit {status}\n{log.read_text()[-4000:]}")


def run(root, logs):
    driver = root / "A/vm/tests/bench/awfy.sh"
    env = {k: v for k, v in os.environ.items() if not k.startswith("SAMALTAK_")}
    for key in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY"):
        env.pop(key, None)
    env.update(SDL_VIDEO_DRIVER="samaltak_no_video", SDL_VIDEODRIVER="samaltak_no_video")
    scores = {}
    with (logs / "pairs.csv").open("w", newline="") as f:
        pairs = csv.writer(f)
        pairs.writerow(["round", "workload", "pair", "order", "metric", "A_us", "B_us", "B_vs_A_pct"])
        for batch in (1, 2):
            # Cool off after the builds and between rounds.
            sleep(10)
            for spec in WORK if batch == 1 else reversed(WORK):
                name = spec.split(":")[0]
                deltas = {"first": [], "steady": []}
                for pair, order in enumerate(ORDERS if batch == 1 else reversed(ORDERS), 1):
                    values = {}
                    for side in order:
                        repo = root / side
                        stem = logs / f"r{batch}-{name}-{pair}-{side}"
                        raw = stem.with_suffix(".csv")
                        print(stem.name, flush=True)
                        run_checked(
                            [str(driver), "--vm", str(repo / "vm/build/samaltak"),
                             "--image", str(repo / "build/samaltak.image"),
                             "--vm-args", "--jit opt", "--cpu", "-n", str(LAPS),
                             "-o", str(raw), spec],
                            cwd=repo, log=stem.with_suffix(".log"), env=env,
                        )
                        values[side] = measurements(raw, name)
                    for i, metric in enumerate(deltas):
                        a, b = values["A"][i], values["B"][i]
                        delta = 100 * (b / a - 1)
                        pairs.writerow([batch, spec, pair, order, metric, a, b, f"{delta:+.4f}"])
                        deltas[metric].append(delta)
                    f.flush()
                for metric, ds in deltas.items():
                    scores.setdefault((spec, metric), []).append(stats.median(ds))

    with (logs / "summary.csv").open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["workload", "metric", "round1_pct", "round2_pct"])
        for (spec, metric), (r1, r2) in scores.items():
            writer.writerow([spec, metric, f"{r1:+.4f}", f"{r2:+.4f}"])
    regressions = [f"{spec} {metric}" for (spec, metric), ds in scores.items()
                   if all(d > REGRESSION for d in ds)]
    gain = all(d <= -GAIN + 1e-9 for d in scores[WORK[0], "steady"])
    if regressions:
        verdict = f"HOLD: repeated >{REGRESSION}% slowdown: {', '.join(regressions)}"
    elif not gain:
        verdict = f"HOLD: >= {GAIN}% steady Mandelbrot gain not confirmed in both rounds"
    else:
        verdict = "PASS: paired timing gate (native correctness is a separate step)"
    summary = (logs / "summary.csv").read_text()
    (logs / "verdict.txt").write_text(verdict + "\n")
    print(summary + verdict)
    if "GITHUB_STEP_SUMMARY" in os.environ:
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            fence = chr(96) * 3
            f.write(f"### {verdict}\n\n{fence}csv\n{summary}{fence}\n")
    return 0 if gain and not regressions else 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: mac-floatx2.py SOURCE_ROOT LOG_DIRECTORY")
    try:
        raise SystemExit(run(*(Path(arg).resolve() for arg in sys.argv[1:])))
    except (OSError, RuntimeError, ValueError) as e:
        raise SystemExit(f"Timing evidence incomplete: {e}")
