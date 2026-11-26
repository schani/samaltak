#!/usr/bin/env python3
"""Bounded selective-worker gate using the run 45835219359 benchmark helper."""
import importlib.util
import os
from pathlib import Path
import random
import sys
import time

spec = importlib.util.spec_from_file_location("pilot", Path(__file__).with_name("bg-jit-ab.py"))
pilot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pilot)

ARMS = {"AA": "AA", "AB": "AB", "BC": "BC"}
PAIRS = {"AA": 2, "AB": 4, "BC": 4}
BAND = .05
LAUNCH_BUDGET_S = 6 * 60  # Keep the last possible 90s VM inside the CI step cap.
METRICS = ("launch_to_first_s", "vm_cpu_s", "steady_us", "first_us")
ERRORS = (RuntimeError, OSError, ValueError, KeyError, TypeError)


def schedule(cells):
    rng = random.Random(pilot.SEED)
    groups = {}
    for cell in cells:
        for comparison, n in PAIRS.items():
            order = [False, True] * (n // 2)
            rng.shuffle(order)
            groups[cell, comparison] = (order, rng.randrange(2**32))
    result = []
    for r in range(max(PAIRS.values())):
        order = list(cells)
        rng.shuffle(order)
        for cell in order:
            comparisons = [c for c in PAIRS if r < PAIRS[c]]
            rng.shuffle(comparisons)
            for comparison in comparisons:
                reverse, seed = groups[cell, comparison]
                result.append(dict(cell=cell, comparison=comparison, pair=r + 1,
                                   arms=list(ARMS[comparison]), reverse=reverse[r],
                                   bootstrap_seed=seed))
    return result


def run_pair(logs, item, cpus, deadline):
    cell, comparison, pair = (item[k] for k in ("cell", "comparison", "pair"))
    folder = logs / comparison / cell / f"{pair:02d}"
    folder.mkdir(parents=True)
    legs, errors = [None, None], []
    before = pilot.host(cpus)
    for j in ((1, 0) if item["reverse"] else (0, 1)):
        arm = item["arms"][j]
        if time.monotonic() >= deadline:
            errors.append(f"{arm}: launch budget exhausted")
            continue
        try:
            legs[j] = pilot.leg(folder / f"{j}-{arm}", cell, arm, cpus)
        except ERRORS as exc:
            errors.append(f"{arm}: {exc}")
        time.sleep(pilot.PAUSE)
    after = pilot.host(cpus)
    reasons = pilot.noise(before, after) if any(leg is not None for leg in legs) else []
    pilot.dump(folder / "host.json", {"before": before, "after": after, "noise": reasons})
    result = dict(legs=legs, errors=errors, noise=reasons)
    pilot.dump(folder / "pair.json", result)
    print(f"{cell} {comparison} {pair}: errors={errors} noise={reasons}", flush=True)
    return result


def summarize(group):
    pairs = [r["legs"] for _, r in group if all(leg is not None for leg in r["legs"])]
    return dict(n=len(pairs), expected=len(group),
                metrics=pilot.summary(pairs, group[0][0]) if pairs else {},
                noise=sorted({reason for _, r in group for reason in r["noise"]}),
                errors=[error for _, r in group for error in r["errors"]],
                installs=[leg["jobs"]["installed"] if leg else None
                          for s, r in group for arm, leg in zip(s["arms"], r["legs"]) if arm == "C"])


def classify(row, aa, key):
    if row["n"] != row["expected"] or aa["n"] != aa["expected"]:
        return "incomplete"
    if row["noise"] or aa["noise"]:
        return "host noise"
    control = aa["metrics"][key]["paired_ratios"]
    if any(not 1 / (1 + BAND) <= x <= 1 + BAND for x in control):
        return "A/A noise"
    tested = row["metrics"][key]["paired_ratios"]
    if all(x > 1 + BAND for x in tested):
        return "repeatable >5% regression"
    if all(x < 1 / (1 + BAND) for x in tested):
        return "repeatable >5% gain"
    return "no repeatable >5% change"


def write_summary(report, installs):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    with (Path(path).open("a") if path else os.fdopen(os.dup(sys.stdout.fileno()), "w")) as out:
        print("### Selective background JIT — native ARM64\n", file=out)
        print("A = main baseline, B = candidate default-off, C = same candidate with ordinary "
              "`--jit-flags bg`. All timed legs use the same baseline image. "
              "Positive percentages are slower or cost more CPU.\n", file=out)
        print("Startup wall is launch → first checked CSV result (includes image load, file-ins and lap 1). "
              "Process CPU is user + system over the whole VM lifetime, including the worker. "
              "Steady wall is median laps 16–30; lap 1 wall is also shown.\n", file=out)
        print("| Workload | Pairing | Pairs | Startup wall | Process CPU | Steady wall | Lap 1 wall | "
              "C workload installs | Notes |", file=out)
        print("|---|---|---:|---:|---:|---:|---:|---|---|", file=out)
        for cell, rows in report.items():
            for comparison, r in rows.items():
                pct = [f"{(r['metrics'][k]['median_ratio']-1)*100:+.1f}%" if k in r["metrics"]
                       else "—" for k in METRICS]
                note = ", ".join(f"{k}: {v}" for k, v in r.get("signals", {}).items()
                                 if v != "no repeatable >5% change")
                if r["noise"]:
                    note += "; host noise flagged"
                if r["errors"]:
                    note += f"; {len(r['errors'])} leg error(s)"
                jobs = ", ".join("—" if n is None else str(n) for n in r["installs"]) or "—"
                print(f"| {cell} | {comparison[0]}/{comparison[1]} | {r['n']}/{r['expected']} | "
                      f"{' | '.join(pct)} | {jobs} | {note.strip('; ')} |", file=out)
        print(f"\nNormal C legs recorded **{installs}** installs within checked workloads. "
              "A/A has two pairs per cell, A/B and B/C four each. "
              "No retries. Noise limits interpretation, not collection or install accounting. "
              "Small samples are directional; this is not an automatic promotion decision.", file=out)


def compare(logs):
    pilot.require(os.uname().machine == "aarch64", "native ARM64 is required")
    cpus = pilot.cpuset((logs / "cpus.txt").read_text().strip())
    pilot.require(len(cpus) == 2 and cpus <= os.sched_getaffinity(0), "chosen CPUs no longer permitted")
    cells = tuple(pilot.CELLS) + ("NBody",)
    pilot.CELLS["NBody"] = 250000
    plan = schedule(cells)
    pilot.dump(logs / "schedule.json", plan)
    deadline = time.monotonic() + LAUNCH_BUDGET_S
    groups = {(cell, comparison): [] for cell in cells for comparison in ARMS}
    for item in plan:
        result = run_pair(logs, item, cpus, deadline)
        groups[item["cell"], item["comparison"]].append((item, result))

    report = {cell: {c: summarize(groups[cell, c]) for c in ARMS} for cell in cells}
    failures, installs = [], 0
    for cell, rows in report.items():
        for comparison, r in rows.items():
            installs += sum(n for n in r["installs"] if n is not None)
            if r["n"] != r["expected"] or r["errors"]:
                failures.append(f"{cell} {comparison}: incomplete or failed workload")
            if comparison == "AA":
                continue
            r["signals"] = {key: classify(r, rows["AA"], key) for key in METRICS}
            failures.extend(f"{cell} {comparison} {key}: {signal}" for key, signal in r["signals"].items()
                            if signal == "repeatable >5% regression")
    if not installs:
        failures.append("no normal background installs in any timed C workload")
    pilot.dump(logs / "paired-summary.json", report)
    pilot.dump(logs / "timing-gate.json", {"normal_installs": installs, "failures": failures})
    write_summary(report, installs)
    pilot.require(not failures, "; ".join(failures))


if __name__ == "__main__":
    (location,) = sys.argv[1:]
    compare(Path(location))
