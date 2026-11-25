# tools/lint.py against stand-in tools: for each tool and each way it can
# end (clean, findings in an exempt file, findings in another file, missing,
# crash, unreadable output), what it says about the exemptions and how it
# ends; that ruff and pyright are taken from the tree's .venv before PATH,
# pyright with .venv's Python; and that an argument it does not take stops
# it. The claim "is clean; remove it" must be made
# for a file only when every tool responsible for that file ran to the end
# and found nothing in it. No network and none of the real tools.
# Run from the repository root: python3 -I tests/test_lint.py
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import toolproc

toolproc.install()

LINT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools", "lint.py")

failures = 0


def check(cond, msg):
    global failures
    if not cond:
        failures += 1
        sys.stderr.write("FAIL: " + msg + "\n")


# One script stands in for every tool; FAKE_<NAME> says how it behaves.
FAKE = """#!{exe}
import json, os, sys
root = os.environ["LINT_ROOT"]
name = os.path.basename(sys.argv[0])
mode = os.environ["FAKE_" + name.upper().replace("-", "_")]
# The file each tool reports on: one the exemptions list, or one they do not.
target = {{"lua-language-server": "a.lua", "ruff": "b.py", "shellcheck": "tools/c.sh", "pyright": "b.py"}}[name]
if mode == "findings_other":
    target = {{"lua-language-server": "z.lua", "ruff": "z.py", "shellcheck": "tools/z.sh", "pyright": "z.py"}}[name]
found = mode in ("findings", "findings_other")
if mode == "crash":
    sys.stderr.write("boom\\n")
    sys.exit(2)
if name == "lua-language-server":
    out = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--check_out_path=")][0]
    if mode == "garbage":
        open(out, "w").write("not json")
        sys.exit(1)
    if found:
        item = {{"range": {{"start": {{"line": 0, "character": 0}}}}, "code": "need-check-nil", "message": "m"}}
        json.dump({{"file://" + os.path.join(root, target): [item]}}, open(out, "w"))
        sys.exit(1)
    sys.exit(0)
if mode == "garbage":
    print("not json")
    sys.exit(1)
if name == "ruff":
    print(json.dumps([{{"filename": os.path.join(root, target), "location": {{"row": 1, "column": 1}}, "code": "F401", "message": "m"}}] if found else []))
elif name == "shellcheck":
    print(json.dumps([{{"file": target, "line": 1, "column": 1, "code": 2086, "message": "m"}}] if found else []))
else:
    diag = [{{"file": os.path.join(root, target), "severity": "error", "range": {{"start": {{"line": 0, "character": 0}}}}, "rule": "r", "message": "m"}}]
    print(json.dumps({{"generalDiagnostics": diag if found else []}}))
sys.exit(1 if found else 0)
"""

# A clean ruff or pyright for a tree's .venv, which records its arguments.
VENV_FAKE = """#!{exe}
import json, os, sys
open(os.path.join(os.path.dirname(sys.argv[0]), "args-{tool}"), "w").write(" ".join(sys.argv[1:]))
print(json.dumps([] if "{tool}" == "ruff" else {{"generalDiagnostics": []}}))
"""

TOOLS = ["lua-language-server", "ruff", "shellcheck", "pyright"]
# Exact exemptions, with the tools responsible for each. A glob is never
# claimed clean; ignored/ is outside lua-language-server's workspace and e.md
# is read by no tool, so neither can be claimed clean either.
OWNERS = {
    "a.lua": ["lua-language-server"],
    "b.py": ["ruff", "pyright"],
    "tools/c.sh": ["shellcheck"],
    "ignored/d.lua": [],
    "e.md": [],
}
TARGETS = {"lua-language-server": ["a.lua"], "ruff": ["b.py"], "shellcheck": ["tools/c.sh"], "pyright": ["b.py"]}


def make_tree(base):
    root = os.path.join(base, "tree")
    for path in list(OWNERS) + ["g/x.lua", "tools/z.sh"]:
        os.makedirs(os.path.dirname(os.path.join(root, path)), exist_ok=True)
        open(os.path.join(root, path), "w").close()
    with open(os.path.join(root, ".luarc.json"), "w") as f:
        f.write('{"workspace.ignoreDir": ["ignored"]}\n')
    with open(os.path.join(root, ".lint-exempt"), "w") as f:
        f.write("\n".join(list(OWNERS) + ["g/*.lua"]) + "\n")
    return root


def make_bin(base, modes):
    bindir = os.path.join(base, "bin-" + "-".join(modes[t] for t in TOOLS))
    os.makedirs(bindir, exist_ok=True)
    for tool in TOOLS:
        if modes[tool] == "missing":
            continue
        path = os.path.join(bindir, tool)
        with open(path, "w") as f:
            f.write(FAKE.format(exe=sys.executable))
        os.chmod(path, 0o755)
    return bindir


def run(root, bindir, modes, args=()):
    env = {"PATH": bindir, "LINT_ROOT": root}
    for tool in TOOLS:
        env["FAKE_" + tool.upper().replace("-", "_")] = modes[tool]
    p = toolproc.run([sys.executable, "-I", LINT, *args], env=env, capture_output=True, text=True, check=False)
    # An error on stderr that the output and the status do not show is a
    # failure too.
    check("Traceback" not in p.stderr, f"lint.py ended with a traceback: {p.stderr[-300:]!r}")
    return p.returncode, p.stdout.splitlines()


def expect(label, modes):
    """What lint.py must say for these outcomes, checked against what it says."""
    code, out = RUNS[label]
    # Tools that ran to the end (findings or not): the others are missing,
    # crashed or gave unreadable output.
    ran = {t for t in TOOLS if modes[t] in ("clean", "findings", "findings_other")}
    broken = {t for t in TOOLS if t not in ran}
    failing = {t for t in TOOLS if modes[t] == "findings_other"}
    clean = set()
    unchecked = set()
    for path, owners in OWNERS.items():
        if not owners:
            continue
        if not all(o in ran for o in owners):
            unchecked.add(path)
        elif not any(modes[o] == "findings" and path in TARGETS[o] for o in owners):
            clean.add(path)
    said_clean = {line[len("lint: "):-len(" is clean; remove it from .lint-exempt")] for line in out if line.endswith(" is clean; remove it from .lint-exempt")}
    check(said_clean == clean, f"{label}: said clean for {sorted(said_clean)}, want {sorted(clean)}")
    check((code == 0) == (not broken and not failing), f"{label}: exit {code}, want {0 if not (broken or failing) else 'not 0'}")
    check(("lint: ok" in out) == (code == 0), f"{label}: 'lint: ok' printed={'lint: ok' in out}, exit {code}")
    if code != 0:
        want = "lint: failed: " + ", ".join(sorted(broken | failing))
        check(want in out, f"{label}: missing {want!r}")
    check(any("not checked" in line for line in out) == bool(unchecked), f"{label}: the 'not checked' notice, want {bool(unchecked)}")
    exempt_lines = [line for line in out if "are exempt" in line]
    if exempt_lines:
        check(("not counted" in exempt_lines[0]) == bool(broken), f"{label}: the exempt count must say which tools it leaves out")
    # A missing tool is named with how to get it; ruff and pyright from .venv.
    for t in TOOLS:
        if modes[t] == "missing":
            how = "just venv" if t in ("ruff", "pyright") else "brew install"
            check(any(line.startswith(f"lint: {t} not found (") and how in line for line in out), f"{label}: {t} missing, said with how to get it ({how})")


RUNS = {}
CASES = {}


def case(label, modes):
    CASES[label] = modes


allclean = {t: "clean" for t in TOOLS}
case("all clean", allclean)
for tool in TOOLS:
    for mode in ("findings", "findings_other", "missing", "crash", "garbage"):
        case(f"{tool} {mode}", {**allclean, tool: mode})
case("pyright missing, luals findings", {**allclean, "pyright": "missing", "lua-language-server": "findings"})
case("everything dead", {t: "crash" for t in TOOLS})

with tempfile.TemporaryDirectory() as base:
    root = make_tree(base)
    for label, modes in CASES.items():
        RUNS[label] = run(root, make_bin(base, modes), modes)
        expect(label, modes)

    # An argument lint.py does not take (the old --require-pyright among
    # them) stops it before any tool runs.
    for args in (["--require-pyright"], ["x"]):
        code, out = run(root, make_bin(base, allclean), allclean, args)
        check(code == 2 and any(line.startswith("usage:") for line in out), f"lint.py {args}: exit {code}, want 2 with its usage")

    # ruff and pyright in the tree's .venv are used before PATH's, which
    # crash here; pyright is given .venv's Python.
    venv = os.path.join(root, ".venv", "bin")
    os.makedirs(venv)
    for tool in ("ruff", "pyright"):
        path = os.path.join(venv, tool)
        with open(path, "w") as f:
            f.write(VENV_FAKE.format(exe=sys.executable, tool=tool))
        os.chmod(path, 0o755)
    with open(os.path.join(venv, "python"), "w") as f:
        f.write("#!/bin/sh\n")
    os.chmod(os.path.join(venv, "python"), 0o755)
    modes = {**allclean, "ruff": "crash", "pyright": "crash"}
    code, out = run(root, make_bin(base, modes), modes)
    check(code == 0, f".venv before PATH: exit {code}, want 0: {out}")
    argv = []
    if os.path.exists(os.path.join(venv, "args-pyright")):
        with open(os.path.join(venv, "args-pyright")) as f:
            argv = f.read().split()
    check("--pythonpath" in argv and argv[argv.index("--pythonpath") + 1] == os.path.join(venv, "python"), f"pyright from .venv was not given .venv's Python: {argv}")
    # Without pyright in .venv and on PATH, the run fails and says how.
    os.remove(os.path.join(venv, "pyright"))
    modes = {**allclean, "pyright": "missing"}
    code, out = run(root, make_bin(base, modes), modes)
    check(code != 0 and "lint: pyright not found (just venv makes .venv with it, from requirements-dev.txt)" in out, f"pyright nowhere: exit {code}: {out}")

if failures:
    sys.stderr.write(f"{failures} failures\n")
    sys.exit(1)
print(f"lint script: ok ({len(CASES)} cases)")
