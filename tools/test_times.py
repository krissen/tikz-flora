"""Shows and compares the test times tools/test.sh --times writes (docs/testing.md).

    python3 -I tools/test_times.py show TIMES [--jobs N|auto]
    python3 -I tools/test_times.py compare OLD NEW
    python3 -I tools/test_times.py run JOBS [TEST...]

show prints the table, most CPU first, with totals, and the least wall
time N jobs could take on the same CPU times (each test started on the
first free job, longest first; at least the longest single test). auto
is the number of jobs the run recorded.
compare prints each test's CPU seconds in both runs and the change. CPU
time (user + sys) is what to compare between runs: wall time depends on
the machine's load, which each file records on its last line.

run is what `just test-times` does: tools/test.sh -j JOBS --times FILE
with a FILE of this run's own, build/test-times/STAMP-PID.tsv, then show.
Nothing deletes a times file; build/ can be emptied by hand. The run's
output is kept beside it as STAMP-PID.out and shown, with the path of the
times, when the run did not succeed. build/test-times.tsv is a link to the
latest run's file; when it cannot be made the run says so, names the real
file, and exits non-zero.

A file that is empty, lacks its header or its closing line (a run that
did not finish writing it), or has a line that is not a test's times is
refused with the line named (exit status 2). A test that failed, or has
no times (NA), is marked and left out of the totals and the schedule;
compare totals only the tests both files timed and passed, and names
those it left out.
"""

import argparse
import heapq
import os
import re
import subprocess
import sys
import time

HEADER = ["test", "status", "wall", "user", "sys", "cpu"]


class TimesError(Exception):
    pass


def read(path):
    """The rows of a times file by test, and its closing note."""
    try:
        with open(path) as f:
            lines = f.read().splitlines()
    except OSError as e:
        raise TimesError(f"{path}: {e.strerror}") from None
    if not lines:
        raise TimesError(f"{path}: empty")
    if lines[0].split("\t") != HEADER:
        raise TimesError(f"{path}:1: not a times file's header: {lines[0]!r}")
    if not lines[-1].startswith("#"):
        raise TimesError(f"{path}: no closing line; the file was not written whole")
    rows = {}
    for n, line in enumerate(lines[1:-1], start=2):
        parts = line.split("\t")
        if len(parts) != len(HEADER):
            raise TimesError(f"{path}:{n}: {len(parts)} fields, not {len(HEADER)}: {line!r}")
        name, status = parts[0], parts[1]
        if name in rows:
            raise TimesError(f"{path}:{n}: {name} twice")
        try:
            st = int(status) if status != "NA" else None
            if parts[2:] == ["NA"] * 4:
                times = None
            else:
                times = dict(zip(HEADER[2:], (float(x) for x in parts[2:])))
        except ValueError:
            raise TimesError(f"{path}:{n}: not a test's times: {line!r}") from None
        rows[name] = {"status": st, "times": times}
    if not rows:
        raise TimesError(f"{path}: no tests")
    return rows, lines[-1][1:].strip()


def counted(r):
    """Whether a row's time counts: the test passed and has times."""
    return r["status"] == 0 and r["times"] is not None


def mark(r):
    if r["times"] is None:
        return "NA (no times)"
    if r["status"] != 0:
        return f"FAIL (status {r['status']})"
    return ""


def schedule(cpus, jobs):
    """The wall time of jobs workers taking the longest test first."""
    free = [0.0] * jobs
    for c in sorted(cpus, reverse=True):
        t = heapq.heappop(free)
        heapq.heappush(free, t + c)
    return max(free) if free else 0.0


def cpu(r):
    return r["times"]["cpu"] if r["times"] else 0.0


def jobs_arg(text):
    """A whole number of at least 1, or auto (the jobs the run recorded)."""
    if text == "auto":
        return text
    try:
        n = int(text)
    except ValueError:
        n = 0
    if n < 1:
        raise argparse.ArgumentTypeError(f"takes a whole number of at least 1 or auto, not {text!r}")
    return n


def show(path, jobs):
    rows, note = read(path)
    if jobs == "auto":
        m = re.search(r"\bjobs=(\d+)", note)
        jobs = int(m.group(1)) if m else max(1, (os.cpu_count() or 2) // 2)
    order = sorted(rows, key=lambda n: -cpu(rows[n]))
    good = [r for r in rows.values() if counted(r)]
    total = sum(cpu(r) for r in good)
    print(f"{'test':32} {'cpu s':>9} {'share':>6} {'wall s':>9}  status")
    for n in order:
        r = rows[n]
        if r["times"] is None:
            print(f"{n:32} {'NA':>9} {'':>6} {'NA':>9}  {mark(r)}")
            continue
        share = f"{100 * cpu(r) / total:5.1f}%" if total and counted(r) else f"{'':>6}"
        print(f"{n:32} {cpu(r):9.1f} {share} {r['times']['wall']:9.1f}  {mark(r)}")
    left = len(rows) - len(good)
    print(f"{'total':32} {total:9.1f}" + (f"  ({left} failed or untimed, left out)" if left else ""))
    print(f"measured: {note}")
    cpus = [cpu(r) for r in good]
    for j in sorted({1, 2, 4, 8, jobs or 1}):
        print(f"least wall at -j {j}: {schedule(cpus, j):.0f} s")


def compare(old_path, new_path):
    old, onote = read(old_path)
    new, nnote = read(new_path)
    names = sorted(set(old) | set(new), key=lambda n: -max(cpu(old[n]) if n in old else 0, cpu(new[n]) if n in new else 0))
    print(f"{'test':32} {'old cpu':>9} {'new cpu':>9} {'change':>8}")
    ta = tb = 0.0
    both, out = 0, []
    for n in names:
        a, b = old.get(n), new.get(n)
        sa = f"{cpu(a):9.1f}" if a and a["times"] else f"{'-' if not a else 'NA':>9}"
        sb = f"{cpu(b):9.1f}" if b and b["times"] else f"{'-' if not b else 'NA':>9}"
        ok = a is not None and b is not None and counted(a) and counted(b)
        ch = f"{100 * (cpu(b) - cpu(a)) / cpu(a):+7.0f}%" if ok and cpu(a) > 0 else ""
        why = ""
        if not ok:
            if a is None:
                why = "only in new"
            elif b is None:
                why = "only in old"
            else:
                why = "; ".join(f"{side} {mark(r)}" for side, r in (("old", a), ("new", b)) if mark(r))
            out.append(n)
        else:
            ta, tb, both = ta + cpu(a), tb + cpu(b), both + 1
        print(f"{n:32} {sa} {sb} {ch:>8}" + (f"  {why}" if why else ""))
    change = f"{100 * (tb - ta) / ta:+7.0f}%" if ta else ""
    print(f"{'total':32} {ta:9.1f} {tb:9.1f} {change:>8}  over the {both} tests both runs timed and passed")
    if out:
        print(f"left out of the total: {', '.join(out)}")
    print(f"old: {onote}\nnew: {nnote}")


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNS = os.path.join("build", "test-times")
POINTER = os.path.join("build", "test-times.tsv")


def tail(path, n):
    with open(path, errors="replace") as f:
        return "".join(f.readlines()[-n:])


def point(times):
    """build/test-times.tsv, made a link to this run's file; the file
    itself is never touched."""
    link = os.path.join(ROOT, POINTER)
    tmp = f"{link}.{os.getpid()}"
    try:
        os.symlink(os.path.relpath(os.path.join(ROOT, times), os.path.dirname(link)), tmp)
        os.replace(tmp, link)
    except OSError as e:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise TimesError(f"cannot point {POINTER} at it ({e.strerror}); the times are in {os.path.join(ROOT, times)}") from None


def run_tests(jobs, names):
    """One run of tools/test.sh with its times kept, shown and pointed to."""
    try:
        os.makedirs(os.path.join(ROOT, RUNS), exist_ok=True)
    except OSError as e:
        raise TimesError(f"cannot make {RUNS} ({e.strerror}); no test was run") from None
    base = os.path.join(RUNS, f"{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}-{os.getpid()}")
    times, log = base + ".tsv", base + ".out"
    try:
        out = open(os.path.join(ROOT, log), "w")  # noqa: SIM115
    except OSError as e:
        raise TimesError(f"cannot write {log} ({e.strerror}); no test was run") from None
    with out:
        rc = subprocess.run([os.path.join(ROOT, "tools", "test.sh"), "-j", jobs, "--times", times, *names], cwd=ROOT, stdout=out, stderr=subprocess.STDOUT, check=False).returncode
    problem = None
    if os.path.exists(os.path.join(ROOT, times)):
        try:
            show(os.path.join(ROOT, times), jobs_arg(jobs))
            point(times)
        except (TimesError, argparse.ArgumentTypeError) as e:
            problem = str(e)
        print(f"times: {times} ({POINTER} points at it)" if problem is None else f"times: {times}")
    if rc != 0:
        print(tail(os.path.join(ROOT, log), 30), end="", file=sys.stderr)
        print(f"test_times: the whole output is in {log}", file=sys.stderr)
    if problem:
        raise TimesError(problem)
    return rc


def main():
    ap = argparse.ArgumentParser(description="Shows and compares the test times tools/test.sh --times writes.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("show")
    s.add_argument("times")
    s.add_argument("--jobs", type=jobs_arg, default=0)
    r = sub.add_parser("run")
    r.add_argument("jobs")
    r.add_argument("names", nargs="*")
    c = sub.add_parser("compare")
    c.add_argument("old")
    c.add_argument("new")
    a = ap.parse_args()
    try:
        if a.cmd == "show":
            show(a.times, a.jobs)
        elif a.cmd == "run":
            return run_tests(a.jobs, a.names)
        else:
            compare(a.old, a.new)
    except TimesError as e:
        print(f"test_times: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
