#!/usr/bin/env python3
"""Native Linux ARM64 paired thread-CPU measurements; no builds or writes to A/B."""
import csv
import os
import re
import signal
import statistics as stats
import subprocess
import sys
from fractions import Fraction
from pathlib import Path
from time import sleep

LAPS = 12
TARGET = "EPtrArrayScan"
CHECKSUM = "200010000"
WORK = (TARGET, "Mandelbrot:500", "NBody:250000", "Richards:7")
ORDERS = ("AB", "BA", "AB", "BA")
REGRESSION, EXPECTED_GAIN = 5, 2  # percent; negative B/A = faster


def require(ok, message):
    if not ok:
        raise ValueError(message)


def measurements(path, spec, side):
    name, _, inner = spec.partition(":")
    text = path.read_text()
    lines = text.splitlines()
    rows = [x.split(",") for x in lines if x.startswith(name + ",")]
    is_target = name == TARGET
    width = 4 if is_target else 3
    require(len(rows) == LAPS and all(
        len(row) == width and row[1] == str(lap) and re.fullmatch(r"[1-9][0-9]*", row[2])
        for lap, row in enumerate(rows, 1)), f"{path}: malformed or missing CPU laps")
    require(not is_target or all(row[3] == CHECKSUM for row in rows),
            f"{path}: expected checksum {CHECKSUM} on every lap")
    counters = [x for x in lines if x.startswith(f"# stats {name} ")]
    require(len(counters) == 1 and re.search(r"\boptMethodsCompiled=[1-9][0-9]*\b", counters[0]),
            f"{path}: no optimized method compilation recorded")
    if not is_target:
        require(lines.count(f"# run {name} inner={inner}") == 1,
                f"{path}: AWFY workload size differs from {spec}")
    else:
        start = lines.index(f"# listing {TARGET}")
        end = lines.index(f"# end listing {TARGET}")
        listing = lines[start + 1:end]
        require(any(x.startswith(f"{TARGET}>>checksumTagged:to:  opt") for x in listing),
                f"{path}: no optimized checksumTagged:to: listing")
        bounds = "within bounds: checked once before the loop"
        tag = "address from tagged pointer index"
        require(any(bounds in x for x in listing), f"{path}: target is not bounds-hoisted")
        # Require the opcodes on successive instructions, with the LDUR using the ADD result.
        if side == "B":
            require(any(bounds in x and tag in x
                        and re.search(r"\badd x17, x[0-9]+, x[0-9]+, lsl #2\s+;", x)
                        and re.search(r"\bldur x[0-9]+, \[x17, #(?:0x)?4\]", y)
                        for x, y in zip(listing, listing[1:])), f"{path}: missing tagged load")
        else:
            require(not any(tag in x for x in listing) and any(
                bounds in x and any(re.search(r"\basr x17, x[0-9]+, #1\b", y)
                                    for y in listing[i:i + 4])
                for i, x in enumerate(listing)), f"{path}: A not on the old bounds-hoisted load path")
    times = [int(row[2]) for row in rows]
    return Fraction(times[0]), stats.median([Fraction(us) for us in times[LAPS // 2:]])


def run_checked(cmd, cwd, log, env):
    with log.open("w") as f:
        proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=f, stderr=subprocess.STDOUT,
                                start_new_session=True)
        try:
            status = proc.wait(timeout=180)
        except subprocess.TimeoutExpired:
            # Kill the process group (the AWFY driver runs a pipeline).
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait()
            raise RuntimeError(f"{log.name}: timed out")
    if status:
        raise RuntimeError(f"{log.name}: exit {status}\n{log.read_text()[-4000:]}")


def run(root, logs):
    driver = root / "A/vm/tests/bench/awfy.sh"
    fixture = Path(__file__).with_name("arm64-eptr-target.st")
    env = {k: v for k, v in os.environ.items() if not k.startswith("SAMALTAK_")}
    for key in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY"):
        env.pop(key, None)
    env.update(SDL_VIDEO_DRIVER="samaltak_no_video", SDL_VIDEODRIVER="samaltak_no_video")
    scores = {}
    with (logs / "pairs.csv").open("w", newline="") as f:
        pairs = csv.writer(f)
        pairs.writerow(["round", "workload", "pair", "order", "metric", "A_us", "B_us", "B_vs_A_pct"])
        for batch in (1, 2):
            sleep(10)
            for spec in WORK if batch == 1 else reversed(WORK):
                name = spec.split(":")[0]
                deltas = {"first": [], "steady": []}
                for pair, order in enumerate(ORDERS if batch == 1 else reversed(ORDERS), 1):
                    values = {}
                    for side in order:
                        repo = root / side
                        stem = logs / f"r{batch}-{name}-{pair}-{side}"
                        log = stem.with_suffix(".log")
                        vm, image = str(repo / "vm/build/samaltak"), str(repo / "build/samaltak.image")
                        print(stem.name, flush=True)
                        if name == TARGET:
                            expr = ("Smalltalk vm jitArchitecture = #arm64 ifFalse: [Smalltalk quit: 1]. "
                                    f"EPtrArrayScan new run: {LAPS}. Smalltalk quit: 0")
                            cmd = [vm, "--jit", "opt", image, "--headless", "--load", str(fixture),
                                   "--eval", expr]
                            raw = log
                        else:
                            raw = stem.with_suffix(".csv")
                            cmd = [str(driver), "--vm", vm, "--image", image, "--vm-args", "--jit opt",
                                   "--cpu", "-n", str(LAPS), "-o", str(raw), spec]
                        run_checked(cmd, repo, log, env)
                        values[side] = measurements(raw, spec, side)
                    for i, metric in enumerate(deltas):
                        a, b = values["A"][i], values["B"][i]
                        delta = 100 * (b / a - 1)
                        pairs.writerow([batch, spec, pair, order, metric, float(a), float(b),
                                        f"{float(delta):+.4f}"])
                        deltas[metric].append(delta)
                    f.flush()
                for metric, ds in deltas.items():
                    scores.setdefault((spec, metric), []).append(stats.median(ds))

    with (logs / "summary.csv").open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["workload", "metric", "round1_pct", "round2_pct"])
        for (spec, metric), (r1, r2) in scores.items():
            writer.writerow([spec, metric, f"{float(r1):+.4f}", f"{float(r2):+.4f}"])
    regressions = []
    unresolved = []
    for (spec, metric), ds in scores.items():
        slow = sum(d > REGRESSION for d in ds)
        if slow == 2:
            regressions.append(f"{spec} {metric}")
        elif slow == 1:
            unresolved.append(f"{spec} {metric}")
    gain = all(d <= -EXPECTED_GAIN for d in scores[TARGET, "steady"])
    if regressions:
        verdict = f"FAIL: repeated >{REGRESSION}% slowdown: {', '.join(regressions)}"
    elif unresolved:
        verdict = f"HOLD: >{REGRESSION}% slowdown in one round; rerun: {', '.join(unresolved)}"
    elif not gain:
        verdict = f"HOLD: steady target gain of at least {EXPECTED_GAIN}% not confirmed in both rounds"
    else:
        verdict = "PASS: paired timing gate (focused correctness and integrity are separate steps)"
    summary = (logs / "summary.csv").read_text()
    (logs / "verdict.txt").write_text(verdict + "\n")
    print(summary + verdict)
    if "GITHUB_STEP_SUMMARY" in os.environ:
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            fence = chr(96) * 3
            f.write(f"### {verdict}\n\n{fence}csv\n{summary}{fence}\n")
    return 0 if gain and not regressions and not unresolved else 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: arm64-eptr-ab.py SOURCE_ROOT LOG_DIRECTORY")
    try:
        raise SystemExit(run(*(Path(arg).resolve() for arg in sys.argv[1:])))
    except (OSError, RuntimeError, ValueError) as exc:
        raise SystemExit(f"Timing evidence incomplete: {exc}")
