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
LOOSE_CHECKED = [os.path.join("tests", n) for n in ("test_tools.py", "test_tools_matrix.py", "test_lint.py", "test_progression_raster.py")] + [os.path.join("tools", n) for n in ("lint.py", "test_times.py", "edge_measure.py", "form_measure.py", "frame_flora.py")]


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


# Files under tests/ that are not tests of their own, and the one reason
# each is not run by the test workflow. A test file (test_*.lua, test_*.py)
# is never listed here: it is run, or the check fails.
CI_EXEMPT = {
    "tests/helper.lua": "shared setup the Lua tests load",
    "tests/split.lua": "the plan by which a heavy test is split over files, loaded by those files",
    "tests/parity.lua": "run by just test-lua54 against a second Lua, which CI does not install",
    "tests/letters_check.lua": "run inside the TeX documents of just test-tex",
    "tests/measure_check.lua": "run inside the TeX documents of just test-tex",
    "tests/support-seed3.lua": "a spec test_support.lua reads",
}
CI_EXEMPT_PREFIXES = {
    "tests/pattern_": "a sweep or its suite that the test files named after it load",
    "tests/perimeter_flora": "the flora band's sweep and its suite, which the test files named after it load",
    "tests/fixtures/": "data the tests read",
    "tests/slides/": "data the tests read",
}
# The TeX documents of just test-tex (a full TeX Live; CI has texlive-binaries).
CI_EXEMPT_SUFFIXES = {".tex": "compiled by just test-tex, which needs a full TeX installation"}


def ci_code(text):
    """The workflow without its comments: whole comment lines and what
    follows a # after blanks (a # in a quoted string is cut too, which no
    line of this workflow has; a commented-out command in a run: block does
    not run, so it goes with the rest)."""
    lines = [re.sub(r"\s+#.*$", "", line) for line in text.splitlines() if not line.lstrip().startswith("#")]
    return "\n".join(lines) + "\n"


OFF = re.compile(r"^\s*(?:-\s+)?if:\s*(?:false|\"false\"|'false'|\$\{\{\s*false\s*\}\})\s*$", re.MULTILINE)


def ci_jobs(code):
    """{job: lines} of the workflow's jobs, those switched off (if: false at
    the job) left out."""
    m = re.search(r"^jobs:\n", code, re.MULTILINE)
    jobs, cur = {}, None
    for line in code[m.end():].splitlines() if m else []:
        head = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if head:
            cur = head.group(1)
            jobs[cur] = []
        elif cur is not None:
            jobs[cur].append(line)
    out = {}
    for name, lines in jobs.items():
        before_steps = []
        for line in lines:
            if re.match(r"^    steps:\s*$", line):
                break
            before_steps.append(line)
        if not OFF.search("\n".join(before_steps)):
            out[name] = lines
    return out


def ci_run_text(step):
    """The shell of a step's run: key, inline or as a block."""
    for i, line in enumerate(step):
        m = re.match(r"^(\s+)(?:-\s+)?run:\s*(.*)$", line)
        if not m:
            continue
        if m.group(2) not in ("|", ">", "|-", ">-"):
            return m.group(2)
        body = []
        for later in step[i + 1:]:
            if later.strip() and len(later) - len(later.lstrip()) <= len(m.group(1)):
                break
            body.append(later.strip())
        return "\n".join(body)
    return ""


def ci_matrix_tests(lines):
    """The values of the job's matrix `tests:`, each a group of names."""
    for i, line in enumerate(lines):
        if re.match(r"^\s+tests:\s*$", line):
            groups = []
            for later in lines[i + 1:]:
                m = re.match(r"^\s+-\s+(.+)$", later)
                if not m:
                    break
                groups.append(m.group(1))
            return groups
    return []


def ci_named(text):
    """The test files the workflow runs: in the jobs that are not switched
    off (if: false), in the steps that are not, the names given to
    tools/test.sh (`fast` stands for the pre-push set), the test files named
    by path, and the values of a job's matrix `tests:` when a step of the job
    loops over them and gives each to tools/test.sh (for t in ${{
    matrix.tests }}; do tools/test.sh $t; done). Comments count for nothing.

    Its limits, said here and in docs/testing.md: it reads the text and does
    not run the workflow, so a condition other than a plain `if: false`
    (on an event, a branch, a result) is taken to hold; a command that is
    not tools/test.sh or a test file's path does not count; an `exclude` or
    `include` in a matrix is not read (ci_unrun refuses a workflow that has
    one); and the paths filter that decides whether the workflow runs at all
    is checked by test_ci_paths, not here."""
    with open(os.path.join(ROOT, "tools", "test.sh")) as f:
        fast = re.search(r'^FAST="([^"]*)"', f.read(), re.MULTILINE)
    fast_names = fast.group(1).split() + ["bake"] if fast else []
    named, paths = set(), set()
    for lines in ci_jobs(ci_code(text)).values():
        steps = []
        for line in lines[next((k for k, line in enumerate(lines) if re.match(r"^    steps:\s*$", line)), len(lines)) + 1:]:
            if re.match(r"^      - ", line):
                steps.append([line])
            elif steps:
                steps[-1].append(line)
        groups = ci_matrix_tests(lines)
        for step in steps:
            if OFF.search("\n".join(step)):
                continue
            run = ci_run_text(step)
            for m in re.finditer(r"tools/test\.sh((?:\s+[a-z0-9_]+)+)", run):
                named.update(m.group(1).split())
            paths.update(m.group(0) for m in re.finditer(r"tests/test_[a-z0-9_]+\.(?:py|lua)", run))
            loop = re.search(r"for\s+(\w+)\s+in\s+\$\{\{\s*matrix\.tests\s*\}\}\s*;\s*do\s+(.*?)\s*;\s*done", run, re.DOTALL)
            if loop and re.search(rf"tools/test\.sh\s+\"?\${{?{loop.group(1)}\b", loop.group(2)):
                for group in groups:
                    named.update(group.split())
    if "fast" in named:
        named.discard("fast")
        named.update(fast_names)
    return {f"tests/test_{n}.lua" for n in named} | {f"tests/test_{n}.py" for n in named} | paths


def ci_unrun(text):
    """The files under tests/ that the workflow does not run and that are not
    listed as exempt, each with why it is named."""
    ran = ci_named(text)
    lost = []
    if re.search(r"^\s+(?:exclude|include):", ci_code(text), re.MULTILINE):
        lost.append("the workflow has a matrix include or exclude, which this check does not read")
    for dirpath, dirs, names in os.walk(os.path.join(ROOT, "tests")):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for name in names:
            rel = os.path.relpath(os.path.join(dirpath, name), ROOT)
            if re.match(r"test_[A-Za-z0-9_]+\.(lua|py)$", name):
                if rel not in ran:
                    lost.append(f"{rel} is run by no job of the test workflow")
            elif not (rel in CI_EXEMPT or any(rel.startswith(p) for p in CI_EXEMPT_PREFIXES) or os.path.splitext(rel)[1] in CI_EXEMPT_SUFFIXES):
                lost.append(f"{rel} is neither a test the workflow runs nor in CI_EXEMPT")
    return sorted(lost)


def take_out(name):
    """A mutation: `name` taken out of the first job line that has it (not a
    comment, not a step's name); text and the line's index, or None."""
    def make(text, then=None):
        token = re.compile(rf"(?<![a-z0-9_]){name}(?![a-z0-9_]) ?")
        lines = text.splitlines(keepends=True)
        for i, line in enumerate(lines):
            if not line.lstrip().startswith(("#", "- name:")) and token.search(line):
                lines[i] = token.sub("", line, count=1)
                return then(lines, i) if then else "".join(lines)
        return None
    return make


def take_out_and_say(name, how):
    """Taken out, and written in a comment instead: as a test's path, as
    tools/test.sh's call, or after the group it left."""
    def then(lines, i):
        if how == "after the group":
            lines[i] = lines[i].rstrip("\n") + f" # tools/test.sh {name}\n"
        else:
            lines.insert(0, f"# {'tests/test_' + name + '.lua' if how == 'path' else 'tools/test.sh ' + name}\n")
        return "".join(lines)
    return lambda text: take_out(name)(text, then)


def replace_once(old, new):
    return lambda text: text.replace(old, new, 1) if old in text else None


def switch_off(after, nth=1):
    """`if: false` put on the line after the nth one that starts with
    `after` (a job's runs-on, a step's name)."""
    def make(text):
        lines = text.splitlines(keepends=True)
        seen = 0
        for i, line in enumerate(lines):
            seen += line.strip().startswith(after)
            if line.strip().startswith(after) and seen == nth:
                indent = line[: len(line) - len(line.lstrip())].replace("- ", "  ")
                lines.insert(i + 1, f"{indent}if: false\n")
                return "".join(lines)
        return None
    return make


# What the check must see, each with the name it must then report as run by
# no job: names taken out of a job line (one in a matrix group, one among
# others in a long group, one in a step of its own); a name that is written
# in a comment instead (as a path, as tools/test.sh's call, after its
# group); the loop that runs the matrix's tests taken away; a job and a
# step switched off. A mutation that cannot be made is a failure of its own.
CI_MUTATIONS = (
    ("compose taken out", take_out("compose"), "compose"),
    ("pattern_perimeter_1 taken out", take_out("pattern_perimeter_1"), "pattern_perimeter_1"),
    ("tools_matrix taken out", take_out("tools_matrix"), "tools_matrix"),
    ("compose in a comment as a path", take_out_and_say("compose", "path"), "compose"),
    ("compose in a comment as a call", take_out_and_say("compose", "call"), "compose"),
    ("compose in a comment after its group", take_out_and_say("compose", "after the group"), "compose"),
    ("the loop over the matrix's tests gone", replace_once("for t in ${{ matrix.tests }}; do tools/test.sh $t; done", "echo nothing"), "compose"),
    ("the loop over the matrix's tests not given to tools/test.sh", replace_once("do tools/test.sh $t; done", "do echo $t; done"), "compose"),
    ("the lua job switched off", switch_off("runs-on: ubuntu-latest"), "compose"),
    ("the tools job switched off", switch_off("runs-on: ubuntu-latest", 2), "tools_matrix"),
    ("the step of the tests switched off", switch_off("- name: tests"), "compose"),
)


def ci_mutations(text, mutations=CI_MUTATIONS):
    """What is wrong with the proof that ci_unrun sees each mutation of the
    workflow: one that cannot be made proves nothing and is a problem of its
    own, and so is one that is not seen."""
    problems = []
    for label, make, name in mutations:
        mutated = make(text)
        if mutated is None:
            problems.append(f"{label}: the mutation could not be made on the workflow, so it proves nothing")
        elif not [m for m in ci_unrun(mutated) if name in m]:
            problems.append(f"{label}: not seen, {name} is still taken to be run")
    return problems


def test_ci_runs_every_test():
    """No test file is left out of the test workflow: each test_*.lua and
    test_*.py is named in one of its jobs, and each other file under tests/
    says in CI_EXEMPT why it is not a test of its own. A mutation of the
    workflow (a name taken out of its groups) is seen, and the test fails
    when a mutation cannot be made."""
    with open(os.path.join(ROOT, ".github", "workflows", "test.yml")) as f:
        text = f.read()
    check(not ci_unrun(text), f"tests the test workflow does not run: {ci_unrun(text)}")
    for problem in ci_mutations(text):
        check(False, problem)
    # The form itself: a mutation that cannot be made (a name in no job line,
    # one in a step's name only, a line that is not there) is reported.
    cannot = ci_mutations(text, (("no such name", take_out("nosuchname"), "nosuchname"), ("a step's name", take_out("texlua"), "texlua"),
                                 ("no such loop", replace_once("not in the workflow", "x"), "compose")))
    check(len(cannot) == 3 and all("could not be made" in p for p in cannot), f"a mutation that cannot be made is not reported: {cannot}")
    # And one that is made and not seen: a mutation that changes nothing.
    unseen = ci_mutations(text, (("no change", lambda t: t, "compose"),))
    check(len(unseen) == 1 and "not seen" in unseen[0], f"a mutation that is not seen is not reported: {unseen}")


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
        check(len(pids_of(a)) == 1 and gone(pids_of(a)), "run_all, one fails: the other did not start, or is left running")
        # Both fail at the same moment: both are 'failed', neither stopped.
        p, took = run([(["sh", "-c", "exit 3"], {}), (["sh", "-c", "exit 4"], {})])
        check(p.stdout.strip() == "[(3, 'failed'), (4, 'failed')]", f"run_all, both fail: {p.stdout.strip()!r}")
        # One fails while the other ignores TERM: stopped after the grace.
        b = os.path.join(d, "b")
        # (it fails only once the other has set its trap and said so)
        p, took = run([(["sh", "-c", f"while [ ! -s {b} ]; do sleep 0.05; done; exit 3"], {}), (["sh", "-c", f"trap '' TERM; echo $$ > {b}; sleep 30"], {})], grace=2)
        check(p.stdout.strip().startswith("[(3, 'failed'), (-9, 'stopped')]"), f"run_all, one ignores TERM: failed and stopped (by KILL): {p.stdout.strip()!r}")
        check(2 <= took < 12, f"run_all, one ignores TERM: took {took:.1f} s, not the grace of 2 s")
        check(len(pids_of(b)) == 1 and gone(pids_of(b)), "run_all, one ignores TERM: it did not start, or is left running after the grace")
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
        check(len(pids_of(c, e)) == 2 and gone(pids_of(c, e)), "run_all, interrupted: a command did not start, or is left running")


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
        test_ci_runs_every_test()
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
