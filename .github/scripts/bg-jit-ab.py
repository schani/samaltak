#!/usr/bin/env python3
"""Hosted native ARM64 gate adapted from the background-JIT paired wall plan."""
import ctypes as C
import itertools
import json
import math
import mmap
import os
from pathlib import Path
import random
import re
import selectors
import signal
import statistics as stats
import subprocess as sp
import sys
import tempfile
import time

ROOT = Path("/tmp/bg-jit-ab")
AWFY = ROOT / "A/vm/tests/bench/awfy"
IMAGE = ROOT / "A/build/samaltak.image"
CELLS = {"DeltaBlue": 8000, "CD": 100, "Json": 7, "NBody": 250000}
LAPS, SEED, PAUSE = 30, 96520134, 2
BG_NAMES = {"queued": "optBackgroundQueued", "installed": "optBackgroundInstalled",
            "discarded": "optBackgroundDiscarded"}
BG_SLOTS = {"queued": 44, "installed": 45, "discarded": 46}
MEASURES = ("first_us", "steady_us", "total_us", "launch_to_first_s",
            "vm_wall_s", "vm_cpu_s", "vm_user_s", "vm_sys_s", "peak_rss_kib")
ENDPOINTS = ("first_us", "steady_us")
LIMIT = 1.05


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def dump(path, obj):
    path.write_text(json.dumps(obj, indent=2, sort_keys=True, allow_nan=False) + "\n")


def read(path):
    try:
        return Path(path).read_text().strip()
    except FileNotFoundError:
        return None


def cpuset(s):
    out = set()
    for item in s.split(","):
        a, _, b = item.partition("-")
        out.update(range(int(a), int(b or a) + 1))
    return out


def cgroups():
    # Record the visible hierarchy. A hosted guest/container can hide outer limits.
    cg = Path("/sys/fs/cgroup")
    out = {}
    for line in Path("/proc/self/cgroup").read_text().splitlines():
        _, controllers, location = line.split(":", 2)
        if controllers and "cpu" not in controllers.split(","):
            continue
        base = cg if not controllers else cg / "cpu"
        if controllers and not base.is_dir():
            base = cg / controllers
        p = base / location.lstrip("/")
        if not p.is_dir():
            p = base  # e.g. delegated mount rooted at the container's own cgroup
        for q in [p, *p.parents]:
            if q != base and base not in q.parents:
                continue
            out[str(q)] = {n: read(q / n) for n in (
                "cpu.max", "cpu.cfs_quota_us", "cpu.cfs_period_us",
                "cpu.stat", "cpuset.cpus.effective", "cpu.pressure")}
    return out


def topology(logs):
    allowed = sorted(os.sched_getaffinity(0) &
                     cpuset(read("/sys/devices/system/cpu/online")))
    entries = {}
    for cpu in allowed:
        p = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology")
        entries[cpu] = {k: read(p / k) for k in (
            "physical_package_id", "core_id", "thread_siblings_list")}
    pairs = []
    for a, b in itertools.combinations(allowed, 2):
        x, y = entries[a], entries[b]
        sx, sy = (cpuset(t["thread_siblings_list"]) if t["thread_siblings_list"] else set()
                  for t in (x, y))
        # Some ARM guests expose core_id=-1 but do expose valid sibling sets.
        if a in sx and b in sy and not (sx & sy):
            pairs.append((x["physical_package_id"] != y["physical_package_id"], a, b))
    chosen = sorted(min(pairs)[1:]) if pairs else []
    groups = cgroups()
    dump(logs / "topology.json", {
        "machine": os.uname().machine, "allowed_online": allowed, "guest_topology": entries,
        "selected": chosen, "cgroups": groups,
        "confidence": "Guest-visible distinct cores only; physical host mapping and reservation unverified.",
    })
    require(len(chosen) == 2, "need two permitted online CPUs with disjoint guest sibling sets")
    for path, limits in groups.items():
        if limits["cpu.max"]:
            quota, period = limits["cpu.max"].split()
            require(quota == "max" or int(quota) >= 2 * int(period), f"<2 CPU quota at {path}")
        if limits["cpu.cfs_quota_us"] and limits["cpu.cfs_period_us"]:
            quota = int(limits["cpu.cfs_quota_us"])
            require(quota < 0 or quota >= 2 * int(limits["cpu.cfs_period_us"]), f"<2 CPU quota at {path}")
        if limits["cpuset.cpus.effective"]:
            require(set(chosen) <= cpuset(limits["cpuset.cpus.effective"]), f"cpuset excludes pair at {path}")
    (logs / "cpus.txt").write_text(",".join(map(str, chosen)) + "\n")
    print(f"Selected guest cores {chosen}; physical host topology unverified", flush=True)


def host(cpus):
    ticks = {}
    for line in Path("/proc/stat").read_text().splitlines():
        fields = line.split()
        if fields and fields[0] in {f"cpu{c}" for c in cpus}:
            v = list(map(int, fields[1:9]))
            ticks[fields[0]] = [sum(v), v[7]]
    return {"ticks": ticks, "cgroups": cgroups(), "load": os.getloadavg(),
            "psi": read("/proc/pressure/cpu")}


def noise(before, after):
    reasons = []
    for key, b in before["cgroups"].items():
        a = after["cgroups"].get(key)
        if not a or any(b[k] != a[k] for k in b if k not in ("cpu.stat", "cpu.pressure")):
            reasons.append("CPU limits changed")
            continue
        prior, now = [dict(l.split() for l in (d["cpu.stat"] or "").splitlines()) for d in (b, a)]
        if int(now.get("nr_throttled", 0)) > int(prior.get("nr_throttled", 0)):
            reasons.append(f"CPU quota throttling at {key}")
    for cpu, (total, steal) in before["ticks"].items():
        a, b = after["ticks"][cpu]
        if a <= total or (b - steal) / (a - total) > .01:
            reasons.append(f"guest steal >1% or no ticks on {cpu}")
    return reasons


def warm(paths):
    libc = C.CDLL(None, use_errno=True)
    libc.mincore.argtypes = [C.c_void_p, C.c_size_t, C.POINTER(C.c_ubyte)]
    residency = {}
    for p in paths:
        with p.open("rb") as f:
            while f.read(1 << 20):
                pass
            with mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_COPY) as mm:
                n = (len(mm) + mmap.PAGESIZE - 1) // mmap.PAGESIZE
                vec = (C.c_ubyte * n)()
                addr = C.addressof(C.c_char.from_buffer(mm))
                require(libc.mincore(addr, len(mm), vec) == 0, f"mincore failed: {p}")
                fraction = sum(v & 1 for v in vec) / n
                require(fraction >= .95, f"insufficient warm residency ({fraction:.1%}): {p}")
                residency[str(p)] = fraction
    return residency


def keyed(pattern, source):
    matches = re.findall(pattern, source, re.M)
    require(len(matches) == 1, f"expected one {pattern!r}, got {len(matches)}")
    return matches[0]


def parse(csv, raw, name):
    require("ERROR" not in raw and "# FAILED" not in csv, "AWFY correctness/error marker")
    rows = re.findall(r"^([A-Za-z0-9]+),([0-9]+),(-?[0-9]+)$", csv, re.M)
    require([(b, int(i)) for b, i, _ in rows] == [(name, i) for i in range(1, LAPS + 1)],
            "wrong, duplicate or incomplete AWFY lap sequence")
    laps = [int(us) for _, _, us in rows]
    require(len(laps) == LAPS and all(t > 0 for t in laps), "nonpositive timing")
    total = keyed(r"^# total " + name + r" ([0-9]+) us$", csv)
    require(sum(laps) == int(total), "AWFY total does not match laps")
    fields = keyed(r"^# stats " + name + r" (.+)$", csv).split()
    pairs = [kv.split("=") for kv in fields]
    counters = {k: int(v) for k, v in pairs}
    require(len(pairs) == len(counters) and {"scavenges", "fullGCs", "bytesAllocated",
            "bytesTenured", "optMethodsCompiled"} <= counters.keys(), "missing/duplicate stats")
    return {"first_us": laps[0], "steady_us": stats.median(laps[15:]),
            "total_us": sum(laps), "stats": counters}


def counters(slots, values):
    require(len(values) >= max(slots.values()), "binary does not expose handoff vmStats slots")
    return {k: values[i - 1] for k, i in slots.items()}


def workload_counters(labelled, slots):
    out = {}
    for key, index in slots.items():
        labels = [n for n in (BG_NAMES[key], f"counter{index}") if n in labelled]
        require(len(labels) == 1, f"missing or ambiguous workload counter {key}")
        out[key] = labelled[labels[0]]
    require(all(v >= 0 for v in out.values()), "negative background job delta")
    require(out["installed"] <= out["queued"] + 1 and out["discarded"] <= out["queued"] + 1,
            "invalid workload job deltas (at most one prior job can carry in)")
    return out


def quantile(values, p):
    s = sorted(values)
    i = p * (len(s) - 1)
    lo, hi = math.floor(i), math.ceil(i)
    return s[lo] + (i - lo) * (s[hi] - s[lo])


def summary(pairs, spec):
    report = {}
    for key in MEASURES:
        left = [a[key] for a, _ in pairs]
        right = [b[key] for _, b in pairs]
        row = {}
        for side, x in (("reference", left), ("tested", right)):
            m = stats.median(x)
            row[side] = {"median": m, "p90": quantile(x, .90),
                         "mad": stats.median(abs(v - m) for v in x)}
        if all(left):
            ratios = [b / a for a, b in zip(left, right)]
            rng = random.Random(spec["bootstrap_seed"])
            boot = [stats.median(rng.choices(ratios, k=len(ratios))) for _ in range(10000)]
            row.update({"paired_ratios": ratios, "median_ratio": stats.median(ratios),
                        "paired_bootstrap_95": [quantile(boot, .025), quantile(boot, .975)]})
        if spec["comparison"] == "AA" and key in ENDPOINTS:
            delta = [abs(a - b) / ((a + b) / 2) for a, b in zip(left, right)]
            row["repeatability"] = {"median": stats.median(delta), "p90": quantile(delta, .90)}
        report[key] = row
    return report


def diagnostic_harness(original):
    src = original.replace(
        "startTime := AwfyPlatform microseconds.",
        "i = 1 ifTrue: [self bgGateSnapshot: 'pre'].\n\tstartTime := AwfyPlatform microseconds.",
    ).replace(
        "runTime := endTime - startTime.",
        "i = 1 ifTrue: [self bgGateSnapshot: 'lap1'].\n\trunTime := endTime - startTime.",
    ).replace(
        "self doRuns: bench.",
        """self doRuns: bench.
	self bgGateSnapshot: 'end'.
	ScriptConsole println: '# bg-jit-params ', (Smalltalk vm jitParameters
		inject: '' into: [:s :each | s, '|', each asString]).""",
    )
    require(src.count("self bgGateSnapshot:") == 3 and src.count("# bg-jit-params") == 1,
            "diagnostic overlay anchors changed")
    return src + """
!Run methodsFor: 'bg gate diagnostic'!
bgGateSnapshot: label
	| counters out |
	counters := Smalltalk vm statistics counters.
	out := WriteStream on: String new.
	out nextPutAll: '# bg-jit-snapshot '; nextPutAll: label.
	counters do: [:v | out space; print: v].
	ScriptConsole println: out contents
! !
"""


def run_vm(cmd, env, cwd, name, cpus):
    """Read the first CSV marker as it arrives; wait4 covers all VM threads."""
    first = None
    data = bytearray()
    pattern = re.compile(rb"(?m)^" + name.encode() + rb",1,[0-9]+\r?\n")
    started = time.monotonic()
    proc = sp.Popen(cmd, env=env, cwd=cwd, stdin=sp.DEVNULL, stdout=sp.PIPE,
                    stderr=sp.STDOUT, start_new_session=True)
    masks = set()
    reaped = False
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while True:
                left = 90 - (time.monotonic() - started)
                require(left > 0, "VM exceeded 90s")
                for entry, _ in selector.select(min(left, .05)):
                    chunk = os.read(entry.fd, 65536)
                    if not chunk:
                        selector.unregister(entry.fd)
                        continue
                    data.extend(chunk)
                    require(len(data) < 2**20, "excessive VM output")
                    if first is None and pattern.search(data):
                        first = time.monotonic() - started
                for task in Path(f"/proc/{proc.pid}/task").glob("*"):
                    status = read(task / "status")
                    if status:
                        match = re.search(r"^Cpus_allowed_list:\s*(.+)$", status, re.M)
                        if match:
                            masks.add(match[1])
                if not reaped:
                    child, status, ru = os.wait4(proc.pid, os.WNOHANG)
                    if child:
                        ended = time.monotonic()
                        proc.returncode = os.waitstatus_to_exitcode(status)
                        reaped = True
                if reaped and not selector.get_map():
                    break
    finally:
        if not reaped:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait()
        proc.stdout.close()
    result = {"exit": proc.returncode, "launch_to_first_s": first,
              "vm_wall_s": ended - started, "vm_cpu_s": ru.ru_utime + ru.ru_stime,
              "vm_user_s": ru.ru_utime, "vm_sys_s": ru.ru_stime, "peak_rss_kib": ru.ru_maxrss,
              "observed_thread_masks": sorted(masks)}
    require(all(cpuset(m) == cpus for m in masks), f"unexpected VM thread masks: {masks}")
    return result, data.decode(errors="replace")


def leg(folder, cell, arm, cpus, overlay=None):
    folder.mkdir(parents=True)
    vm = ROOT / ("A" if arm == "A" else "B") / "vm/build/samaltak"
    harness = overlay or AWFY / "Harness.st"
    sources = [AWFY / "Samaltak.st", harness, AWFY / "Core.st", AWFY / f"{cell}.st"]
    residency = warm([vm, IMAGE, *sources])
    with tempfile.TemporaryDirectory(prefix="bg-jit-leg-") as d:
        env = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC",
               "HOME": d, "SDL_VIDEO_DRIVER": "samaltak_no_video",
               "SDL_VIDEODRIVER": "samaltak_no_video"}
        for key in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME",
                    "XDG_RUNTIME_DIR", "TMPDIR"):
            p = Path(d) / key.lower()
            p.mkdir(mode=0o700)
            env[key] = str(p)
        fileins = ". ".join(f"Compiler fileIn: '{p}'" for p in sources)
        expr = (f"[{fileins}. (Smalltalk at: #Harness) new run: "
                f"#('{cell}' '{LAPS}' '{CELLS[cell]}'). ''] "
                "on: Error do: [:e | Smalltalk vm stderrWrite: 'ERROR ', e messageText, "
                "(String with: Character lf). Smalltalk quit: 1]")
        mask = ",".join(map(str, sorted(cpus)))
        cmd = ["taskset", "-c", mask, str(vm), "--jit", "opt", "--jit-threshold", "2",
               "--jit-osr", "50", "--jit-opt", "1000", "--jit-cache", "64",
               "--eden", "16", "--max-heap", "4096"]
        if arm == "C":
            cmd += ["--jit-flags", "bg"]
        cmd += [str(IMAGE), "--headless", "--eval", expr]
        dump(folder / "launch.json", {"argv": cmd, "env": env, "cwd": d, "warm_residency": residency})
        result, output = run_vm(cmd, env, d, cell, cpus)
    (folder / "awfy.log").write_text(output)
    require(result["exit"] == 0, f"{cell}/{arm}: VM exit {result['exit']}: {output[-1500:]}")
    require(result["launch_to_first_s"] is not None, f"{cell}/{arm}: missing first output marker")
    result.update(parse(output.replace("\r\n", "\n"), output, cell), cell=cell, arm=arm)
    if arm != "A":
        jobs = workload_counters(result["stats"], BG_SLOTS)
        result["jobs"] = jobs
        if arm == "B":
            require(not any(jobs.values()), "candidate default-off used a background job")
    if overlay:
        params = keyed(r"^# bg-jit-params \|([^\n]+)$", output).strip().split("|")
        require(len(params) == 6 and params[0] == "opt" and
                ("bg" in params[1].split(",")) == (arm == "C"), f"unexpected JIT params {params}")
        result["jit_params"] = [params[0], sorted(set(params[1].split(",")) - {"bg"}), *params[2:]]
        if arm != "A":
            snap = {tag: counters(BG_SLOTS, list(map(int, keyed(
                r"^# bg-jit-snapshot " + tag + r" ([-0-9 ]+)$", output).split())))
                    for tag in ("pre", "lap1", "end")}
            if arm == "B":
                require(not any(snap["end"].values()), "candidate default-off used a background job")
            result["diagnostic_snapshots"] = snap
            result["first_lap_install"] = snap["lap1"]["installed"] > snap["pre"]["installed"]
    dump(folder / "result.json", result)
    return result


def compare(logs):
    cpus = cpuset((logs / "cpus.txt").read_text().strip())
    require(len(cpus) == 2 and cpus <= os.sched_getaffinity(0), "chosen CPUs no longer permitted")
    rng = random.Random(SEED)
    schedule = []
    for label, ref, test, count in (("AA", "A", "A", 10), ("AB", "A", "B", 12), ("BC", "B", "C", 12)):
        cells = list(CELLS)
        rng.shuffle(cells)
        for cell in cells:
            order = [False, True] * (count // 2)
            rng.shuffle(order)
            schedule.append({"comparison": label, "cell": cell, "arms": [ref, test],
                             "reverse": order, "bootstrap_seed": rng.randrange(2**32)})
    dump(logs / "schedule.json", schedule)
    diag, report = {}, {}
    with tempfile.TemporaryDirectory(prefix="bg-jit-diag-") as d:
        overlay = Path(d) / "Harness.st"
        overlay.write_text(diagnostic_harness((AWFY / "Harness.st").read_text()))
        for cell in CELLS:
            results = [leg(logs / "diagnostic" / cell / a, cell, a, cpus, overlay) for a in "ABC"]
            require(all(r["jit_params"] == results[0]["jit_params"] for r in results),
                    f"{cell}: JIT parameters differ beyond opt-in flag")
            diag[cell] = results[-1]["first_lap_install"]
    dump(logs / "first-lap-install-diagnostic.json", diag)
    for spec in schedule:
        label, cell = spec["comparison"], spec["cell"]
        folder = logs / label / cell
        folder.mkdir(parents=True)
        before = host(cpus)
        pairs = []
        for i, rev in enumerate(spec["reverse"], 1):
            legs = [None, None]
            for j in ((1, 0) if rev else (0, 1)):
                legs[j] = leg(folder / f"{i:02d}-{j}", cell, spec["arms"][j], cpus)
                time.sleep(PAUSE)
            pairs.append(legs)
        after = host(cpus)
        bad = noise(before, after)
        metrics = summary(pairs, spec)
        installs = [c["jobs"]["installed"] for _, c in pairs] if label == "BC" else None
        gate = {}
        for key in ENDPOINTS:
            m = metrics[key]
            if bad:
                gate[key] = "inconclusive: host counters"
            elif label == "AA":
                rep = m["repeatability"]
                gate[key] = ("pass" if rep["median"] <= .02 and rep["p90"] <= .05
                             else "inconclusive: A/A noise")
            elif label == "BC" and not all(installs):
                gate[key] = "inconclusive: not all worker-on legs installed"
            elif report["AA"][cell]["gate"][key] != "pass":
                gate[key] = "inconclusive: A/A noise"
            else:
                low, high = m["paired_bootstrap_95"]
                gate[key] = ("regression" if low > LIMIT else
                             "pass" if high <= LIMIT else "inconclusive: CI crosses +5%")
        report.setdefault(label, {})[cell] = {
            "metrics": metrics, "gate": gate, "noise": bad, "installs": installs,
        }
        dump(folder / "host.json", {"before": before, "after": after})
        dump(logs / "paired-summary.json", report)
        show = ["first_us", "steady_us", "launch_to_first_s", "vm_cpu_s"]
        ratios = {k: round((metrics[k]["median_ratio"] - 1) * 100, 2) for k in show}
        print(f"{label} {cell}: % changes {ratios}; {gate}; installs={installs}", flush=True)

    path = Path(os.environ["GITHUB_STEP_SUMMARY"])
    with path.open("a") as out:
        print("### Native ARM64 background JIT (distinct guest cores; physical mapping unknown)\n", file=out)
        print("A = base; B = candidate default-off; C = candidate with ordinary `--jit-flags bg`. "
              "AB is the decisive default-off regression gate. Positive means slower/more CPU. "
              "Whole-process CPU (user + system, including worker) is not a startup time. "
              "Launch-to-first-output includes image load and AWFY file-ins; lap 1 excludes them.\n", file=out)
        print("| Pair | Workload | First lap wall | Steady lap wall | Launch → first output | Total CPU | "
              "C installs (min–max) | Wall gate (first / steady) |", file=out)
        print("|---|---|---:|---:|---:|---:|---:|---|", file=out)
        for label in ("AB", "BC"):
            for cell, r in sorted(report[label].items()):
                pct = [f"{(r['metrics'][k]['median_ratio']-1)*100:+.1f}%" for k in show]
                jobs = r["installs"]
                installed = f"{min(jobs)}–{max(jobs)}" if jobs is not None else "—"
                print(f"| {label} | {cell} | {' | '.join(pct)} | {installed} | "
                      f"{' / '.join(r['gate'].values())} |", file=out)
        active = ", ".join(k for k, v in diag.items() if v) or "none"
        print(f"\nSeparate untimed diagnostic saw an install during lap 1: {active}. "
              "This is not a timing or causal witness.", file=out)
    ab = [v for r in report["AB"].values() for v in r["gate"].values()]
    bc_active = all(all(r["installs"]) for r in report["BC"].values())
    if "regression" in ab:
        sys.exit("AB: candidate default-off wall regression exceeds +5%")
    if any(v != "pass" for v in ab) or not bc_active:
        print("AB default-off gate and/or BC activation inconclusive; do not infer a pass for unresolved cells.",
              file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    action, location = sys.argv[1:]
    {"topology": topology, "compare": compare}[action](Path(location))
