# Local server for the tuner (the Svelte app in tuner/, built to tuner/dist).
#
#   GET  /                 the built tuner app and its static files
#   GET  /api/components   the components (lua/flora/components.lua) as JSON
#   POST /api/component    {values, id, seed}: draw that component's
#                          specimen with `values` as overrides
#   GET  /api/tune         lua/flora/tune.lua as JSON, with tune-local.lua
#                          applied when it exists
#   POST /api/render       {values, seed, page, full}: draw that reference page
#                          with `values` as overrides. By default the flora
#                          is drawn without TeX (tools/preview.lua) over a
#                          cached text-only compile, and the flora and text
#                          images are returned separately; with full = true
#                          the page is compiled by LuaLaTeX.
#   POST /api/save         {values}: write them to tune-local.lua, which
#                          `just build` then applies
#   POST /api/bake         {values}: write the changed ones into
#                          lua/flora/tune.lua itself (tools/bake_tune.py)
#
# Run from the repository root after building the app (just tuner does
# both). It binds 127.0.0.1 only. Page renders run one at a time;
# specimens, which take a fraction of a second, run alongside them.
import json
import os
import tempfile
import subprocess
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
import bake_tune  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX_BIN = os.path.dirname(bake_tune.TEXLUA)
OUT = os.path.join(ROOT, "build", "tuner")
LOCAL = os.path.join(ROOT, "tune-local.lua")
PORT = int(os.environ.get("TUNER_PORT", "8766"))
DPI = 110
render_lock = threading.Lock()


def env(tune_path=None):
    e = dict(os.environ)
    e["PATH"] = TEX_BIN + ":" + e.get("PATH", "")
    e["TEXINPUTS"] = "./tex//:"
    path = tune_path or (LOCAL if os.path.exists(LOCAL) else "")
    e["FLORA_TUNE"] = path
    return e


def lua_literal(v, indent=""):
    """A JSON value as a Lua table constructor."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{ " + ", ".join(lua_literal(x) for x in v) + " }"
    inner = indent + "  "
    rows = [f"{inner}{k} = {lua_literal(x, inner)}," for k, x in sorted(v.items())]
    return "{\n" + "\n".join(rows) + "\n" + indent + "}"


def write_tune(path, values):
    with open(path, "w") as f:
        f.write("-- Tuner overrides for lua/flora/tune.lua, written by tuner/server.py.\n")
        f.write("return " + lua_literal(values) + "\n")


def current_tune():
    out = subprocess.run([os.path.join(TEX_BIN, "texlua"), "tools/tune_json.lua"],
                         cwd=ROOT, env=env(), capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def lualatex(job, tex, env_, outdir=OUT):
    run = subprocess.run(["lualatex", "-interaction=nonstopmode", "-halt-on-error",
                          f"-output-directory={outdir}", f"-jobname={job}", tex],
                         cwd=ROOT, env=env_, capture_output=True, text=True)
    if run.returncode != 0:
        log = open(os.path.join(outdir, job + ".log"), errors="replace").read()
        raise RuntimeError(log[-2500:])


def rasterize(pdf, page, stem):
    subprocess.run(["pdftocairo", "-png", "-singlefile", "-r", str(DPI), "-f", str(page), "-l", str(page),
                    pdf, stem], cwd=ROOT, env=env(), check=True)
    return stem + ".png"


def fresh_png(prefix):
    """A new render path; renders older than two minutes are removed."""
    for name in os.listdir(OUT):
        if name.startswith(("page-", "flora-", "part-")) and time.time() - os.path.getmtime(os.path.join(OUT, name)) > 120:
            os.remove(os.path.join(OUT, name))
    return os.path.join(OUT, f"{prefix}-{int(time.time() * 1000)}")


def url(path):
    return "/" + os.path.relpath(path, ROOT)


# Inputs that change the text layout. When any is newer than the base
# compile, the base is rebuilt.
LAYOUT_INPUTS = ["tex/reference.tex", "tex/tikzflora.sty", "lua/flora/init.lua", "lua/flora/measure.lua"]


def base():
    """The text-only compile: measured layouts (spec-N.lua) and page images."""
    base_dir = os.path.join(OUT, "base")
    stamp = os.path.join(base_dir, "base.pdf")
    newest = max(os.path.getmtime(os.path.join(ROOT, p)) for p in LAYOUT_INPUTS)
    if not os.path.exists(stamp) or os.path.getmtime(stamp) < newest:
        os.makedirs(base_dir, exist_ok=True)
        e = env()
        e["FLORA_SPEC_DIR"] = base_dir
        lualatex("base", "\\def\\florapages{0}\\input{tex/reference.tex}", e, base_dir)
        for name in os.listdir(base_dir):
            if name.startswith("text-"):
                os.remove(os.path.join(base_dir, name))
    return base_dir


def render_fast(values, seed, page):
    """Flora drawn by tools/preview.lua over the cached text page, no TeX."""
    t0 = time.time()
    base_dir = base()
    text = os.path.join(base_dir, f"text-{page}.png")
    if not os.path.exists(text):
        rasterize(os.path.join(base_dir, "base.pdf"), page, text[:-4])
    tune_path = os.path.join(OUT, "override.lua")
    write_tune(tune_path, values)
    stem = fresh_png("flora")
    run = subprocess.run([os.path.join(TEX_BIN, "texlua"), "tools/preview.lua",
                          os.path.join(base_dir, f"spec-{page}.lua"), str(int(seed)), str(page), stem + ".pdf"],
                         cwd=ROOT, env=env(tune_path), capture_output=True, text=True)
    if run.returncode != 0:
        raise RuntimeError(run.stderr[-2500:])
    png = rasterize(stem + ".pdf", 1, stem)
    os.remove(stem + ".pdf")
    return {"png": url(png), "text": url(text), "dpi": DPI, "seconds": round(time.time() - t0, 1)}


def render_full(values, seed, page):
    """The exact LuaLaTeX build of one page."""
    t0 = time.time()
    tune_path = os.path.join(OUT, "override.lua")
    write_tune(tune_path, values)
    # Light compression: previews are thrown away, and level 1 saves about
    # a second per page over the default.
    lualatex("tuner", "\\pdfvariable compresslevel=1"
             f"\\def\\florseed{{{int(seed)}}}\\def\\florapages{{{int(page)}}}"
             "\\input{tex/reference.tex}", env(tune_path))
    png = rasterize(os.path.join(OUT, "tuner.pdf"), page, fresh_png("page"))
    return {"png": url(png), "dpi": DPI, "seconds": round(time.time() - t0, 1)}


def components():
    out = subprocess.run([os.path.join(TEX_BIN, "texlua"), "tools/component.lua", "--list"],
                         cwd=ROOT, env=env(), capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def render_component(values, cid, seed):
    """One component's specimen, drawn without TeX at 2x the page DPI."""
    t0 = time.time()
    os.makedirs(OUT, exist_ok=True)
    stem = fresh_png("part")
    with tempfile.NamedTemporaryFile("w", suffix=".lua", dir=OUT, delete=False) as f:
        tune_path = f.name
    try:
        write_tune(tune_path, values)
        run = subprocess.run([os.path.join(TEX_BIN, "texlua"), "tools/component.lua", str(cid), str(int(seed)),
                              stem + ".pdf"], cwd=ROOT, env=env(tune_path), capture_output=True, text=True)
    finally:
        os.remove(tune_path)
    if run.returncode != 0:
        raise RuntimeError(run.stderr[-2500:])
    subprocess.run(["pdftocairo", "-png", "-singlefile", "-r", str(DPI * 2), stem + ".pdf", stem],
                   cwd=ROOT, env=env(), check=True)
    os.remove(stem + ".pdf")
    return {"png": url(stem + ".png"), "dpi": DPI * 2, "seconds": round(time.time() - t0, 2)}


def render(values, seed, page, full=False):
    os.makedirs(OUT, exist_ok=True)
    return (render_full if full else render_fast)(values, seed, page)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    def log_message(self, format, *args):
        sys.stderr.write("tuner: " + format % args + "\n")

    def send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            if not os.path.exists(os.path.join(ROOT, "tuner", "dist", "index.html")):
                return self.send_error(503, "tuner app not built: run `just tuner`")
            self.path = "/tuner/dist/index.html"
        if self.path == "/api/tune":
            return self.send_json(200, current_tune())
        if self.path == "/api/components":
            return self.send_json(200, components())
        # Serve only the built app, its renders and the reference.
        allowed = ("/tuner/dist/", "/build/tuner/", "/tex/reference/rectified.png")
        if not self.path.startswith(allowed):
            return self.send_error(404)
        return super().do_GET()

    def do_POST(self):
        size = int(self.headers.get("Content-Length", "0"))
        try:
            req = json.loads(self.rfile.read(size) or b"{}")
        except json.JSONDecodeError:
            return self.send_json(400, {"error": "bad JSON"})
        if self.path == "/api/render":
            with render_lock:
                try:
                    return self.send_json(200, render(req["values"], req.get("seed", 1), req.get("page", 1),
                                                      bool(req.get("full"))))
                except Exception as e:  # report compile failures to the page
                    return self.send_json(500, {"error": str(e)})
        if self.path == "/api/component":
            try:
                return self.send_json(200, render_component(req["values"], req["id"], req.get("seed", 1)))
            except Exception as e:  # report draw failures to the page
                return self.send_json(500, {"error": str(e)})
        if self.path == "/api/bake":
            try:
                changed = bake_tune.bake(req["values"])
            except Exception as e:  # the file is left as it was
                return self.send_json(500, {"error": f"tune.lua not changed: {e}"})
            return self.send_json(200, {"changed": changed, "local": os.path.exists(LOCAL)})
        if self.path == "/api/save":
            write_tune(LOCAL, req["values"])
            return self.send_json(200, {"saved": os.path.relpath(LOCAL, ROOT)})
        return self.send_error(404)


if __name__ == "__main__":
    os.chdir(ROOT)
    print(f"tuner: http://127.0.0.1:{PORT}/")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
