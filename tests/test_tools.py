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

TOOLS_TEST_HOLD, set, makes the interrupt checks wait for their runner
instead of stopping it (tests/test_tools_matrix.py interrupts the test
then, and requires that nothing it started is left).

TOOLS_UNDER_TEST, a directory, takes the three tools from there instead
of tools/ (to show this test fails on an earlier version). TEST_SH_SHELL
runs tools/test.sh with that shell (e.g. dash, as /bin/sh is on Ubuntu)
instead of by its #!/bin/sh line.

    python3 -I tests/test_tools.py
"""

import ast
import glob
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import toolproc

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
    p = toolproc.run(["texlua", PROFILE, "--out", out, *args], cwd=cwd, capture_output=True, text=True, check=False)
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
    p = toolproc.run(["texlua", PROFILE, "--out", os.path.join(d, "no", "such", "dir", "r.txt"), "marker.lua"], cwd=d, capture_output=True, text=True, check=False)
    check(p.returncode == 2 and not os.path.exists(os.path.join(d, "ran")), f"--out that cannot be written: rc {p.returncode}")


FAKE_TESTS = {
    "ok": 'print("ok: ok")\n',
    "fail": 'print("fail: failing on purpose"); os.exit(3)\n',
    "killed": 'os.execute("kill -KILL $PPID")\n',
    # Its sleeper's pid goes to slow-pid, so that a run finds the processes
    # it started and no others (two runs may share the machine).
    "slow": 'os.execute("sleep 37.25 & echo $! > slow-pid; wait")\n',
    "marker": 'local f = io.open("marker-ran", "w"); f:close()\n',
}


def read_pid(path):
    """The pid a file holds once it is whole, else None."""
    try:
        with open(path) as f:
            text = f.read()
    except OSError:
        return None
    return int(text) if text.endswith("\n") and text.strip().isdigit() else None


def alive(pid):
    """Whether the process exists. A zombie does, until its parent reaps
    it; the sleepers' parent is gone, and init reaps them."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def test_runner(d):
    os.makedirs(os.path.join(d, "tools"))
    for name in ("test.sh", "toolproc.py"):
        shutil.copy(os.path.join(TOOLS, name), os.path.join(d, "tools", name))
    for name, text in FAKE_TESTS.items():
        write(os.path.join(d, "tests", f"test_{name}.lua"), text)
    sh = os.path.join(d, "tools", "test.sh")
    shell = os.environ.get("TEST_SH_SHELL")
    run_sh = [shell, sh] if shell else [sh]

    p = toolproc.run([*run_sh, "-j", "3", "--times", "t.tsv", "ok", "fail", "killed"], cwd=d, capture_output=True, text=True, check=False)
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
        p = toolproc.run([*run_sh, *args], cwd=d, capture_output=True, text=True, check=False)
        check(p.returncode == 2 and not os.path.exists(os.path.join(d, "marker-ran")), f"{what}: rc {p.returncode}, a test ran: {os.path.exists(os.path.join(d, 'marker-ran'))}")

    # Interrupted: every test it started stops, and no times are written.
    for sig, rc in ((signal.SIGINT, 130), (signal.SIGTERM, 143)):
        for f in ("i.tsv", "slow-pid"):
            if os.path.exists(os.path.join(d, f)):
                os.remove(os.path.join(d, f))
        with toolproc.popen([*run_sh, "-j", "2", "--times", "i.tsv", "ok", "slow"], cwd=d, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True) as p:
            sleeper = None
            for _ in range(100):
                sleeper = read_pid(os.path.join(d, "slow-pid"))
                if sleeper:
                    break
                time.sleep(0.05)
            check(sleeper is not None, f"{sig.name}: the slow test did not start")
            if os.environ.get("TOOLS_TEST_HOLD"):
                # For tests/test_tools_matrix.py, which interrupts this
                # test while its runner is up: not stopped here, only
                # waited for.
                try:
                    p.wait(timeout=120)
                except subprocess.TimeoutExpired:
                    pass
            os.kill(p.pid, sig)
            try:
                got = p.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid, signal.SIGKILL)
                got = None
            # Only the process this run started: its recorded pid, never a
            # search by name.
            for _ in range(40):
                if sleeper is None or not alive(sleeper):
                    break
                time.sleep(0.05)
            left = [sleeper] if sleeper is not None and alive(sleeper) else []
            check(got == rc, f"{sig.name}: rc {got}, not {rc}")
            check(not left, f"{sig.name}: tests left running: {left}")
            for pid in left:
                os.kill(pid, signal.SIGKILL)
        leftovers = [f for f in os.listdir(d) if f.startswith("i.tsv")]
        check(not leftovers, f"{sig.name}: times written after an interrupt: {leftovers}")


TIMES = "test\tstatus\twall\tuser\tsys\tcpu\n"


def test_times_files(d):
    tt = os.path.join(TOOLS, "test_times.py")

    def run(*args):
        return toolproc.run([sys.executable, "-I", tt, *args], cwd=d, capture_output=True, text=True, check=False)

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
        p = toolproc.run([os.path.join(TOOLS, "test-linux.sh"), "--list"], cwd=ROOT, capture_output=True, text=True, check=False)
        check(p.returncode == 0, f"test-linux.sh --list: rc {p.returncode}: {p.stderr.strip()}")
        sent_text = p.stdout
    sent = {os.path.normpath(x) for x in sent_text.splitlines() if x}
    names = read_paths()
    check(len(names) > 10, f"found only {len(names)} files named in the tests (the scan is broken?)")
    missing = sorted(names - sent)
    check(not missing, f"files the tests read that the Linux container does not get: {missing}")


def test_concurrent_runs():
    """Two runs of the runner's tests at once on one machine, with an
    unrelated sleep 37.25 of the same command line as the tests' own
    running beside them: both pass and the unrelated process is left
    alone (a run that looked for leftovers by command line found it and
    the other run's sleepers, and killed them)."""
    me = [sys.executable, "-I", os.path.abspath(__file__)]
    env = {**os.environ, "TOOLS_TEST_PART": "runner"}
    with toolproc.popen(["sleep", "37.25"]) as bystander:
        try:
            runs = [toolproc.popen(me, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) for _ in range(2)]
            for i, run in enumerate(runs):
                with run:
                    try:
                        out, _ = run.communicate(timeout=300)
                    except subprocess.TimeoutExpired:
                        run.kill()
                        out, _ = run.communicate()
                    check(run.returncode == 0, f"concurrent run {i + 1}: rc {run.returncode}: {out.strip()[-300:]!r}")
            check(bystander.poll() is None, "a concurrent run killed an unrelated process")
        finally:
            bystander.kill()


# What may start a process or a group of its own: only tools/toolproc.py.
LOOSE_CALLS = {"run", "Popen", "call", "check_call", "check_output", "getoutput", "getstatusoutput"}
LOOSE_OS = {"fork", "forkpty", "system", "popen", "setpgid", "setsid", "spawnv", "spawnvp", "posix_spawn", "execv", "execvp"}
LOOSE_KEYWORDS = {"start_new_session", "preexec_fn", "process_group"}
# The python programs of the tools and their tests that run others (the
# older tools, tools/bake_tune.py and the tuner among them, are not the
# measuring tools').
LOOSE_CHECKED = [os.path.join("tests", n) for n in ("test_tools.py", "test_tools_matrix.py", "test_lint.py", "test_progression_raster.py")] + [os.path.join("tools", n) for n in ("lint.py", "test_times.py", "edge_measure.py", "form_measure.py")]


def test_no_loose_processes():
    """The tools and their tests start every process through
    tools/toolproc.py, which tracks it and stops it on INT, TERM and HUP:
    none of the python programs in LOOSE_CHECKED calls subprocess or os for
    a process or a group of its own."""
    for name in LOOSE_CHECKED:
        path = os.path.join(ROOT, name)
        with open(path) as f:
            tree = ast.parse(f.read(), path)
        found = []
        for node in ast.walk(tree):
            if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) and (
                (node.value.id == "subprocess" and node.attr in LOOSE_CALLS) or (node.value.id == "os" and node.attr in LOOSE_OS)
            ):
                found.append(f"{node.value.id}.{node.attr} at line {node.lineno}")
            if isinstance(node, ast.keyword) and node.arg in LOOSE_KEYWORDS:
                found.append(f"{node.arg} at line {node.lineno}")
        check(not found, f"{name} starts processes outside tools/toolproc.py: {found}")
    check(os.path.exists(os.path.join(ROOT, "tools", "toolproc.py")), "tools/toolproc.py is missing")


def glob_regex(pattern):
    """A path glob as a regex: ** crosses directories, * does not."""
    return re.compile("".join(".*" if part == "**" else "[^/]*" if part == "*" else re.escape(part) for part in re.split(r"(\*\*|\*)", pattern)) + "$")


def test_ci_paths():
    """The test workflow runs when a file its tests use changes: every
    file the tests and tools/test.sh name, and the ones the table of calls
    reads, matches its paths."""
    with open(os.path.join(ROOT, ".github", "workflows", "test.yml")) as f:
        text = f.read()
    block = text.split("    paths:\n", 1)[1].split("  workflow_dispatch:", 1)[0]
    globs = [m.group(1) for m in re.finditer(r'^\s*-\s*"([^"]+)"', block, re.MULTILINE)]
    check(len(globs) >= 5, f"found only {globs} in the workflow's paths (the scan is broken?)")
    regexes = [glob_regex(g) for g in globs]
    used = read_paths() | {"justfile", "docs/testing.md", "tools/toolproc.py", "tools/test-linux.Dockerfile", ".github/workflows/test.yml"}
    for rel in sorted(used):
        check(any(r.match(rel) for r in regexes), f"{rel} is used by the tests and is not in the test workflow's paths")


def test_toolproc():
    """What toolproc promises when a signal or a timeout comes at a bad
    moment."""
    here = f"import sys; sys.path.insert(0, {TOOLS!r}); import toolproc; toolproc.install()\n"
    with tempfile.TemporaryDirectory() as d:
        # A signal while the thread holds the lock the handler takes.
        held = here + "import os, signal\nwith toolproc._lock:\n    os.kill(os.getpid(), signal.SIGTERM)\n    print('not reached')\n"
        try:
            p = toolproc.run([sys.executable, "-I", "-c", held], timeout=20, capture_output=True, text=True)
            check(p.returncode == 143, f"a signal while the lock is held: rc {p.returncode}, not 143")
        except subprocess.TimeoutExpired:
            check(False, "a signal while the lock is held hangs the handler")
        # A child that was not tracked (started a moment before, or not here).
        loose = here + "import subprocess, time\nc = subprocess.Popen(['sleep', '37.25'], start_new_session=True)\nprint(c.pid, flush=True)\ntime.sleep(60)\n"
        with toolproc.popen([sys.executable, "-I", "-c", loose], stdout=subprocess.PIPE, text=True) as q:
            assert q.stdout is not None
            pid = int(q.stdout.readline())
            os.kill(q.pid, signal.SIGTERM)
            got = q.wait(timeout=20)
            for _ in range(50):
                if not alive(pid):
                    break
                time.sleep(0.1)
            check(got == 143, f"a child that was not tracked: rc {got}, not 143")
            check(not alive(pid), "a child that was not tracked is left running when the signal comes")
            if alive(pid):
                os.kill(pid, signal.SIGKILL)
        # Without ps (a PATH that lacks it; and the listing failing as well):
        # a normal end and a signal still stop what is tracked, with no
        # traceback.
        for listing in ("a PATH without ps", "no listing at all"):
            for how, want in (("exit", 0), ("term", 143)):
                prog = here + "import os, signal, time\nc = toolproc.popen(['sleep', '37.25'])\nprint(c.pid, flush=True)\nos.environ['PATH'] = '/nonexistent'\n"
                if listing == "no listing at all":
                    prog += "toolproc.PS = '/nonexistent/ps'\n"
                if how == "term":
                    prog += "os.kill(os.getpid(), signal.SIGTERM)\ntime.sleep(5)\n"
                p = toolproc.run([sys.executable, "-I", "-c", prog], timeout=40, capture_output=True, text=True)
                child = int(p.stdout.split()[0]) if p.stdout.split() else None
                for _ in range(30):
                    if child is None or not alive(child):
                        break
                    time.sleep(0.1)
                label = f"{how} with {listing}"
                check(p.returncode == want, f"{label}: rc {p.returncode}, not {want}")
                check("Traceback" not in p.stderr, f"{label}: a traceback: {p.stderr[-200:]!r}")
                check(child is not None and not alive(child), f"{label}: the tracked child is left running")
                if child is not None and alive(child):
                    os.kill(child, signal.SIGKILL)
        # A command that outlives its timeout while a process of its own, in
        # another group, lives and holds the pipes: stopped as a signal
        # stops it, and the call returns.
        pidfile = os.path.join(d, "sleeper")
        super_ = here + f"import toolproc\nc = toolproc.popen(['sleep', '37.25'])\nopen({pidfile!r}, 'w').write(str(c.pid))\nc.wait()\n"
        start = time.monotonic()
        try:
            toolproc.run([sys.executable, "-I", "-c", super_], timeout=2, capture_output=True)
            check(False, "a command over its time did not raise")
        except subprocess.TimeoutExpired:
            pass
        check(time.monotonic() - start < 12, f"a command over its time took {time.monotonic() - start:.1f} s to be stopped")
        sleeper = int(read_text(pidfile)) if os.path.exists(pidfile) else None
        for _ in range(30):
            if sleeper is None or not alive(sleeper):
                break
            time.sleep(0.1)
        check(sleeper is not None and not alive(sleeper), "a command over its time left its own process running")
        if sleeper is not None and alive(sleeper):
            os.kill(sleeper, signal.SIGKILL)


def test_run_all():
    """toolproc.run_all: commands at once, all waited for; when one fails
    the others are stopped like a signal stops them, at once or after the
    grace; an interrupt stops them all."""
    here = f"import sys; sys.path.insert(0, {TOOLS!r}); import toolproc; toolproc.install()\n"

    def run(commands, grace=None):
        prog = here + f"print(toolproc.run_all({commands!r}, grace={grace!r}))\n"
        started = time.monotonic()
        p = toolproc.run([sys.executable, "-I", "-c", prog], timeout=60, capture_output=True, text=True)
        return p, time.monotonic() - started

    def pids_of(*files):
        out = []
        for f in files:
            if os.path.exists(f) and read_text(f).strip().isdigit():
                out.append(int(read_text(f)))
        return out

    def gone(pids):
        for _ in range(30):
            if not any(alive(p) for p in pids):
                return True
            time.sleep(0.1)
        return False

    with tempfile.TemporaryDirectory() as d:
        quick = (["sh", "-c", "exit 0"], {})
        p, took = run([quick, (["sh", "-c", "sleep 0.3"], {})])
        check(p.stdout.strip() == "[(0, 'ok'), (0, 'ok')]", f"run_all, all succeed: {p.stdout.strip()!r} {p.stderr[-200:]!r}")
        # One fails at once, the other would run for half a minute.
        a = os.path.join(d, "a")
        # (the failing command second: the first one still running must not hide it)
        p, took = run([(["sh", "-c", f"echo $$ > {a}; exec sleep 30"], {}), (["sh", "-c", "exit 3"], {})])
        codes = p.stdout.strip()
        check(codes == "[(-15, 'stopped'), (3, 'failed')]", f"run_all, one fails: the one that failed is 'failed', the other 'stopped': {codes!r}")
        check(took < 8, f"run_all, one fails: took {took:.1f} s, the other was stopped only when its own time was up")
        check(gone(pids_of(a)), "run_all, one fails: the other is left running")
        # Both fail at the same moment: both are 'failed', neither stopped.
        p, took = run([(["sh", "-c", "exit 3"], {}), (["sh", "-c", "exit 4"], {})])
        check(p.stdout.strip() == "[(3, 'failed'), (4, 'failed')]", f"run_all, both fail: {p.stdout.strip()!r}")
        # One fails while the other ignores TERM: stopped after the grace.
        b = os.path.join(d, "b")
        # (it fails only once the other has set its trap and said so)
        p, took = run([(["sh", "-c", f"while [ ! -s {b} ]; do sleep 0.05; done; exit 3"], {}), (["sh", "-c", f"trap '' TERM; echo $$ > {b}; sleep 30"], {})], grace=2)
        check(p.stdout.strip().startswith("[(3, 'failed'), (-9, 'stopped')]"), f"run_all, one ignores TERM: failed and stopped (by KILL): {p.stdout.strip()!r}")
        check(2 <= took < 12, f"run_all, one ignores TERM: took {took:.1f} s, not the grace of 2 s")
        check(gone(pids_of(b)), "run_all, one ignores TERM: it is left running after the grace")
        # An interrupt while they run stops them all.
        c, e = os.path.join(d, "c"), os.path.join(d, "e")
        prog = here + f"toolproc.run_all([(['sh', '-c', 'echo $$ > {c}; exec sleep 30'], {{}}), (['sh', '-c', 'echo $$ > {e}; exec sleep 30'], {{}})])\n"
        with toolproc.popen([sys.executable, "-I", "-c", prog]) as q:
            for _ in range(100):
                if len(pids_of(c, e)) == 2:
                    break
                time.sleep(0.05)
            os.kill(q.pid, signal.SIGTERM)
            got = q.wait(timeout=30)
        check(got == 143, f"run_all, interrupted: rc {got}, not 143")
        check(gone(pids_of(c, e)), "run_all, interrupted: a command is left running")


def read_text(path):
    with open(path) as f:
        return f.read()


def main():
    toolproc.install()
    part = os.environ.get("TOOLS_TEST_PART")
    with tempfile.TemporaryDirectory() as d:
        if part != "runner":
            test_profile(os.path.join(d, "profile"))
        test_runner(os.path.join(d, "runner"))
        if part != "runner":
            test_times_files(os.path.join(d, "times"))
    if part != "runner":
        test_linux_input()
        test_no_loose_processes()
        test_ci_paths()
        test_toolproc()
        test_run_all()
        test_concurrent_runs()
    if failures:
        print(f"tools: {len(failures)} failure(s)", file=sys.stderr)
        return 1
    print("tools: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
