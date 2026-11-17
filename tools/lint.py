# Lints the repository's Lua with lua-language-server, the checker behind the
# editor's warnings, so that what the editor shows is what CI fails on.
#
#   python3 -I tools/lint.py
#
# Reads .luarc.json (Lua 5.3, the LuaTeX globals in .luals/luatex.lua).
# Files named in .lint-exempt are reported as a count and do not fail the
# run: the list is the debt not yet cleaned, and it only shrinks. A file
# listed there that has become clean is reported, so its line can go.
#
# The server is found as $LUA_LS or lua-language-server on PATH.
import fnmatch
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def exempt_patterns():
    path = os.path.join(ROOT, ".lint-exempt")
    if not os.path.exists(path):
        return []
    with open(path) as f:
        lines = (line.split("#", 1)[0].strip() for line in f)
        return [line for line in lines if line]


def diagnostics(server):
    """Every finding at warning level or above, as (file, line, col, code, text)."""
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "check.json")
        run = subprocess.run(
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
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if not os.path.exists(out):
            # No report is written when nothing was found; anything else is a failure.
            if run.returncode == 0:
                return []
            sys.exit("lint: lua-language-server failed:\n" + run.stdout + run.stderr)
        with open(out) as f:
            report = json.load(f)
    found = []
    # An empty report is a list, a non-empty one a mapping from file URI.
    for uri, items in (report.items() if isinstance(report, dict) else []):
        path = urllib.request.url2pathname(urllib.parse.urlparse(uri).path)
        rel = os.path.relpath(path, ROOT)
        for d in items:
            start = d["range"]["start"]
            text = d["message"].split("\n", 1)[0]
            found.append((rel, start["line"] + 1, start["character"] + 1, d["code"], text))
    return sorted(found)


def main():
    server = os.environ.get("LUA_LS") or shutil.which("lua-language-server")
    if not server:
        sys.exit("lint: lua-language-server not found (set LUA_LS or put it on PATH)")
    patterns = exempt_patterns()
    exempt = {}
    failing = []
    for rel, line, col, code, text in diagnostics(server):
        if any(fnmatch.fnmatch(rel, p) for p in patterns):
            exempt[rel] = exempt.get(rel, 0) + 1
        else:
            failing.append((rel, line, col, code, text))
    for rel, line, col, code, text in failing:
        print(f"{rel}:{line}:{col}: {code}: {text}")
    for p in patterns:
        hit = [f for f in exempt if fnmatch.fnmatch(f, p)]
        if not hit and "*" not in p and os.path.exists(os.path.join(ROOT, p)):
            print(f"lint: {p} is clean; remove it from .lint-exempt")
    if exempt:
        print(f"lint: {sum(exempt.values())} findings in {len(exempt)} files are exempt (.lint-exempt)")
    if failing:
        print(f"lint: {len(failing)} findings")
        sys.exit(1)
    print("lint: ok")


if __name__ == "__main__":
    main()
