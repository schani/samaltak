#!/usr/bin/env python3
"""Read-only native A/B gate for two separately built VM/image pairs."""
import argparse
import csv
import hashlib
import os
import platform
import re
import resource
import shlex
import signal
import statistics
import subprocess
from fractions import Fraction
from pathlib import Path
from time import sleep

LAPS = 12
TARGET, ARRAY = "AffineByteScan", "EPtrArrayScan"
WORK = (TARGET, ARRAY, "NBody:250000", "Richards:7")
FIXTURE = Path(__file__).resolve().with_name("affine-target.st")
CASES = {
    TARGET: ("runAffine:", "checksum:at:with:at:count:", "3006848"),
    ARRAY: ("runArray:", "checksumTagged:to:", "200010000"),
}
HOIST = "within bounds: checked once before the loop"
CHECK = "bounds check"
GUARD = "guard: at most the other, once before the loop (its indexed accesses check no bounds)"
TAGGED = "address from tagged pointer index"
INSTR = re.compile(r"^\s*\+([0-9a-f]+)\s+([0-9a-f]+)\s+([^;]+?)(?:\s*;\s*(.*))?$", re.I)


def need(ok, message):
    if not ok:
        raise ValueError(message)


def digest(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def result(lines, spec, path):
    name, _, inner = spec.partition(":")
    case = CASES.get(name)
    rows = [line.split(",") for line in lines if line.startswith(name + ",")]
    need(len(rows) == LAPS and all(
        len(row) == (4 if case else 3) and row[1] == str(i)
        and re.fullmatch(r"[1-9][0-9]*", row[2]) and (not case or row[3] == case[2])
        for i, row in enumerate(rows, 1)), f"{path}: bad laps, timings or checksum")
    counters = [line for line in lines if line.startswith(f"# stats {name} ")]
    need(len(counters) == 1 and re.search(r"\boptMethodsCompiled=[1-9][0-9]*\b", counters[0]),
         f"{path}: no optimization recorded during benchmark")
    if not case:
        need(lines.count(f"# run {name} inner={inner}") == 1, f"{path}: wrong AWFY workload")
    times = [Fraction(row[2]) for row in rows]
    return times[0], statistics.median(times[6:])


def method_symbol(name):
    return f"AffineBoundsBench>>{CASES[name][1]}"


def full_method_events(perf, name):
    # The runtime emits these at successful non-copy compilation. Only the
    # bare symbol is the full method; optimized blocks and OSR have suffixes.
    symbol = "opt:" + method_symbol(name)
    row = re.compile(r"([0-9A-Fa-f]+)\s+([0-9A-Fa-f]+)\s+" + re.escape(symbol))
    events = []
    for line in perf:
        if line.split(maxsplit=2)[-1:] != [symbol]:
            continue
        hit = row.fullmatch(line)
        need(hit is not None, f"{symbol}: malformed perf-map event")
        address, size = (int(part, 16) for part in hit.groups())
        need(address > 0 and size > 0, f"{symbol}: zero perf-map address or size")
        events.append((address, size))
    need(bool(events), f"{symbol}: no live full-method optimization event (OSR/block rows do not count)")
    return events


def shape(listing, name, side, arch):
    # machineCodeFor: #opt can compile a scratch copy with the method's
    # feedback. Inspect this listing independently of the live perf-map events.
    symbol = method_symbol(name)
    need(bool(listing), "empty listing")
    header = re.fullmatch(re.escape(symbol) + r"  opt, ([1-9][0-9]*) bytes at 16r([0-9a-fA-F]+)",
                          listing[0])
    need(header is not None, f"{symbol}: absent optimized method listing")
    size, address = int(header[1]), int(header[2], 16)
    need(address > 0, f"{symbol}: invalid listing address")

    need(sum(HOIST in line for line in listing) == (1 if name == ARRAY else 2 if side == "B" else 0)
         and sum(CHECK in line for line in listing) == (2 if name == TARGET and side == "A" else 0),
         f"{symbol}: unexpected hoisted/in-body bounds annotation counts")
    code, notes, offsets = [], {}, []
    for line in listing[1:]:
        hit = INSTR.fullmatch(line)
        if hit:
            offsets.append(int(hit[1], 16))
            code.append(hit[3].strip().lower())
            notes[len(code) - 1] = hit[4] or ""
        elif code and line.lstrip().startswith(";"):
            notes[len(code) - 1] += " " + line.lstrip()[1:].strip()
    need(len(offsets) > 0 and offsets == sorted(set(offsets)) and offsets[-1] < size,
         f"{symbol}: missing or malformed disassembly")
    tag_count = sum(TAGGED in line for line in listing)
    if name == ARRAY:
        i = next((i for i, note in notes.items() if HOIST in note), -1)
        need(i >= 0, f"{symbol}: missing Array load annotation on an instruction")
        if arch == "arm64":
            need(tag_count == 1 and TAGGED in notes[i]
                 and re.fullmatch(r"add x17, x\d+, x\d+, lsl #2", code[i])
                 and any(re.fullmatch(r"ldur x\d+, \[x17, #(?:0x)?4\]", op)
                         for op in code[i+1:i+2]), f"{symbol}: no tagged ARM64 pointer load")
        else:
            need(tag_count == 0 and any(re.fullmatch(r"sar\s+r12,\s*(?:0x)?1", a)
                 and re.fullmatch(r"mov\s+\w+,\s*qword ptr \[\w+\+r12\*8\+0x8\]", b)
                 for a, b in zip(code[i:i+2], code[i+1:i+3])),
                 f"{symbol}: no x86 shift + indexed pointer load")
        return address, size

    need(tag_count == 0, f"{symbol}: pointer-load variant in ByteArray scan")
    checked = side == "A"
    disp = "10" if checked else "f"
    load = (r"ldrb w16, \[x16, x17\]" if arch == "arm64"
            else rf"movzx\s+r10d,\s*byte ptr \[\w+\+r12\*1\+0x{disp}\]")
    indexed = [i for i, op in enumerate(code) if re.fullmatch(load, op)]
    sites = [i for i, note in notes.items() if (CHECK if checked else HOIST) in note]
    need(len(indexed) == len(sites) == 2,
         f"{symbol}: did not find two annotated native ByteArray loads")
    for k, (site, index) in enumerate(zip(sites, indexed)):
        distance = index - site
        need(1 <= distance <= (18 if checked else 5) and (k == 1 or index < sites[1]),
             f"{symbol}: load not paired with its own bounds annotation")
        # Confirm the annotated checked sites actually compare and branch before the load.
        if checked:
            branch = r"b\.(?:hs|cs)\s+\w+" if arch == "arm64" else r"j(?:ae|nb|nc)\s+\w+"
            need(any(re.fullmatch(branch, op) for op in code[site:index]),
                 f"{symbol}: annotated in-body bounds check has no unsigned branch")
    if not checked:
        need(sum(GUARD in line for line in listing) >= 2,
             f"{symbol}: missing loop-entry bounds guards")

    return address, size


def witness_report(listing, perf, name, side, arch):
    events = full_method_events(perf, name)
    address, size = shape(listing, name, side, arch)
    symbol = method_symbol(name)
    report = [
        f"PASS: {arch} {name} {side}: full-method optimization event + annotated listing shape",
        "Live run perf map (successful non-scratch compilation; not execution samples or current residency):",
        *(f"  {pc:x} {n:x} opt:{symbol}" for pc, n in events),
        f"Annotated inspection listing (may be scratch): {symbol}, {size} bytes at 0x{address:x}",
        f"Listing address+size matches an event (diagnostic only): {'yes' if (address, size) in events else 'no'}",
        "Shape was checked in the listing, not in the mapped live bytes.",
    ]
    return "\n".join(report) + "\n"


class Runner:
    def __init__(self, root, logs, arch):
        self.root, self.logs, self.arch = root, logs, arch
        self.driver = root / "A/vm/tests/bench/awfy.sh"

    def inputs(self):
        paths = [FIXTURE, Path(__file__).resolve(), self.driver]
        for side in ("A", "B"):
            vm, img = self.vm(side)
            with vm.open("rb") as f:
                elf = f.read(20)
            machine = 183 if self.arch == "arm64" else 62
            need(elf[:6] == b"\x7fELF\x02\x01" and int.from_bytes(elf[18:20], "little") == machine,
                 f"{vm}: wrong ELF architecture")
            need(img.is_file() and img.stat().st_size > 0, f"{img}: no image")
            paths.extend((vm, img))
        need(not os.path.samefile(self.vm("A")[0], self.vm("B")[0])
             and not os.path.samefile(self.vm("A")[1], self.vm("B")[1]),
             "provide two separately staged VM/image pairs")
        paths.extend(self.driver.parent / "awfy" / f"{name}.st" for name in
                     ("Samaltak", "SamaltakCPU", "Harness", "Core", "NBody", "Richards"))
        return {str(p): digest(p) for p in paths}

    def vm(self, side):
        return self.root / side / "vm/build/samaltak", self.root / side / "build/samaltak.image"

    def run(self, cmd, stem, witness=False):
        cwd = self.logs / "scratch" / stem
        cwd.mkdir(parents=True, mode=0o700)
        env = {k: v for k, v in os.environ.items()
               if not k.startswith(("SAMALTAK_", "LD_", "XDG_", "SDL_"))
               and k not in ("DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "PHARO_IMAGE", "PHARO_VM")}
        env.update(HOME=str(cwd), TMPDIR=str(cwd), LC_ALL="C",
                   SDL_VIDEO_DRIVER="samaltak_no_video", SDL_VIDEODRIVER="samaltak_no_video")
        if witness:
            env["SAMALTAK_PERF_MAP"] = "1"
        log = self.logs / f"{stem}.log"
        print(stem, flush=True)
        with (self.logs / "commands.txt").open("a") as commands:
            print(f"{stem}: {shlex.join(map(str, cmd))}", file=commands)
        with log.open("x") as f:
            proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=f, stderr=subprocess.STDOUT,
                                    start_new_session=True)
            perf = Path(f"/tmp/perf-{proc.pid}.map")
            try:
                need(proc.wait(timeout=180) == 0, f"{log}: exit {proc.returncode}")
                if witness:
                    need(perf.is_file() and not perf.is_symlink() and perf.stat().st_uid == os.getuid(),
                         f"{log}: missing witness perf map")
                    (self.logs / f"{stem}.map").write_bytes(perf.read_bytes())
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait()
                raise
            finally:
                if witness and perf.is_file() and not perf.is_symlink() and perf.stat().st_uid == os.getuid():
                    perf.unlink()
        return log

    def expression(self, side, args, expr, stem, witness=False):
        vm, img = self.vm(side)
        return self.run([vm, "--jit", "opt", *args, img, "--headless", "--eval", expr], stem, witness)

    def focused(self, side, selector):
        expr = (f"| r | Smalltalk vm jitArchitecture = #{self.arch} ifFalse: [Smalltalk quit: 1]. "
                f"r := (JitOptRuntimeTest selector: #{selector}) run. "
                "Transcript show: r summary; cr. "
                "Smalltalk quit: ((r passed size = 1 and: [r runCount = 1]) ifTrue: [0] ifFalse: [1])")
        log = self.expression(side, ["--jit-threshold", "0", "--jit-flags", "eager"], expr,
                              f"test-{side}-{selector}")
        need(re.search(r"^1 run, 1 passed, 0 failed, 0 errors(?: in \d+ ms)?$",
                       log.read_text(), re.M), f"{log}: focused test did not pass")

    def trial(self, side, spec, stem, witness=False):
        if spec in CASES:
            runner, selector, _ = CASES[spec]
            expr = (f"| o | Smalltalk vm jitArchitecture = #{self.arch} ifFalse: [Smalltalk quit: 1]. "
                    f"o := AffineBoundsBench new. o {runner} {LAPS}. ")
            if witness:
                expr += f"o printListing: #{selector} of: '{spec}'. "
            # --load is an image option, after the image path.
            vm, img = self.vm(side)
            flags = ["--jit-flags", "notes"] if witness else []
            log = self.run([vm, "--jit", "opt", *flags, img, "--headless", "--load", FIXTURE,
                            "--eval", expr + "Smalltalk quit: 0"], stem, witness)
            lines = log.read_text().splitlines()
            if witness:
                a, b = f"# listing {spec}", f"# end listing {spec}"
                need(lines.count(a) == lines.count(b) == 1, f"{log}: missing or repeated listing")
                start, end = lines.index(a), lines.index(b)
                need(start < end and not any(line.startswith(spec + ",") for line in lines[start:]),
                     f"{log}: listing must follow all laps")
                listing = lines[start+1:end]
                (self.logs / f"{stem}.asm").write_text("\n".join(listing) + "\n")
                times = result(lines, spec, log)
                perf = (self.logs / f"{stem}.map").read_text().splitlines()
                (self.logs / f"{stem}.witness.txt").write_text(
                    witness_report(listing, perf, spec, side, self.arch))
                return times
            else:
                need(not any(line.startswith("# listing ") for line in lines), f"{log}: listing in timing run")
        else:
            vm, img = self.vm(side)
            raw = self.logs / f"{stem}.csv"
            self.run(["sh", self.driver, "--vm", vm, "--image", img, "--vm-args", "--jit opt",
                      "--cpu", "-n", str(LAPS), "-o", raw, spec], stem)
            log, lines = raw, raw.read_text().splitlines()
        return result(lines, spec, log)

    def gate(self):
        common = ("testCountedLoopsCheckBoundsOnce", "testUncheckedPointerLoadAddressing")
        extra = ("testAffineCountedLoopBounds", "testAffineCountedLoopOverflowFallsBack")
        for side in ("A", "B"):
            for test in common + (extra if side == "B" else ()):
                self.focused(side, test)
            for name in CASES:
                self.trial(side, name, f"witness-{name}-{side}", witness=True)

    def compare(self):
        scores = {}
        with (self.logs / "pairs.csv").open("x", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(("round", "workload", "pair", "order", "metric", "A_us", "B_us", "B_vs_A_pct"))
            orders = ("AB", "BA", "AB", "BA")
            for batch in (1, 2):
                sleep(10)
                for spec in WORK if batch == 1 else WORK[::-1]:
                    deltas = {"first": [], "steady": []}
                    for pair, order in enumerate(orders if batch == 1 else orders[::-1], 1):
                        vals = {side: self.trial(side, spec, f"r{batch}-{spec.split(':')[0]}-{pair}-{side}")
                                for side in order}
                        for i, (metric, ds) in enumerate(deltas.items()):
                            a, b = vals["A"][i], vals["B"][i]
                            d = 100 * (b / a - 1)
                            ds.append(d)
                            writer.writerow((batch, spec, pair, order, metric, float(a), float(b), f"{float(d):+.4f}"))
                        f.flush()
                    for metric, ds in deltas.items():
                        scores.setdefault((spec, metric), []).append(statistics.median(ds))
        with (self.logs / "summary.csv").open("x", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(("workload", "metric", "round1_pct", "round2_pct"))
            for (spec, metric), ds in scores.items():
                writer.writerow((spec, metric, *(f"{float(d):+.4f}" for d in ds)))
        return verdict(scores)


def verdict(scores):
    repeat = [" ".join(k) for k, ds in scores.items() if all(d > 5 for d in ds)]
    once = [" ".join(k) for k, ds in scores.items() if any(d > 5 for d in ds)]
    if repeat:
        return "FAIL: >5% slowdown in both rounds: " + ", ".join(repeat)
    if once:
        return "HOLD: >5% slowdown in one round: " + ", ".join(once)
    if not all(d <= -2 for d in scores[TARGET, "steady"]):
        return "HOLD: 2% steady target gain not confirmed in both rounds"
    return "PASS: paired timing gate"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("gate", "compare"), help="focused tests + witnesses; compare also times")
    parser.add_argument("root", type=Path, help="directory containing separately staged A and B trees")
    parser.add_argument("logs", type=Path, help="new evidence directory, outside the input trees")
    parser.add_argument("--arch", required=True, choices=("x86_64", "arm64"))
    args = parser.parse_args()
    root, logs = args.root.resolve(), args.logs.resolve()
    # Avoid writing into either source tree even if the caller misconfigures logs.
    need(not any(logs.is_relative_to((root / side).resolve()) for side in ("A", "B")),
         "logs must be outside the input trees")
    need(platform.system() == "Linux" and platform.machine() ==
         ("aarch64" if args.arch == "arm64" else "x86_64"), "wrong native Linux architecture")
    os.umask(0o077)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    logs.mkdir(mode=0o700)
    report = "NO DECISION: incomplete evidence"
    try:
        (logs / "host.txt").write_text(
            f"{platform.uname()}\naffinity={sorted(os.sched_getaffinity(0))}\n"
            f"clock=thread CPU; laps={LAPS}\n")
        runner = Runner(root, logs, args.arch)
        before = runner.inputs()
        (logs / "inputs.sha256").write_text("".join(f"{h}  {p}\n" for p, h in before.items()))
        try:
            runner.gate()
            decision = (runner.compare() if args.mode == "compare" else
                        "PASS: focused tests, full-method optimization events, and annotated listing shapes")
        finally:
            need(runner.inputs() == before, "inputs changed during gate")
            (logs / "integrity.txt").write_text("VM/image pairs and measured sources unchanged\n")
        report = decision
    except (OSError, ValueError, subprocess.TimeoutExpired, KeyboardInterrupt) as exc:
        report = f"NO DECISION: {exc or type(exc).__name__}"
    finally:
        (logs / "verdict.txt").write_text(report + "\n")
        print(report)
    return 0 if report.startswith("PASS:") else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as exc:
        raise SystemExit(f"NO DECISION: {exc}")
