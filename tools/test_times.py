"""Shows and compares the test times tools/test.sh --times writes (docs/testing.md).

    python3 -I tools/test_times.py show TIMES [--jobs N]
    python3 -I tools/test_times.py compare OLD NEW

show prints the table, most CPU first, with totals, and the least wall
time N jobs could take on the same CPU times (each test started on the
first free job, longest first; at least the longest single test).
compare prints each test's CPU seconds in both runs and the change. CPU
time (user + sys) is what to compare between runs: wall time depends on
the machine's load, which each file records on its last line.

A file that is empty, lacks its header or its closing line (a run that
did not finish writing it), or has a line that is not a test's times is
refused with the line named (exit status 2). A test that failed, or has
no times (NA), is marked and left out of the totals and the schedule;
compare totals only the tests both files timed and passed, and names
those it left out.
"""

import argparse
import heapq
import sys

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


def show(path, jobs):
    rows, note = read(path)
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


def main():
    ap = argparse.ArgumentParser(description="Shows and compares the test times tools/test.sh --times writes.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("show")
    s.add_argument("times")
    s.add_argument("--jobs", type=int, default=0)
    c = sub.add_parser("compare")
    c.add_argument("old")
    c.add_argument("new")
    a = ap.parse_args()
    try:
        if a.cmd == "show":
            show(a.times, a.jobs)
        else:
            compare(a.old, a.new)
    except TimesError as e:
        print(f"test_times: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
