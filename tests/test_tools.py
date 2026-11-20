"""The measuring tools report what happened, or refuse, when a run goes wrong.

tools/profile.lua: a timed function that raises an error inside a pcall
is timed to the error, its later calls are timed, and the error goes on
unchanged; recursive calls and calls from a coroutine are timed once; an
error or os.exit ends the run with a report that says so; an unknown
--time name, a bad option or an --out file that cannot be written stop
the run before it starts. tools/test.sh: a failing and a killed test get
their status in the times file; an interrupted run stops its tests and
writes no times; a --times file that cannot be written, a bad -j and a
test named twice stop the run before it starts. tools/test_times.py:
empty, headless, half-written and garbled files are refused, and compare
totals only the tests both runs timed and passed. tools/test-linux.sh:
every file the tests and tools/test.sh name is among those it sends the
container.

TOOLS_UNDER_TEST, a directory, takes the three tools from there instead
of tools/ (to show this test fails on an earlier version). TEST_SH_SHELL
runs tools/test.sh with that shell (e.g. dash, as /bin/sh is on Ubuntu)
instead of by its #!/bin/sh line.

    python3 -I tests/test_tools.py
"""

import glob
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.environ.get("TOOLS_UNDER_TEST") or os.path.join(ROOT, "tools")
PROFILE = os.path.join(TOOLS, "profile.lua")
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("FAIL: " + msg, file=sys.stderr)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def timed(report, name):
    """(seconds, calls, raised) of name's line in a profile report."""
    for line in report.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[3] == name and parts[1] == "s":
            raised = 0
            if "raised" in line:
                raised = int(line.split("(")[1].split()[0])
            return float(parts[0]), int(parts[2]), raised
    return None


BURN = """local M = {}
function M.work(fail)
  local x = 0
  for i = 1, 400000 do x = x + i % 7 end
  if fail == "string" then error("planned failure") end
  if fail == "table" then error(M.err) end
  return x, nil, "third"
end
M.err = { "an error value" }
function M.down(n)
  local x = 0
  for i = 1, 200000 do x = x + i % 5 end
  if n > 1 then return M.down(n - 1) end
  return x
end
function M.pause()
  M.work()
  coroutine.yield()
  M.work()
end
M.work_in_pause = M.work
return M
"""

# Each script prints, for the test, the CPU it measured itself.
SCRIPTS = {
    "fail.lua": """package.path = "./lua/?.lua;" .. package.path
local B = require("burn")
local c = os.clock()
B.work()
local ok, err = pcall(B.work, "string")
assert(not ok)
io.write("message=", err, "\\n")
local ok2, err2 = pcall(B.work, "table")
io.write("same_table=", tostring(not ok2 and rawequal(err2, B.err)), "\\n")
local a, b, c3 = B.work()
io.write("returns=", tostring(a ~= nil and b == nil and c3 == "third"), "\\n")
for _ = 1, 3 do B.work() end
io.write("cpu=", os.clock() - c, "\\n")
""",
    "recurse.lua": """package.path = "./lua/?.lua;" .. package.path
local B = require("burn")
local c = os.clock()
B.down(5)
io.write("cpu=", os.clock() - c, "\\n")
""",
    "co.lua": """package.path = "./lua/?.lua;" .. package.path
local B = require("burn")
local co = coroutine.create(function() B.pause() end)
assert(coroutine.resume(co))
-- B.pause lies suspended in co; the calls here are timed on their own.
local c = os.clock()
for _ = 1, 3 do B.work() end
io.write("cpu=", os.clock() - c, "\\n")
assert(coroutine.resume(co))
""",
    "co_only.lua": """local function spin_in_coroutine()
  local x = 0
  for i = 1, 3000000 do x = x + i % 3 end
  return x
end
local co = coroutine.wrap(spin_in_coroutine)
co()
""",
    "dies.lua": """error("the script fails")
""",
    "exits.lua": """os.exit(3)
""",
    "marker.lua": """local f = io.open("ran", "w"); f:write("ran"); f:close()
""",
}


def profile(cwd, *args):
    out = os.path.join(cwd, "report.txt")
    if os.path.exists(out):
        os.remove(out)
    p = subprocess.run(["texlua", PROFILE, "--out", out, *args], cwd=cwd, capture_output=True, text=True, check=False)
    report = ""
    if os.path.exists(out):
        with open(out) as f:
            report = f.read()
    return p, report


def measured(stdout):
    for line in stdout.splitlines():
        if line.startswith("cpu="):
            return float(line[4:])
    return None


def test_profile(d):
    write(os.path.join(d, "lua", "burn.lua"), BURN)
    for name, text in SCRIPTS.items():
        write(os.path.join(d, name), text)

    # The finding: an error caught by pcall, then calls that succeed.
    p, rep = profile(d, "--no-sample", "--time", "burn.work", "fail.lua")
    t = timed(rep, "burn.work")
    check(p.returncode == 0 and t is not None, f"profile fail.lua: rc {p.returncode}, report {rep!r}")
    if t:
        secs, calls, raised = t
        own = measured(p.stdout)
        check(calls == 7, f"burn.work: {calls} calls counted, not 7")
        check(raised == 2, f"burn.work: {raised} calls said to raise, not 2")
        # The calls' own measure includes a little of the script's; the
        # timed seconds must hold nearly all of it, failed calls included.
        check(own and secs >= 0.8 * own, f"burn.work: {secs:.3f} s timed of {own} s spent (calls after an error lost?)")
    check("message=./lua/burn.lua:5: planned failure" in p.stdout, f"the error message changed: {p.stdout!r}")
    check("same_table=true" in p.stdout, "a table raised is not the same table when caught")
    check("returns=true" in p.stdout, "the timed function's returns changed (a nil in the middle?)")

    p, rep = profile(d, "--no-sample", "--time", "burn.down", "recurse.lua")
    t = timed(rep, "burn.down")
    own = measured(p.stdout)
    check(t is not None and t[1] == 5, f"recursion: calls {t and t[1]}, not 5")
    check(t is not None and own is not None and 0.8 * own <= t[0] <= 1.5 * own + 0.01, f"recursion: {t and t[0]} s timed of {own} s (counted more than once?)")

    p, rep = profile(d, "--no-sample", "--time", "burn.work", "co.lua")
    t = timed(rep, "burn.work")
    own = measured(p.stdout)
    check(p.returncode == 0, f"coroutine: rc {p.returncode}: {p.stderr}")
    check(t is not None and t[1] == 5, f"coroutine: calls {t and t[1]}, not 5")
    check(t is not None and own is not None and t[0] >= 0.8 * own, f"coroutine: {t and t[0]} s timed; the three calls in the main thread alone took {own} s")

    p, rep = profile(d, "--period", "1000", "co_only.lua")
    # The coroutine's function is line 1's; its loop is line 3.
    check("co_only.lua:3" in rep, "code run only in a coroutine was not sampled")

    p, rep = profile(d, "dies.lua")
    check(p.returncode == 1, f"a script that fails: rc {p.returncode}, not 1")
    check(rep.splitlines()[:1] and "stopped by an error" in rep.splitlines()[0], f"a script that fails: the report does not say so: {rep[:200]!r}")

    p, rep = profile(d, "exits.lua")
    check(p.returncode == 3, f"os.exit(3): rc {p.returncode}")
    check(rep.splitlines()[:1] and "ended by os.exit(3)" in rep.splitlines()[0], f"os.exit(3): the report does not say so: {rep[:200]!r}")

    for args, what in ((["--time", "burn.nothing"], "a function that does not exist"),
                       (["--time", "nomodule.fn"], "a module that does not exist"),
                       (["--period", "0"], "--period 0"),
                       (["--top", "x"], "--top x")):
        if os.path.exists(os.path.join(d, "ran")):
            os.remove(os.path.join(d, "ran"))
        p, _ = profile(d, *args, "marker.lua")
        check(p.returncode == 2 and not os.path.exists(os.path.join(d, "ran")), f"{what}: rc {p.returncode}, the script ran: {os.path.exists(os.path.join(d, 'ran'))}")
    p = subprocess.run(["texlua", PROFILE, "--out", os.path.join(d, "no", "such", "dir", "r.txt"), "marker.lua"], cwd=d, capture_output=True, text=True, check=False)
    check(p.returncode == 2 and not os.path.exists(os.path.join(d, "ran")), f"--out that cannot be written: rc {p.returncode}")


FAKE_TESTS = {
    "ok": 'print("ok: ok")\n',
    "fail": 'print("fail: failing on purpose"); os.exit(3)\n',
    "killed": 'os.execute("kill -KILL $PPID")\n',
    "slow": 'local f = io.open("slow-started", "w"); f:close(); os.execute("sleep 37.25")\n',
    "marker": 'local f = io.open("marker-ran", "w"); f:close()\n',
}


def test_runner(d):
    os.makedirs(os.path.join(d, "tools"))
    shutil.copy(os.path.join(TOOLS, "test.sh"), os.path.join(d, "tools", "test.sh"))
    for name, text in FAKE_TESTS.items():
        write(os.path.join(d, "tests", f"test_{name}.lua"), text)
    sh = os.path.join(d, "tools", "test.sh")
    shell = os.environ.get("TEST_SH_SHELL")
    run_sh = [shell, sh] if shell else [sh]

    p = subprocess.run([*run_sh, "-j", "3", "--times", "t.tsv", "ok", "fail", "killed"], cwd=d, capture_output=True, text=True, check=False)
    check(p.returncode == 1 and "failed: fail killed" in p.stderr, f"failing tests: rc {p.returncode}, {p.stderr[-200:]!r}")
    rows = {}
    if os.path.exists(os.path.join(d, "t.tsv")):
        with open(os.path.join(d, "t.tsv")) as f:
            lines = f.read().splitlines()
        for line in lines[1:]:
            if not line.startswith("#"):
                parts = line.split("\t")
                rows[parts[0]] = parts[1]
    check(rows == {"ok": "0", "fail": "3", "killed": str(128 + signal.SIGKILL)}, f"statuses in the times file: {rows}")

    for args, what in ((["--times", os.path.join(d, "no", "dir", "t.tsv"), "marker"], "a --times file that cannot be written"),
                       (["-j", "x", "marker"], "-j x"),
                       (["-j", "0", "marker"], "-j 0"),
                       (["-j"], "-j with no number"),
                       (["--times"], "--times with no file"),
                       (["-j", "2", "marker", "marker"], "a test named twice")):
        if os.path.exists(os.path.join(d, "marker-ran")):
            os.remove(os.path.join(d, "marker-ran"))
        p = subprocess.run([*run_sh, *args], cwd=d, capture_output=True, text=True, check=False)
        check(p.returncode == 2 and not os.path.exists(os.path.join(d, "marker-ran")), f"{what}: rc {p.returncode}, a test ran: {os.path.exists(os.path.join(d, 'marker-ran'))}")

    # Interrupted: every test it started stops, and no times are written.
    for sig, rc in ((signal.SIGINT, 130), (signal.SIGTERM, 143)):
        for f in ("i.tsv", "slow-started"):
            if os.path.exists(os.path.join(d, f)):
                os.remove(os.path.join(d, f))
        p = subprocess.Popen([*run_sh, "-j", "2", "--times", "i.tsv", "ok", "slow"], cwd=d, start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        for _ in range(100):
            if os.path.exists(os.path.join(d, "slow-started")):
                break
            time.sleep(0.05)
        os.kill(p.pid, sig)
        try:
            got = p.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            got = None
        time.sleep(0.2)
        left = subprocess.run(["pgrep", "-f", "sleep 37.25"], capture_output=True, text=True, check=False).stdout.split()
        check(got == rc, f"{sig.name}: rc {got}, not {rc}")
        check(not left, f"{sig.name}: tests left running: {left}")
        for pid in left:
            os.kill(int(pid), signal.SIGKILL)
        leftovers = [f for f in os.listdir(d) if f.startswith("i.tsv")]
        check(not leftovers, f"{sig.name}: times written after an interrupt: {leftovers}")


TIMES = "test\tstatus\twall\tuser\tsys\tcpu\n"


def test_times_files(d):
    tt = os.path.join(TOOLS, "test_times.py")

    def run(*args):
        return subprocess.run([sys.executable, "-I", tt, *args], cwd=d, capture_output=True, text=True, check=False)

    files = {
        "empty.tsv": "",
        "headless.tsv": "a\t0\t1.0\t1.0\t0.0\t1.0\n# jobs=1\n",
        "half.tsv": TIMES + "a\t0\t1.0\t1.0\t0.0\t1.0\nb\t0\t2.0",
        "garbled.tsv": TIMES + "a\t0\t1.0\tx\t0.0\t1.0\n# jobs=1\n",
        "short.tsv": TIMES + "a\t0\t1.0\n# jobs=1\n",
    }
    for name, text in files.items():
        write(os.path.join(d, name), text)
        p = run("show", name)
        check(p.returncode == 2 and "test_times:" in p.stderr, f"{name}: rc {p.returncode}, {p.stdout[:120]!r}")

    write(os.path.join(d, "old.tsv"), TIMES + "a\t0\t10\t10\t0\t10\nb\t0\t5\t5\t0\t5\nc\t0\t4\t4\t0\t4\n# jobs=1\n")
    write(os.path.join(d, "new.tsv"), TIMES + "a\t0\t5\t5\t0\t5\nb\t1\t1\t1\t0\t1\nd\t0\t9\t9\t0\t9\nk\t137\tNA\tNA\tNA\tNA\n# jobs=1\n")
    p = run("compare", "old.tsv", "new.tsv")
    total = [line for line in p.stdout.splitlines() if line.startswith("total")]
    check(p.returncode == 0 and total and total[0].split()[1:3] == ["10.0", "5.0"], f"compare totals other than the tests both timed and passed: {total}")
    check("only in new" in p.stdout and "only in old" in p.stdout and "FAIL" in p.stdout, f"compare does not name what it left out: {p.stdout!r}")
    p = run("show", "new.tsv")
    total = [line for line in p.stdout.splitlines() if line.startswith("total")]
    check(p.returncode == 0 and total and total[0].split()[1] == "14.0", f"show totals a failed or untimed test: {total}")


# A path in quotes, as the tests and the runner write the files they read.
PATH_RE = re.compile(r"""["']((?:\./)?[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+)["']""")


def read_paths():
    """The repository's files named in the tests and tools/test.sh."""
    found = set()
    sources = glob.glob(os.path.join(ROOT, "tests", "*.lua")) + glob.glob(os.path.join(ROOT, "tests", "*.py"))
    for src in [*sources, os.path.join(ROOT, "tools", "test.sh")]:
        with open(src) as f:
            text = f.read()
        for m in PATH_RE.finditer(text):
            rel = os.path.normpath(m.group(1))
            if os.path.isfile(os.path.join(ROOT, rel)):
                found.add(rel)
    return found


def test_linux_input():
    """Every file the tests name is among those tools/test-linux.sh sends
    the container (LINUX_SENT_LIST, a file of paths one a line, checks
    another list instead)."""
    given = os.environ.get("LINUX_SENT_LIST")
    if not given and os.environ.get("FLORA_IN_LINUX_CONTAINER"):
        # The container's tree is the list sent, without git to list it.
        print("tools: the container's input is checked where it is sent, not inside it")
        return
    if given:
        with open(given) as f:
            sent_text = f.read()
    else:
        p = subprocess.run([os.path.join(TOOLS, "test-linux.sh"), "--list"], cwd=ROOT, capture_output=True, text=True, check=False)
        check(p.returncode == 0, f"test-linux.sh --list: rc {p.returncode}: {p.stderr.strip()}")
        sent_text = p.stdout
    sent = {os.path.normpath(x) for x in sent_text.splitlines() if x}
    names = read_paths()
    check(len(names) > 10, f"found only {len(names)} files named in the tests (the scan is broken?)")
    missing = sorted(names - sent)
    check(not missing, f"files the tests read that the Linux container does not get: {missing}")


def main():
    with tempfile.TemporaryDirectory() as d:
        test_profile(os.path.join(d, "profile"))
        test_runner(os.path.join(d, "runner"))
        test_times_files(os.path.join(d, "times"))
    test_linux_input()
    if failures:
        print(f"tools: {len(failures)} failure(s)", file=sys.stderr)
        return 1
    print("tools: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
