"""Shows and compares the test times tools/test.sh --times writes (docs/testing.md).

    python3 -I tools/test_times.py show TIMES [--jobs N]
    python3 -I tools/test_times.py compare OLD NEW

show prints the table, most CPU first, with totals, and the least wall
time N jobs could take on the same CPU times (each test started on the
first free job, longest first; at least the longest single test).
compare prints each test's CPU seconds in both runs and the change. CPU
time (user + sys) is what to compare between runs: wall time depends on
the machine's load, which each file records on its last line.
"""

import argparse
import heapq
import sys


def read(path):
    rows, note = {}, ""
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("#"):
                note = line[1:].strip()
                continue
            parts = line.split("\t")
            if parts[0] == "test" or len(parts) < 6:
                continue
            name, status, wall, user, sys_, cpu = parts[:6]
            rows[name] = {
                "status": int(status),
                "wall": float(wall),
                "user": float(user),
                "sys": float(sys_),
                "cpu": float(cpu),
            }
    return rows, note


def schedule(cpus, jobs):
    """The wall time of jobs workers taking the longest test first."""
    free = [0.0] * jobs
    for c in sorted(cpus, reverse=True):
        t = heapq.heappop(free)
        heapq.heappush(free, t + c)
    return max(free) if free else 0.0


def show(path, jobs):
    rows, note = read(path)
    order = sorted(rows, key=lambda n: -rows[n]["cpu"])
    total = sum(r["cpu"] for r in rows.values()) or 1.0
    print(f"{'test':32} {'cpu s':>9} {'share':>6} {'wall s':>9}  status")
    for n in order:
        r = rows[n]
        flag = "" if r["status"] == 0 else "FAIL"
        print(f"{n:32} {r['cpu']:9.1f} {100 * r['cpu'] / total:5.1f}% {r['wall']:9.1f}  {flag}")
    print(f"{'total':32} {total:9.1f}")
    if note:
        print(f"measured: {note}")
    cpus = [r["cpu"] for r in rows.values()]
    for j in sorted({1, 2, 4, 8, jobs or 1}):
        print(f"least wall at -j {j}: {schedule(cpus, j):.0f} s")


def compare(old_path, new_path):
    old, onote = read(old_path)
    new, nnote = read(new_path)
    names = sorted(set(old) | set(new), key=lambda n: -max(old.get(n, {}).get("cpu", 0), new.get(n, {}).get("cpu", 0)))
    print(f"{'test':32} {'old cpu':>9} {'new cpu':>9} {'change':>8}")
    for n in names:
        a, b = old.get(n), new.get(n)
        sa = f"{a['cpu']:9.1f}" if a else f"{'-':>9}"
        sb = f"{b['cpu']:9.1f}" if b else f"{'-':>9}"
        ch = f"{100 * (b['cpu'] - a['cpu']) / a['cpu']:+7.0f}%" if a and b and a["cpu"] > 0 else ""
        print(f"{n:32} {sa} {sb} {ch}")
    ta = sum(r["cpu"] for r in old.values())
    tb = sum(r["cpu"] for r in new.values())
    print(f"{'total':32} {ta:9.1f} {tb:9.1f} {100 * (tb - ta) / ta if ta else 0:+7.0f}%")
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
    if a.cmd == "show":
        show(a.times, a.jobs)
    else:
        compare(a.old, a.new)
    return 0


if __name__ == "__main__":
    sys.exit(main())
