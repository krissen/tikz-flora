"""Every call the tools document, run against stand-in tests: a table.

The measuring tools (tools/test.sh, tools/test_times.py, tools/profile.lua,
tools/test-linux.sh and the justfile's recipes that call them) take
arguments in many forms. Each row of CELLS is one call: the tool, its
arguments, the tests it runs against, and what it must do. A call either
works or refuses in words with a status other than 0, before it starts any
test; none gives a traceback, fails without a word, loses a measurement or
ends with status 0 when it went wrong. The rows for tools/test.sh are the
product of the forms of -j, of --times and of the test names (see
test_sh_cells); the others are written out.

The stand-in tests are files in a temporary tree and a texlua of its own
that answers for them (a shell script on PATH), so the table needs neither
TeX nor the engine. profile.lua is run with the real texlua. Rows that need
docker, just or texlua are skipped, with a line saying so, where the
program is missing (TOOLS_MATRIX_DOCKER=0 skips the docker rows). TEST_SH_SHELL runs tools/test.sh with that shell.

A recipe in the justfile that calls one of these tools and has no row, or
a tool in docs/testing.md without one, fails the test: the table and the
documentation cannot drift apart.

    python3 -I tests/test_tools_matrix.py            run every row
    TOOLS_MATRIX_TABLE=1 python3 -I tests/test_tools_matrix.py   and print the table
"""

import concurrent.futures
import itertools
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import toolproc

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
failures = []
SKIPPED = []
KEPT = os.path.join("build", "test-times.tsv")


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("FAIL: " + msg, file=sys.stderr)


def write(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    if mode:
        os.chmod(path, mode)


def read(path):
    with open(path) as f:
        return f.read()


# --- the stand-in tree ---------------------------------------------------

# A texlua that runs the stand-in tests: "ok" by name, "fail" ends with
# status 3, "killed" kills its parent shell, anything else that is no file
# ends as texlua does.
STUB_TEXLUA = """#!/bin/sh
f=$1
[ -f "$f" ] || { echo "texlua: cannot open $f" >&2; exit 1; }
n=${f##*/test_}
n=${n%.lua}
case "$n" in
  fail) echo "fail: failing on purpose"; exit 3 ;;
  slow) trap 'kill $!' TERM INT HUP; sleep 37.25 & wait ;;
  mkdirtimes) mkdir -p "$TIMES_TARGET"; echo "mkdirtimes: ok" ;;
  lockdir) chmod a-w "$LOCK_DIR"; echo "lockdir: ok" ;;
  killed) kill -KILL $PPID; sleep 5 ;;
  *) echo "$n: ok" ;;
esac
"""

BURN = """local M = {}
function M.work() local x = 0; for i = 1, 20000 do x = x + i % 7 end; return x end
return M
"""

SCRIPT = """package.path = "./lua/?.lua;" .. package.path
local B = require("burn")
B.work()
print("script ran", ...)
"""

TIMES = "test\tstatus\twall\tuser\tsys\tcpu\n"
TIMES_OK = TIMES + "a\t0\t3.0\t2.0\t0.5\t2.5\nb\t0\t1.0\t0.5\t0.1\t0.6\n# jobs=2 2026-01-01T00:00:00Z load averages: 1.0\n"
TIMES_NEW = TIMES + "a\t0\t2.0\t1.0\t0.5\t1.5\nb\t0\t1.0\t0.5\t0.1\t0.6\n# jobs=2 2026-01-02T00:00:00Z load averages: 1.0\n"
TIMES_BAD = TIMES + "a\t1\t3.0\t2.0\t0.5\t2.5\nk\t137\tNA\tNA\tNA\tNA\n# jobs=2 2026-01-01T00:00:00Z load averages: 1.0\n"


def fast_names():
    m = re.search(r'^FAST="([^"]*)"', read(os.path.join(TOOLS, "test.sh")), re.MULTILINE)
    return m.group(1).split() if m else []


def build_tree(path, full, inject=False):
    """A tree the tools run in: the tools themselves, the justfile, and the
    stand-in tests (all that pass; with full also fail and killed)."""
    os.makedirs(os.path.join(path, "tools"))
    for f in ("test.sh", "test_times.py", "toolproc.py", "profile.lua", "test-linux.sh", "test-linux.Dockerfile", "bodies-compare.sh"):
        if os.path.exists(os.path.join(TOOLS, f)):
            shutil.copy(os.path.join(TOOLS, f), os.path.join(path, "tools", f))
    shutil.copy(os.path.join(ROOT, "justfile"), os.path.join(path, "justfile"))
    names = {*fast_names(), "ok", "marker"} - {"bake", "lint", "tools", "tools_matrix"}
    if full:
        names |= {"fail", "killed"}
    if inject:
        names |= {"mkdirtimes", "lockdir"}
    for n in sorted(names):
        write(os.path.join(path, "tests", f"test_{n}.lua"), "-- stand-in\n")
    for n in ("bake", "lint", "tools", "tools_matrix"):
        write(os.path.join(path, "tests", f"test_{n}.py"), f'print("{n}: ok")\n')
    write(os.path.join(path, "lua", "burn.lua"), BURN)
    write(os.path.join(path, "script.lua"), SCRIPT)
    write(os.path.join(path, "dies.lua"), 'error("planned")\n')
    write(os.path.join(path, "exits.lua"), "os.exit(3)\n")
    write(os.path.join(path, "ok.tsv"), TIMES_OK)
    write(os.path.join(path, "new.tsv"), TIMES_NEW)
    write(os.path.join(path, "bad.tsv"), TIMES_BAD)
    write(os.path.join(path, "empty.tsv"), "")
    os.makedirs(os.path.join(path, "adir"))


def all_tests(tree_full):
    """What tools/test.sh with no names runs, in the tree."""
    lua = {*fast_names(), "ok", "marker", *(["fail", "killed"] if tree_full else [])} - {"bake", "lint", "tools", "tools_matrix"}
    return sorted(lua) + ["bake", "lint", "tools", "tools_matrix"]


# --- the table -----------------------------------------------------------

# expect: "ok" runs and exits 0; "refuse" says why, exits non-zero, runs
# nothing; "fail" runs, and exits non-zero with what failed shown.
# times: "whole" a times file, complete, is left at {T}; "none" no file.
# ran: the tests that ran (their "NAME: ok" lines, or for fail the status).
CELLS = []


def cell(tool, args, expect, tree="good", times=None, ran=None, note="", docker=False, prep=None, nonroot=False):
    """prep names a fault injected before the call (see PREPS); nonroot
    rows need a user a read-only directory stops."""
    CELLS.append({"tool": tool, "args": args, "expect": expect, "tree": tree, "times": times, "ran": ran, "note": note, "docker": docker, "prep": prep, "nonroot": nonroot})


def test_sh_cells():
    jobs = {"omitted": [], "1": ["-j", "1"], "3": ["-j", "3"], "auto": ["-j", "auto"], "0": ["-j", "0"], "word": ["-j", "x"], "empty": ["-j", ""]}
    times = {"omitted": [], "file": ["--times", "{T}"], "unwritable": ["--times", "{NODIR}/t.tsv"], "empty": ["--times", ""], "directory": ["--times", "{DIR}"]}
    names = {
        "none": ([], all_tests(False)),
        "one": (["core"], ["core"]),
        "two": (["core", "grow"], ["core", "grow"]),
        "fast": (["fast"], sorted({*fast_names(), "bake"})),
        "unknown": (["nosuch"], None),
        "twice": (["core", "core"], None),
        "emptyname": ([""], None),
        "failing": (["fail"], ["fail"]),
        "mixed": (["core", "fail"], ["core", "fail"]),
    }
    for (jn, j), (tn, t), (nn, (n, ran)) in itertools.product(jobs.items(), times.items(), names.items()):
        bad_opt = jn in ("0", "word", "empty") or tn in ("unwritable", "empty", "directory") or ran is None
        tree = "full" if nn in ("failing", "mixed") else "good"
        if bad_opt:
            expect = "refuse"
        elif nn in ("failing", "mixed"):
            expect = "fail"
        else:
            expect = "ok"
        timed = tn == "file" and not bad_opt
        cell("test.sh", [*j, *t, *n], expect, tree, "whole" if timed else "none", ran if not bad_opt else [], f"-j {jn}, times {tn}, tests {nn}")
    # Written out: the rest of the forms.
    cell("test.sh", ["-j3", "core"], "ok", ran=["core"], note="-j attached to its number")
    cell("test.sh", ["-j", "3", "-j", "1", "core"], "ok", ran=["core"], note="-j twice, the last one counts")
    cell("test.sh", ["-j"], "refuse", note="-j with no number")
    cell("test.sh", ["--times"], "refuse", note="--times with no file")
    cell("test.sh", ["--bogus"], "refuse", note="an option that does not exist")
    cell("test.sh", ["-j", "2", "--bogus", "core"], "refuse", note="an unknown option among others")
    cell("test.sh", ["core", "-j", "2"], "refuse", note="an option after the names")
    cell("test.sh", ["fast", "core"], "refuse", note="fast with another name (the other would be dropped)")
    cell("test.sh", ["core", "fast"], "refuse", note="fast is a name only first")
    cell("test.sh", ["--times", "{T}", "-j", "2"], "ok", times="whole", ran=all_tests(False), note="--times and -j, no names")
    cell("test.sh", ["-j", "2", "--times", "{T}"], "fail", tree="full", times="whole", ran=all_tests(True), note="every test, with a failing and a killed one")
    cell("test.sh", ["-j", "2", "killed"], "fail", tree="full", ran=["killed"], note="a test that kills its shell")
    cell("test.sh", ["--times", "{T}", "killed"], "fail", tree="full", times="whole", ran=["killed"], note="a killed test, timed")
    cell("test.sh", ["--times", "{T}", "fail"], "fail", tree="full", times="whole", ran=["fail"], note="a failing test, timed")


def test_times_cells():
    for f in ("ok.tsv", "bad.tsv"):
        cell("test_times", ["show", f], "ok", note=f"show {f}")
        for j in ("1", "4", "auto"):
            cell("test_times", ["show", f, "--jobs", j], "ok", note=f"show {f} --jobs {j}")
        for j in ("0", "-1", "x", "", "2.5"):
            cell("test_times", ["show", f, "--jobs", j], "refuse", note=f"show {f} --jobs {j!r}")
    cell("test_times", ["show", "--jobs", "2", "ok.tsv"], "ok", note="--jobs before the file")
    cell("test_times", ["show", "--jobs"], "refuse", note="--jobs with no number")
    for f, what in (("nosuch.tsv", "a file that does not exist"), ("empty.tsv", "an empty file"), ("adir", "a directory"), ("", "an empty path")):
        cell("test_times", ["show", f], "refuse", note=f"show {what}")
        cell("test_times", ["compare", f, "ok.tsv"], "refuse", note=f"compare {what} first")
        cell("test_times", ["compare", "ok.tsv", f], "refuse", note=f"compare {what} second")
    cell("test_times", ["show"], "refuse", note="show with no file")
    cell("test_times", ["show", "ok.tsv", "new.tsv"], "refuse", note="show with two files")
    cell("test_times", ["compare", "ok.tsv", "new.tsv"], "ok", note="compare two runs")
    cell("test_times", ["compare", "ok.tsv", "ok.tsv"], "ok", note="compare a run with itself")
    cell("test_times", ["compare", "ok.tsv", "bad.tsv"], "ok", note="compare with a run that has failures")
    cell("test_times", ["compare", "bad.tsv", "bad.tsv"], "ok", note="compare two runs with failures")
    cell("test_times", ["compare", "ok.tsv"], "refuse", note="compare with one file")
    cell("test_times", [], "refuse", note="no command")
    cell("test_times", ["bogus"], "refuse", note="a command that does not exist")
    cell("test_times", ["-h"], "ok", note="its help")


def profile_cells():
    cell("profile", [], "refuse", note="no script")
    cell("profile", ["script.lua"], "ok", note="a script")
    cell("profile", ["script.lua", "a", "b"], "ok", note="a script with arguments")
    cell("profile", ["script.lua", "--period", "5"], "ok", note="options after the script belong to it")
    cell("profile", ["-e", "print(1)"], "ok", note="-e with code")
    cell("profile", ["-e"], "refuse", note="-e with no code")
    cell("profile", ["-e", ""], "ok", note="-e with empty code")
    cell("profile", ["-e", "this is not lua"], "refuse", note="-e with code that does not load")
    for opt in ("--period", "--top"):
        cell("profile", [opt, "50000", "script.lua"], "ok", note=f"{opt} a number")
        cell("profile", [opt, "1", "script.lua"], "ok", note=f"{opt} 1")
        for bad in ("0", "x", "-5", "", "1.5"):
            cell("profile", [opt, bad, "script.lua"], "refuse", note=f"{opt} {bad!r}")
        cell("profile", [opt], "refuse", note=f"{opt} with no number")
    cell("profile", ["--out", "{T}", "script.lua"], "ok", note="--out a file", times="whole")
    cell("profile", ["--out", "{NODIR}/r.txt", "script.lua"], "refuse", note="--out in a directory that does not exist")
    cell("profile", ["--out", "{DIR}", "script.lua"], "refuse", note="--out a directory")
    cell("profile", ["--out", "", "script.lua"], "refuse", note="--out an empty path")
    cell("profile", ["--out"], "refuse", note="--out with no file")
    cell("profile", ["--time", "burn.work", "script.lua"], "ok", note="--time a function")
    cell("profile", ["--time", "burn.work,burn.work", "script.lua"], "ok", note="--time a function twice")
    for bad, why in (("burn.nothing", "that does not exist"), ("nomodule.fn", "of a module that does not exist"), ("burn", "with no dot"), ("", "empty"), (",,", "with only commas")):
        cell("profile", ["--time", bad, "script.lua"], "refuse", note=f"--time a function {why}" if bad else "--time an empty list")
    cell("profile", ["--time"], "refuse", note="--time with no list")
    cell("profile", ["--no-sample", "--time", "burn.work", "script.lua"], "ok", note="--no-sample with --time")
    cell("profile", ["--no-sample", "script.lua"], "refuse", note="--no-sample with nothing to time")
    cell("profile", ["--bogus", "script.lua"], "refuse", note="an option that does not exist")
    cell("profile", ["nosuch.lua"], "refuse", note="a script that does not exist")
    cell("profile", ["adir"], "refuse", note="a directory as the script")
    cell("profile", ["dies.lua"], "fail", note="a script that fails")
    cell("profile", ["exits.lua"], "fail", note="a script that calls os.exit(3)")


def just_cells():
    for j in ("", "1", "2", "auto"):
        cell("just", ["test", *([j] if j else [])], "ok", ran=all_tests(False), note=f"just test {j}".strip())
    for j in ("x", "0", ""):
        cell("just", ["test", j], "refuse", note=f"just test {j!r}")
    cell("just", ["test", "1", "extra"], "refuse", note="just test with an argument too many")
    for j in ("", "1", "2", "auto"):
        for names in ([], ["core"], ["core", "grow"]):
            if names and not j:
                continue  # the names come after the jobs
            cell("just", ["test-times", *([j] if j else []), *names], "ok", times="recipe", ran=names or all_tests(False), note=f"just test-times {j} {' '.join(names)}".strip())
    for j in ("x", "0", ""):
        cell("just", ["test-times", j, "core"], "refuse", times="none-recipe", note=f"just test-times {j!r} core")
    cell("just", ["test-times", "2", "nosuch"], "refuse", times="none-recipe", note="just test-times with a test that does not exist")
    cell("just", ["test-times", "2", "core", "core"], "refuse", times="none-recipe", note="just test-times with a test named twice")
    cell("just", ["test-times", "2", "fail"], "fail", tree="full", ran=["fail"], times="recipe-kept", note="just test-times with a failing test keeps the measurement")
    cell("just", ["test-times", "auto", "fail", "core"], "fail", tree="full", ran=["core", "fail"], times="recipe-kept", note="just test-times auto with a failing test")
    cell("just", ["profile"], "refuse", note="just profile with no script")
    cell("just", ["profile", "script.lua"], "ok", note="just profile a script")
    cell("just", ["profile", "--time", "burn.work", "script.lua"], "ok", note="just profile --time")
    cell("just", ["profile", "nosuch.lua"], "refuse", note="just profile a script that does not exist")
    cell("just", ["nosuchrecipe"], "refuse", note="a recipe that does not exist")


def fault_cells():
    """A step after a measurement is made fails: the measurement stays,
    the run names where, and it ends non-zero ("saved"). A step before it
    fails: nothing runs ("refuse")."""
    for prep, what in (("shim-cp", "cp fails"), ("shim-mv", "mv fails")):
        cell("test.sh", ["--times", "{T}", "core"], "fail", times="saved", ran=["core"], prep=prep, note=f"--times, {what} after the run")
        cell("just", ["test-times", "2", "core"], "fail", times="saved", ran=["core"], prep=prep, note=f"just test-times, {what} after the run")
    cell("test.sh", ["--times", "{T}", "mkdirtimes"], "fail", tree="inject", times="saved", ran=["mkdirtimes"], note="--times FILE becomes a directory during the run")
    cell("test.sh", ["--times", "{LOCK}/t.tsv", "lockdir"], "fail", tree="inject", times="saved", ran=["lockdir"], nonroot=True, note="--times FILE's directory becomes read-only during the run")
    cell("test.sh", ["--times", "{T}", "core"], "ok", times="whole", ran=["core"], prep="old-file", note="--times FILE exists: replaced")
    cell("just", ["test-times", "2", "core"], "fail", times="saved", ran=["core"], prep="pointer-dir", note="build/test-times.tsv is a directory: the run's file stays")
    cell("just", ["test-times", "2", "core"], "ok", times="recipe", ran=["core"], prep="pointer-file", note="build/test-times.tsv is an older file: replaced by the link")
    cell("just", ["test-times", "2", "core"], "ok", times="recipe", ran=["core"], prep="pointer-dangling", note="build/test-times.tsv is a dangling link: replaced")
    cell("just", ["test-times", "2", "core"], "refuse", times="none-recipe", prep="runs-file", note="build/test-times is a file: nothing is run")
    cell("just", ["test-times", "2", "core"], "refuse", times="none-recipe", prep="build-readonly", nonroot=True, note="build/ is read-only: nothing is run")
    cell("just", ["test-times", "2", "core"], "refuse", times="none-recipe", prep="runs-readonly", nonroot=True, note="build/test-times is read-only: nothing is run")
    cell("profile", ["--out", "/dev/full", "script.lua"], "fail", prep="needs-dev-full", note="--out a file that takes no data: the report goes to stderr")


def linux_cells():
    cell("test-linux", ["--list"], "ok", tree="real", note="--list in the repository")
    cell("test-linux", ["--list"], "refuse", note="--list outside a git working tree")
    cell("test-linux", ["core"], "refuse", tree="nodocker", note="without docker")
    for args, expect, note in (
        (["core"], "ok", "a test in the container"),
        (["-j", "2", "core", "grow"], "ok", "-j with two tests"),
        (["--times", "/tmp/x.tsv", "core"], "ok", "--times, written inside the container"),
        (["nosuch"], "refuse", "a test that does not exist"),
        (["core", "core"], "refuse", "a test named twice"),
        (["-j", "x", "core"], "refuse", "-j x"),
        (["-j", "0", "core"], "refuse", "-j 0"),
    ):
        cell("test-linux", args, expect, tree="real", note=note, docker=True)
    cell("just", ["test-linux", "core"], "ok", tree="real", note="just test-linux core", docker=True)
    cell("just", ["test-linux", "nosuch"], "refuse", tree="real", note="just test-linux with a test that does not exist", docker=True)


# Rows for tools a branch adds (tools/bodies-compare.sh) are in
# tests/tools_matrix_extra.py when that branch has it.
def extra_cells():
    path = os.path.join(ROOT, "tests", "tools_matrix_extra.py")
    if os.path.exists(path):
        scope = {"cell": cell, "CELLS": CELLS, "all_tests": all_tests}
        exec(compile(read(path), path, "exec"), scope)  # noqa: S102


def build_cells():
    test_sh_cells()
    test_times_cells()
    profile_cells()
    just_cells()
    fault_cells()
    linux_cells()
    extra_cells()


# --- running a row -------------------------------------------------------

class Env:
    pass


def docker_ready():
    if not shutil.which("docker") or os.environ.get("FLORA_IN_LINUX_CONTAINER") or os.environ.get("TOOLS_MATRIX_DOCKER") == "0":
        return False
    p = toolproc.run(["docker", "info"], capture_output=True, check=False)
    return p.returncode == 0


def command_for(c, tree, subst, shell):
    tool, args = c["tool"], [a.format(**subst) if "{" in a else a for a in c["args"]]
    sh = [shell] if shell else []
    if tool == "test.sh":
        return [*sh, os.path.join(tree, "tools", "test.sh"), *args]
    if tool == "test_times":
        return [sys.executable, "-I", os.path.join(tree, "tools", "test_times.py"), *args]
    if tool == "profile":
        return ["texlua", os.path.join(tree, "tools", "profile.lua"), *args]
    if tool == "test-linux":
        return [*sh, os.path.join(tree, "tools", "test-linux.sh"), *args]
    if tool == "bodies-compare":
        return [*sh, os.path.join(tree, "tools", "bodies-compare.sh"), *args]
    if tool == "just":
        return ["just", *args]
    raise ValueError(tool)


def make_shim(work, name):
    """A directory with a failing program of that name, for PATH."""
    shim = os.path.join(work, "shim-" + name)
    write(os.path.join(shim, name), "#!/bin/sh\nexit 1\n", 0o755)
    return shim


def prepare(c, tree, work, env):
    """Inject the row's fault."""
    prep = c.get("prep")
    if not prep:
        return
    build = os.path.join(tree, "build")
    if prep in ("shim-cp", "shim-mv"):
        env["PATH"] = make_shim(work, prep[5:]) + os.pathsep + env["PATH"]
    elif prep == "old-file":
        write(os.path.join(work, "t.tsv"), "older\n")
    elif prep == "pointer-dir":
        os.makedirs(os.path.join(build, "test-times.tsv"))
    elif prep == "pointer-file":
        write(os.path.join(build, "test-times.tsv"), "older\n")
    elif prep == "pointer-dangling":
        os.makedirs(build)
        os.symlink("test-times/gone.tsv", os.path.join(build, "test-times.tsv"))
    elif prep == "runs-file":
        write(os.path.join(build, "test-times"), "in the way\n")
    elif prep == "build-readonly":
        os.makedirs(build)
        os.chmod(build, 0o555)
    elif prep == "runs-readonly":
        os.makedirs(os.path.join(build, "test-times"))
        os.chmod(os.path.join(build, "test-times"), 0o555)


def unlock(*dirs):
    for d in dirs:
        for root, subdirs, _ in os.walk(d):
            for sub in [root, *(os.path.join(root, x) for x in subdirs)]:
                try:
                    os.chmod(sub, 0o755)
                except OSError:
                    pass


def run_cell(c, trees, stub, shell, results_dir, index):
    work = os.path.join(results_dir, str(index))
    os.makedirs(work)
    tree = trees[c["tree"]]
    private = c["tool"] == "just" or c["times"] in ("recipe", "recipe-kept", "none-recipe", "saved")
    if private:
        tree = os.path.join(work, "tree")
        shutil.copytree(trees[c["tree"]], tree, symlinks=True)
    subst = {"T": os.path.join(work, "t.tsv"), "NODIR": os.path.join(work, "no", "such"), "DIR": os.path.join(work, "adir"), "LOCK": os.path.join(work, "lock")}
    os.makedirs(subst["DIR"])
    os.makedirs(subst["LOCK"])
    env = dict(os.environ)
    env["PATH"] = stub + os.pathsep + env["PATH"]
    env["TIMES_TARGET"] = subst["T"]
    env["LOCK_DIR"] = subst["LOCK"]
    prepare(c, tree, work, env)
    env["FLORA_PYTHON"] = sys.executable
    env.pop("FLORA_IN_LINUX_CONTAINER", None) if c["tree"] != "real" else None
    if c["tree"] == "nodocker":
        tool_dir = os.path.join(work, "bin")
        os.makedirs(tool_dir)
        for prog in ("dirname", "sort", "mktemp", "rm", "tar", "git", "cat", "sed", "uname", "grep", "env"):
            p = shutil.which(prog)
            if p:
                os.symlink(p, os.path.join(tool_dir, prog))
        env["PATH"] = tool_dir
        tree = trees["good"]
    cmd = command_for(c, tree, subst, shell)
    if c["tool"] == "just":
        cmd = [cmd[0], "--justfile", os.path.join(tree, "justfile"), "--working-directory", tree, *cmd[1:]]
    cwd = ROOT if c["tree"] == "real" else tree
    timeout = 600 if c.get("docker") else 120
    try:
        p = toolproc.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout, check=False)
        rc, out, err = p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        rc, out, err = -999, "", "timed out"
    result = judge(c, rc, out, err, tree, subst)
    unlock(work)
    return result


def ran_lines(out):
    return sorted(m.group(1) for m in re.finditer(r"^(\w+): ok$", out, re.MULTILINE))


def judge(c, rc, out, err, tree, subst):
    """The problems with the way a call ended; none when it behaved."""
    bad = []
    both = out + err
    expect = c["expect"]
    if rc == -999:
        return ["timed out"], rc
    if rc < 0:
        bad.append(f"ended by signal {-rc}")
    if "Traceback" in both or ("stack traceback" in both and c["tool"] != "profile"):
        bad.append("a traceback")
    if re.search(r"(unbound variable|: not found|command not found|parameter not set|Syntax error)", both):
        bad.append("a shell's own error")
    if expect == "ok" and rc != 0:
        bad.append(f"rc {rc}, not 0: {both.strip()[-200:]!r}")
    if expect in ("refuse", "fail") and rc == 0:
        bad.append("rc 0 for a call that must not succeed")
    if expect == "refuse":
        if not err.strip():
            bad.append("refused without a word on stderr")
        if c["tool"] == "test.sh" and rc not in (2, 1):
            bad.append(f"rc {rc}, not 2")
        if c["ran"] is not None and ran_lines(out):
            bad.append(f"refused after running {ran_lines(out)}")
    if expect == "fail" and not both.strip():
        bad.append("failed without a word")
    ran = c["ran"]
    prints_tests = c["tool"] == "test.sh" or c["args"][:1] == ["test"]
    if expect in ("ok", "fail") and ran is not None and prints_tests:
        shown = ran_lines(out)
        want = sorted(n for n in ran if n not in ("fail", "killed"))
        if shown != want:
            bad.append(f"ran {shown}, not {want}")
    if expect == "fail" and c["tool"] == "test.sh" and ran:
        failing = [n for n in ran if n in ("fail", "killed")]
        joined = " ".join(c["args"])
        parallel = ("-j" in joined and not re.search(r"-j[ =]?1\b", joined)) or c["times"] == "whole"
        if parallel and not re.search(r"test\.sh: failed:.*" + failing[0], err):
            bad.append(f"the failure is not named in {err.strip()[-200:]!r}")
    times = c["times"]
    t = subst["T"]
    if times == "whole":
        problem = times_problem(t, ran if c["tool"] == "test.sh" else None)
        if problem:
            bad.append(problem)
    elif times == "none" and os.path.exists(t):
        bad.append("a times file was written")
    if c["tool"] == "test.sh" or times in ("whole", "none"):
        left = [f for f in os.listdir(os.path.dirname(t)) if ".partial." in f]
        if left:
            bad.append(f"partial files left: {left}")
    if times in ("recipe", "recipe-kept"):
        final = os.path.join(tree, KEPT)
        if not os.path.exists(final):
            bad.append("the measurement is not at build/test-times.tsv")
        else:
            problem = times_problem(final, ran)
            if problem:
                bad.append(problem)
        if times == "recipe-kept" and KEPT not in both:
            bad.append("the path of the kept measurement is not said")
    if times == "none-recipe":
        runs = os.path.join(tree, "build", "test-times")
        made = os.path.lexists(os.path.join(tree, KEPT)) or (os.path.isdir(runs) and any(f.endswith(".tsv") for f in os.listdir(runs)))
        if made:
            bad.append("a measurement was kept for a run that never started")
    if times == "saved":
        bad.extend(saved_problems(rc, both, tree, ran))
    if c.get("prep") == "needs-dev-full" and not ("profile:" in err and "could not write" in err):
        bad.append("the report is not on stderr with the reason")
    if c["tool"] == "profile" and expect == "ok" and c["args"][:1] != ["-e"]:
        rep = read(t) if c["times"] == "whole" and os.path.exists(t) else err
        if "profile:" not in rep:
            bad.append("no report")
    return bad, rc


def saved_problems(rc, text, tree, names):
    """After a failed step the measurement is left, at a path the run
    names, and the run ends non-zero."""
    bad = []
    if rc == 0:
        bad.append("rc 0 though the measurement could not be saved")
    named = [p.rstrip(".;)") for p in re.findall(r"[\w/.+-]+\.tsv", text)]
    left = []
    for p in named:
        full = p if os.path.isabs(p) else os.path.join(tree, p)
        if os.path.isfile(full) and times_problem(full, names) is None:
            left.append(p)
    if not left:
        bad.append(f"no whole measurement at any path the run names ({named})")
    return bad


def times_problem(path, names):
    """What is wrong with a times file (or, for a profile's --out, a
    report), or None; names are the tests it must hold, when known."""
    if not os.path.exists(path):
        return "no times file"
    text = read(path)
    if text.startswith("profile:"):
        return None
    lines = text.splitlines()
    if not text.endswith("\n") or not lines or not lines[-1].startswith("# jobs="):
        return "the times file is not whole"
    got = sorted(ln.split("\t")[0] for ln in lines[1:-1])
    if names is not None and got != sorted(names):
        return f"the times file has {got}, not {sorted(names)}"
    return None


# --- interrupting a run that runs the tools' tests ---------------------------

def descendants(root):
    """(pid, command) of every process below pid root."""
    ps = toolproc.run(["ps", "-A", "-o", "pid=,ppid=,command="], capture_output=True, text=True)
    below = {}
    for line in ps.stdout.splitlines():
        parts = line.split(None, 2)
        if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
            below.setdefault(int(parts[1]), []).append((int(parts[0]), parts[2] if len(parts) > 2 else ""))
    found, todo = [], [root]
    while todo:
        for pid, cmd in below.get(todo.pop(), []):
            found.append((pid, cmd))
            todo.append(pid)
    return found


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def hold():
    """What TOOLS_MATRIX_HOLD asks for: a run with a test that sleeps, held
    until it is stopped, so that a run that is interrupted has something
    to stop (interrupted_run)."""
    with tempfile.TemporaryDirectory() as base:
        stub = os.path.join(base, "stub")
        write(os.path.join(stub, "texlua"), STUB_TEXLUA, 0o755)
        tree = os.path.join(base, "hold")
        build_tree(tree, False)
        write(os.path.join(tree, "tests", "test_slow.lua"), "-- stand-in\n")
        env = {**os.environ, "PATH": stub + os.pathsep + os.environ["PATH"], "FLORA_PYTHON": sys.executable}
        toolproc.run([os.path.join(tree, "tools", "test.sh"), "-j", "2", "slow"], cwd=tree, env=env, timeout=120)


def interrupt_and_check(label, tree, argv, env, sig):
    """Start argv in tree; once a test below it is sleeping send it sig:
    it ends with 128 plus the signal, and of the processes below it then
    not one is left."""
    problems = []
    with open(os.path.join(tree, "out.txt"), "w") as log, toolproc.popen(argv, cwd=tree, env=env, stdout=log, stderr=subprocess.STDOUT) as p:
        below = None
        deadline = time.monotonic() + 120
        while below is None and p.poll() is None and time.monotonic() < deadline:
            seen = descendants(p.pid)
            if any("sleep" in cmd and "37.25" in cmd for _, cmd in seen):
                below = [pid for pid, _ in seen]
            else:
                time.sleep(0.2)
        if below is None:
            problems.append("the run never got to a sleeping test")
            below = [pid for pid, _ in descendants(p.pid)]
        os.kill(p.pid, sig)
        try:
            got = p.wait(timeout=40)
        except subprocess.TimeoutExpired:
            got = None
            os.killpg(p.pid, signal.SIGKILL)
        if got != 128 + sig:
            problems.append(f"rc {got}, not {128 + sig}")
        deadline = time.monotonic() + 10
        left = [pid for pid in below if alive(pid)]
        while left and time.monotonic() < deadline:
            time.sleep(0.2)
            left = [pid for pid in left if alive(pid)]
        if left:
            problems.append(f"processes left running: {left}")
            for pid in left:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
    return [f"interrupt {sig.name} of {label}: {pr}" for pr in problems]


def interrupted_run(base, outer, sig):
    """tools/test.sh -j 2 OUTER, a run of the tools' own tests (which start
    runs of their own), interrupted."""
    tree = os.path.join(base, f"nested-{outer}-{sig.name}")
    os.makedirs(tree)
    for part in ("tools", "tests", "docs"):
        shutil.copytree(os.path.join(ROOT, part), os.path.join(tree, part), symlinks=True)
    shutil.copy(os.path.join(ROOT, "justfile"), tree)
    env = {**os.environ, "TOOLS_MATRIX_HOLD": "1", "TOOLS_TEST_HOLD": "1", "TOOLS_MATRIX_DOCKER": "0", "FLORA_PYTHON": sys.executable}
    return interrupt_and_check(f"test.sh -j 2 {outer}", tree, [os.path.join(tree, "tools", "test.sh"), "-j", "2", outer], env, sig)


def interrupted_slow(base, tool, args, sig):
    """A tool that runs a test that sleeps (the stand-in tree's slow),
    interrupted."""
    stub = os.path.join(base, "stub-" + tool)
    write(os.path.join(stub, "texlua"), STUB_TEXLUA, 0o755)
    tree = os.path.join(base, f"slow-{tool}-{sig.name}")
    build_tree(tree, False)
    write(os.path.join(tree, "tests", "test_slow.lua"), "-- stand-in\n")
    env = {**os.environ, "PATH": stub + os.pathsep + os.environ["PATH"], "FLORA_PYTHON": sys.executable}
    argv = [os.path.join(tree, "tools", "test.sh"), *args] if tool == "test.sh" else [sys.executable, "-I", os.path.join(tree, "tools", "test_times.py"), *args]
    return interrupt_and_check(f"{tool} {' '.join(args)}", tree, argv, env, sig)


def interrupted_container(base, sig):
    """tools/test-linux.sh running a long test in the container is sent sig:
    it ends with 128 plus the signal, and the container is gone."""
    problems = []
    name = None
    with toolproc.popen([os.path.join(ROOT, "tools", "test-linux.sh"), "scene_ops"], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as p:
        name = f"tikz-flora-test-{p.pid}"

        def containers():
            found = toolproc.run(["docker", "ps", "-q", "--filter", f"name={name}"], capture_output=True, text=True)
            return found.stdout.split()

        deadline = time.monotonic() + 120
        while not containers() and p.poll() is None and time.monotonic() < deadline:
            time.sleep(0.5)
        if not containers():
            problems.append("the container never started")
        os.kill(p.pid, sig)
        try:
            got = p.wait(timeout=60)
        except subprocess.TimeoutExpired:
            got = None
            os.killpg(p.pid, signal.SIGKILL)
        if got != 128 + sig:
            problems.append(f"rc {got}, not {128 + sig}")
        deadline = time.monotonic() + 20
        while containers() and time.monotonic() < deadline:
            time.sleep(0.5)
        left = containers()
        if left:
            problems.append(f"the container is still running: {left}")
            toolproc.run(["docker", "kill", name], capture_output=True)
    return [f"interrupt {sig.name} of tools/test-linux.sh: {pr}" for pr in problems]


INTERRUPTS = (("tools", signal.SIGINT), ("tools", signal.SIGTERM), ("tools", signal.SIGHUP), ("tools_matrix", signal.SIGTERM))


# --- the whole table ------------------------------------------------------

def test_recipes_have_rows():
    """Every recipe that calls one of the tools has rows, and the
    documentation names each."""
    just = read(os.path.join(ROOT, "justfile"))
    docs = read(os.path.join(ROOT, "docs", "testing.md"))
    tool_files = ("tools/test.sh", "tools/test_times.py", "tools/profile.lua", "tools/test-linux.sh", "tools/bodies-compare.sh")
    recipes = {}
    current = None
    for line in just.splitlines():
        m = re.match(r"^([a-z][a-z0-9-]*)(?: .*)?:\s*$", line)
        if m:
            current = m.group(1)
            recipes[current] = ""
        elif current and (line.startswith(" ") or not line.strip()):
            recipes[current] += line + "\n"
        else:
            current = None
    used = {name for name, body in recipes.items() if any(t in body for t in tool_files)}
    check(len(used) >= 4, f"found only {sorted(used)} calling the tools (the scan is broken?)")
    covered = {c["args"][0] for c in CELLS if c["tool"] == "just"}
    for name in sorted(used - covered):
        check(False, f"just {name} calls a tool and has no row in the table of calls")
    if os.path.exists(os.path.join(TOOLS, "bodies-compare.sh")):
        check(any(c["tool"] == "bodies-compare" for c in CELLS), "tools/bodies-compare.sh has no row in the table of calls")
    for name in sorted(used):
        check(f"just {name}" in docs, f"docs/testing.md does not mention just {name}")
    for tool, token in (("test.sh", "tools/test.sh"), ("test_times", "test_times.py"), ("profile", "tools/profile.lua"), ("test-linux", "tools/test-linux.sh")):
        check(any(c["tool"] == tool for c in CELLS), f"{token} has no row in the table of calls")
        check(token in docs or token.split("/")[-1] in docs, f"docs/testing.md does not mention {token}")


def main():
    toolproc.install()
    if os.environ.get("TOOLS_MATRIX_HOLD"):
        hold()
        return 0
    build_cells()
    test_recipes_have_rows()
    shell = os.environ.get("TEST_SH_SHELL")
    have = {"texlua": bool(shutil.which("texlua")), "just": bool(shutil.which("just")), "docker": docker_ready()}
    with tempfile.TemporaryDirectory() as base:
        stub = os.path.join(base, "stub")
        write(os.path.join(stub, "texlua"), STUB_TEXLUA, 0o755)
        trees = {"good": os.path.join(base, "good"), "full": os.path.join(base, "full")}
        build_tree(trees["good"], False)
        build_tree(trees["full"], True)
        trees["inject"] = os.path.join(base, "inject")
        build_tree(trees["inject"], False, inject=True)
        trees["real"] = ROOT
        trees["nodocker"] = trees["good"]
        real_texlua = shutil.which("texlua")
        runnable = []
        for i, c in enumerate(CELLS):
            need = None
            if c["tool"] == "profile" and not real_texlua:
                need = "texlua"
            if c["tool"] == "just" and not have["just"]:
                need = "just"
            if c.get("nonroot") and hasattr(os, "geteuid") and os.geteuid() == 0:
                need = "a user other than root"
            if c.get("prep") == "needs-dev-full" and not os.path.exists("/dev/full"):
                need = "/dev/full"
            if c.get("docker") and not have["docker"]:
                need = "docker (running, and not inside the container)"
            if c["tool"] == "test-linux" and c["tree"] == "real" and not shutil.which("git"):
                need = "git"
            if c["tool"] == "test-linux" and c["args"] == ["--list"] and c["expect"] == "ok" and os.environ.get("FLORA_IN_LINUX_CONTAINER"):
                need = "git (not in the container)"
            if need:
                SKIPPED.append((c, need))
            else:
                runnable.append((i, c))
        # profile.lua runs under the real texlua; the stand-in one is for the tests only.
        results = {}
        jobs = max(2, min(6, os.cpu_count() or 2))

        def one(item):
            i, c = item
            st = stub
            if c["tool"] == "profile" or c["args"][:1] == ["profile"]:
                st = os.path.join(base, "nostub")
                os.makedirs(st, exist_ok=True)
            return i, run_cell(c, trees, st, shell, os.path.join(base, "cells"), i)

        os.makedirs(os.path.join(base, "cells"))
        nest = os.path.join(base, "nested")
        os.makedirs(nest)
        interrupts = concurrent.futures.ThreadPoolExecutor(max_workers=len(INTERRUPTS) + 5)
        interrupt_runs = [interrupts.submit(interrupted_run, nest, outer, sig) for outer, sig in INTERRUPTS]
        for sig in (signal.SIGINT, signal.SIGTERM):
            interrupt_runs.append(interrupts.submit(interrupted_slow, nest, "test.sh", ["slow"], sig))
            interrupt_runs.append(interrupts.submit(interrupted_slow, nest, "test_times", ["run", "2", "slow"], sig))
        if have["docker"]:
            interrupt_runs.append(interrupts.submit(interrupted_container, nest, signal.SIGTERM))
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
            for i, res in pool.map(one, runnable):
                results[i] = res
        for run in interrupt_runs:
            for problem in run.result():
                check(False, problem)
        interrupts.shutdown()
        rows = []
        for i, c in runnable:
            bad, rc = results[i]
            label = f"{c['tool']} {shlex.join(c['args'])}".strip()
            rows.append((label, c["note"], c["expect"], "ok" if not bad else "; ".join(bad), rc))
            for b in bad:
                check(False, f"{label} [{c['note']}]: {b}")
    skipped_notes = sorted({f"{c['tool']} {need}" for c, need in SKIPPED})
    for s in skipped_notes:
        print(f"tools matrix: skipped rows for {s}, which is not available here")
    if os.environ.get("TOOLS_MATRIX_TABLE"):
        print(f"{'call':64} {'expected':8} {'rc':>4}  outcome")
        for label, note, expect, outcome, rc in rows:
            print(f"{label[:64]:64} {expect:8} {rc:>4}  {outcome}")
    ran_n = len(rows) + len(interrupt_runs)
    if failures:
        print(f"tools matrix: {len(failures)} failure(s) in {ran_n} rows", file=sys.stderr)
        return 1
    print(f"tools matrix: ok ({ran_n} rows run, {len(SKIPPED)} skipped)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
