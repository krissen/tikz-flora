"""lua-language-server's findings down to the level Hint, for chosen files.

    python3 -I tools/lint_hint.py FILE...

`just lint` (tools/lint.py) fails on findings at Warning and above; the
editor also shows those below it, Information and Hint (in .luarc.json,
duplicate-set-field among them). This runs the same checker over the
repository, as the editor does, at --checklevel=Hint, and prints every
finding in the files named, a count per file, and exits 1 when there is
any, 0 when there is none. Files with no findings are named with 0.

A file outside lua-language-server's workspace (.luarc.json's
workspace.ignoreDir) or not a .lua file is refused (exit 2). The checker
is $LUA_LS, else lua-language-server on PATH.
"""
import json
import os
import shutil
import sys
import tempfile
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import toolproc

ROOT = os.environ.get("LINT_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def relative(path):
    return os.path.relpath(os.path.realpath(path), os.path.realpath(ROOT))


def check(server):
    """Every finding of the workspace at Hint and above, as (file, line, col, code, text)."""
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "check.json")
        proc = toolproc.run(
            [server, "--check", ROOT, "--configpath=" + os.path.join(ROOT, ".luarc.json"), "--checklevel=Hint",
             "--check_format=json", "--check_out_path=" + out, "--logpath=" + os.path.join(tmp, "log"),
             "--metapath=" + os.path.join(tmp, "meta")],
            cwd=ROOT, capture_output=True, text=True, check=False)
        if not os.path.exists(out):
            if proc.returncode == 0:
                return []
            raise RuntimeError(proc.stdout + proc.stderr)
        with open(out) as f:
            report = json.load(f)
    found = []
    for uri, items in report.items() if isinstance(report, dict) else []:
        rel = relative(urllib.request.url2pathname(urllib.parse.urlparse(uri).path))
        for d in items:
            start = d["range"]["start"]
            found.append((rel, start["line"] + 1, start["character"] + 1, d["code"], d["message"].split("\n", 1)[0]))
    return found


def main(argv):
    toolproc.install()
    if not argv:
        print("usage: python3 -I tools/lint_hint.py FILE...")
        return 2
    try:
        with open(os.path.join(ROOT, ".luarc.json")) as f:
            ignored = json.load(f).get("workspace.ignoreDir", [])
    except (OSError, ValueError):
        ignored = []
    files = []
    for a in argv:
        rel = relative(os.path.join(os.getcwd(), a))
        outside = any(rel == d or rel.startswith(d.rstrip("/") + "/") for d in ignored)
        if not rel.endswith(".lua") or not os.path.isfile(os.path.join(ROOT, rel)) or outside or rel.startswith(".."):
            print(f"lint-hint: {a} is not a Lua file lua-language-server checks")
            return 2
        files.append(rel)
    server = os.environ.get("LUA_LS") or shutil.which("lua-language-server")
    if not server:
        print("lint-hint: lua-language-server not found (brew install lua-language-server)")
        return 2
    try:
        found = check(server)
    except (RuntimeError, ValueError, KeyError) as e:
        print(f"lint-hint: lua-language-server failed to run or gave output that could not be read:\n{e}")
        return 2
    total = 0
    for rel in files:
        mine = sorted(f for f in found if f[0] == rel)
        for _, line, col, code, text in mine:
            print(f"{rel}:{line}:{col}: {code}: {text}")
        print(f"lint-hint: {rel}: {len(mine)}")
        total += len(mine)
    print(f"lint-hint: {'ok' if total == 0 else str(total) + ' findings'}")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
