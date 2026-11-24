# Lints the repository: its Lua with lua-language-server (the checker behind
# the editor's warnings, so what the editor shows is what CI fails on), its
# Python with ruff and pyright, and its shell scripts with shellcheck.
#
#   python3 -I tools/lint.py [--require-pyright]
#
# Configuration: .luarc.json (Lua 5.3, the LuaTeX globals in
# .luals/luatex.lua), ruff.toml, pyrightconfig.json; shellcheck runs on
# tools/*.sh with its defaults. Files named in .lint-exempt are reported as
# a count and do not fail the run: the list is the debt not yet cleaned, and
# it only shrinks. A file listed there that has become clean is reported, so
# its line can go.
#
# A tool that is not installed fails the run and is named; nothing is
# skipped quietly. The one exception is pyright, which is skipped, said
# aloud, when it is not on PATH, unless --require-pyright is given (CI).
# Locations: $LUA_LS for lua-language-server, otherwise PATH.
import fnmatch
import glob
import json
import os
import shutil
import sys
import tempfile
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toolproc

# LINT_ROOT points the run at another tree; tests/test_lint.py uses it.
ROOT = os.environ.get("LINT_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

INSTALL = {
    "lua-language-server": "brew install lua-language-server",
    "ruff": "brew install ruff, or pip install ruff",
    "shellcheck": "brew install shellcheck",
    "pyright": "pip install pyright",
}


def exempt_patterns():
    path = os.path.join(ROOT, ".lint-exempt")
    if not os.path.exists(path):
        return []
    with open(path) as f:
        lines = (line.split("#", 1)[0].strip() for line in f)
        return [line for line in lines if line]


def owners(rel):
    """The tools that read this file, and so the only ones that can call it clean."""
    if rel.endswith(".lua"):
        try:
            with open(os.path.join(ROOT, ".luarc.json")) as f:
                ignored = json.load(f).get("workspace.ignoreDir", [])
        except (OSError, ValueError):
            ignored = []
        outside = any(rel == d or rel.startswith(d.rstrip("/") + "/") for d in ignored)
        return [] if outside else ["lua-language-server"]
    if rel.endswith(".py"):
        return ["ruff", "pyright"]
    if rel.endswith(".sh") and os.path.dirname(rel) == "tools":
        return ["shellcheck"]
    return []


def relative(path):
    return os.path.relpath(os.path.realpath(path), os.path.realpath(ROOT))


def run(cmd):
    return toolproc.run(cmd, cwd=ROOT, capture_output=True, text=True, check=False)


def lua(server):
    """Findings at warning level or above, as (file, line, col, code, text)."""
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "check.json")
        proc = run(
            [
                server,
                "--check",
                ROOT,
                "--configpath=" + os.path.join(ROOT, ".luarc.json"),
                "--checklevel=Warning",
                "--check_format=json",
                "--check_out_path=" + out,
                "--logpath=" + os.path.join(tmp, "log"),
                "--metapath=" + os.path.join(tmp, "meta"),
            ]
        )
        if not os.path.exists(out):
            # No report is written when nothing was found; anything else is a failure.
            if proc.returncode == 0:
                return []
            raise RuntimeError(proc.stdout + proc.stderr)
        with open(out) as f:
            report = json.load(f)
    found = []
    # An empty report is a list, a non-empty one a mapping from file URI.
    for uri, items in report.items() if isinstance(report, dict) else []:
        rel = relative(urllib.request.url2pathname(urllib.parse.urlparse(uri).path))
        for d in items:
            start = d["range"]["start"]
            found.append((rel, start["line"] + 1, start["character"] + 1, d["code"], d["message"].split("\n", 1)[0]))
    return found


def ruff(exe):
    proc = run([exe, "check", "--output-format=json", "."])
    if proc.returncode not in (0, 1):
        raise RuntimeError(proc.stdout + proc.stderr)
    return [
        (relative(d["filename"]), d["location"]["row"], d["location"]["column"], d["code"] or "error", d["message"])
        for d in json.loads(proc.stdout)
    ]


def shellcheck(exe):
    files = sorted(os.path.relpath(f, ROOT) for f in glob.glob(os.path.join(ROOT, "tools", "*.sh")))
    proc = run([exe, "-f", "json", *files])
    if proc.returncode not in (0, 1):
        raise RuntimeError(proc.stdout + proc.stderr)
    return [
        (relative(os.path.join(ROOT, d["file"])), d["line"], d["column"], f"SC{d['code']}", d["message"])
        for d in json.loads(proc.stdout or "[]")
    ]


def pyright(exe):
    proc = run([exe, "--outputjson"])
    if proc.returncode not in (0, 1):
        raise RuntimeError(proc.stdout + proc.stderr)
    found = []
    for d in json.loads(proc.stdout).get("generalDiagnostics", []):
        if d["severity"] in ("error", "warning"):
            start = d["range"]["start"]
            found.append(
                (relative(d["file"]), start["line"] + 1, start["character"] + 1, d.get("rule", "pyright"), d["message"].split("\n", 1)[0])
            )
    return found


def main():
    toolproc.install()
    require_pyright = "--require-pyright" in sys.argv[1:]
    patterns = exempt_patterns()
    tools = [
        ("lua-language-server", os.environ.get("LUA_LS") or shutil.which("lua-language-server"), lua),
        ("ruff", shutil.which("ruff"), ruff),
        ("shellcheck", shutil.which("shellcheck"), shellcheck),
        ("pyright", shutil.which("pyright"), pyright),
    ]
    failing = {}
    exempt = {}
    broken = []
    ran = set()
    skipped = []
    for name, exe, check in tools:
        if not exe:
            if name == "pyright" and not require_pyright:
                print("lint: pyright skipped, not on PATH (pip install pyright)")
                skipped.append(name)
                continue
            print(f"lint: {name} not found ({INSTALL[name]})")
            broken.append(name)
            continue
        try:
            findings = sorted(set(check(exe)))
        except (RuntimeError, ValueError, KeyError, TypeError) as e:
            print(f"lint: {name} failed to run or gave output that could not be read:\n{e}")
            broken.append(name)
            continue
        ran.add(name)
        for finding in findings:
            if any(fnmatch.fnmatch(finding[0], p) for p in patterns):
                exempt[finding[0]] = exempt.get(finding[0], 0) + 1
            else:
                failing.setdefault(name, []).append(finding)
        for rel, line, col, code, text in failing.get(name, []):
            print(f"{name}: {rel}:{line}:{col}: {code}: {text}")
        n = len(failing.get(name, []))
        print(f"lint: {name}: {'ok' if not n else str(n) + ' findings'}")
    # An exact exemption is called clean only when every tool that reads the
    # file ran to the end and found nothing in it. Globs and files no tool
    # reads are never called clean.
    unchecked = []
    for p in patterns:
        if any(c in p for c in "*?[") or not os.path.exists(os.path.join(ROOT, p)):
            continue
        who = owners(p)
        if not who:
            continue
        if not all(t in ran for t in who):
            unchecked.append(p)
        elif p not in exempt:
            print(f"lint: {p} is clean; remove it from .lint-exempt")
    if unchecked:
        left = sorted({t for p in unchecked for t in owners(p) if t not in ran})
        print(f"lint: {len(unchecked)} exact exemptions not checked for cleanliness ({', '.join(left)} did not run)")
    if exempt:
        left = sorted(set(broken + skipped))
        note = f"; not counted: {', '.join(left)} did not run" if left else ""
        print(f"lint: {sum(exempt.values())} findings in {len(exempt)} files are exempt (.lint-exempt{note})")
    bad = sorted(set(failing) | set(broken))
    if bad:
        print("lint: failed: " + ", ".join(bad))
        sys.exit(1)
    print("lint: ok")


if __name__ == "__main__":
    main()
