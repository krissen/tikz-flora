"""Where flora round the paper's edge lies, measured on the pages
tools/frame_flora.lua renders, and those pages as one labelled sheet.

    python3 -I tools/frame_flora.py OUTDIR [TITLE]

Reads OUTDIR/pages.tsv, rasterises each page (pdftocairo, 150 dpi,
transparent where nothing is painted) and writes:

- OUTDIR/measure.tsv, one line a page and side (left, right, foot, top).
  Each painted pixel outside the text block belongs to the side whose
  paper edge is nearest. near and far are the least and greatest distance
  of that ink from the paper's edge (mm); cover the share of the side's
  length with ink of the side at all, and cover_band with ink within the
  band asked; beyond the share of the side's ink further in than the band
  asked. text_mm2 is the ink inside the text block (mm2), the frame title
  and the reservation included, and title_mm2 that inside the frame
  title's box alone.
- OUTDIR/summary.md, a table of the same, the seeds of one page taken
  together (the least near, the greatest far, the mean covers).
- OUTDIR/sheet.png, the pages in the rows and columns pages.tsv names,
  each with its text block in grey, the frame title darker, and the band
  asked as a dashed line, under TITLE.

Needs numpy and Pillow.
"""
import csv
import sys
from collections import OrderedDict
from itertools import pairwise
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import toolproc

DPI = 150
PX = DPI / 72.0
MM = 72 / 25.4
SIDES = ("left", "right", "foot", "top")
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"


def box(s):
    return [float(v) for v in s.split(",")] if s else None


def render(out, file, dpi, transparent=True):
    png = out / f"{file}-{dpi}"
    args = ["pdftocairo", "-png", "-singlefile", "-r", str(dpi)]
    if transparent:
        args.append("-transp")
    toolproc.run([*args, str(out / f"{file}.pdf"), str(png)], check=True)
    return Path(str(png) + ".png")


def ink_mask(png):
    return np.asarray(Image.open(png).convert("RGBA"))[:, :, 3] > 16


def measure(out, r):
    a = ink_mask(render(out, r["file"], DPI))
    h, w = a.shape
    W, H = float(r["W"]), float(r["H"])
    # Pixel centres in pt, y up from the foot.
    xs = (np.arange(w) + 0.5) / PX
    ys = H - (np.arange(h) + 0.5) / PX
    X, Y = np.meshgrid(xs, ys)
    t = [float(r[k]) for k in ("tx0", "ty0", "tx1", "ty1")]
    inside = (X > t[0]) & (X < t[2]) & (Y > t[1]) & (Y < t[3])
    px_mm2 = (25.4 / DPI) ** 2
    text_mm2 = float((a & inside).sum()) * px_mm2
    tb = box(r["title"])
    title_mm2 = 0.0
    if tb:
        tin = (X > tb[0]) & (X < tb[2]) & (Y > tb[1]) & (Y < tb[3])
        title_mm2 = float((a & tin).sum()) * px_mm2
    d = np.stack([X, W - X, Y, H - Y])
    side = np.argmin(d, axis=0)
    dist = np.min(d, axis=0)
    band = float(r["band_mm"]) * MM
    rows = []
    for k, name in enumerate(SIDES):
        sel = a & ~inside & (side == k)
        # Positions along the side: columns for the foot and top, rows for
        # the left and right.
        along = 0 if name in ("foot", "top") else 1
        n = sel.shape[1 - along]
        if sel.any():
            dd = dist[sel]
            near, far = dd.min() / MM, dd.max() / MM
            cover = sel.any(axis=along).sum() / n
            cover_band = (sel & (dist <= band)).any(axis=along).sum() / n
            beyond = float((dd > band).sum()) / dd.size
        else:
            near = far = float("nan")
            cover = cover_band = beyond = 0.0
        rows.append({**{k2: r[k2] for k2 in ("file", "row", "col", "kind", "paper", "band_mm", "band_pt", "seed")},
                     "side": name, "near": f"{near:.1f}", "far": f"{far:.1f}", "cover": f"{cover:.2f}",
                     "cover_band": f"{cover_band:.2f}", "beyond": f"{beyond:.2f}",
                     "text_mm2": f"{text_mm2:.1f}", "title_mm2": f"{title_mm2:.1f}"})
    return rows


def summary(rows):
    groups = OrderedDict()
    for m in rows:
        groups.setdefault((m["row"], m["col"]), {}).setdefault(m["side"], []).append(m)
    lines = ["| page | | " + " | ".join(f"{s} near-far mm, cover (in band) %, beyond %" for s in SIDES) + " | text mm2 (title) |",
             "|---|---|" + "---|" * len(SIDES) + "---|"]
    for (row, col), sides in groups.items():
        cells = []
        for s in SIDES:
            ms = sides[s]
            near = min(float(m["near"]) for m in ms)
            far = max(float(m["far"]) for m in ms)
            cov = np.mean([float(m["cover"]) for m in ms]) * 100
            cb = np.mean([float(m["cover_band"]) for m in ms]) * 100
            bey = np.mean([float(m["beyond"]) for m in ms]) * 100
            if np.isnan(near):
                cells.append("none")
            else:
                cells.append(f"{near:.1f}-{far:.1f}, {cov:.0f} ({cb:.0f}), {bey:.0f}")
        ms = sides[SIDES[0]]
        text = max(float(m["text_mm2"]) for m in ms)
        title = max(float(m["title_mm2"]) for m in ms)
        laid = float(ms[0]["band_pt"]) / MM
        lines.append(f"| {row} | {col} (laid {laid:.1f}) | " + " | ".join(cells) + f" | {text:.1f} ({title:.1f}) |")
    return "\n".join(lines) + "\n"


def font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default()


def tile(out, r, width):
    W, H = float(r["W"]), float(r["H"])
    k = width / W
    dpi = 72 * k
    im = Image.open(render(out, r["file"], f"{dpi:.2f}", transparent=False)).convert("RGB")
    im = im.resize((width, round(H * k)))
    base = Image.new("RGB", im.size, "white")
    dr = ImageDraw.Draw(base)

    def rect(b, **kw):
        dr.rectangle([b[0] * k, (H - b[3]) * k, b[2] * k, (H - b[1]) * k], **kw)

    t = [float(r[c]) for c in ("tx0", "ty0", "tx1", "ty1")]
    rect(t, fill="#ecebe7")
    tb = box(r["title"])
    if tb:
        rect(tb, fill="#c9c6bf")
    rb = box(r["reserve"])
    if rb:
        rect(rb, outline="#d08a8a")
    base = Image.composite(im, base, Image.eval(im.convert("L"), lambda v: 255 if v < 250 else 0))
    dr = ImageDraw.Draw(base)
    # The band asked, dashed.
    b = float(r["band_mm"]) * MM
    pts = [(b, b), (W - b, b), (W - b, H - b), (b, H - b), (b, b)]
    for (x0, y0), (x1, y1) in pairwise(pts):
        n = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) * k / 8))
        for i in range(0, n, 2):
            u0, u1 = i / n, min(1, (i + 1) / n)
            dr.line([((x0 + (x1 - x0) * u0) * k, (H - (y0 + (y1 - y0) * u0)) * k),
                     ((x0 + (x1 - x0) * u1) * k, (H - (y0 + (y1 - y0) * u1)) * k)], fill="#c0392b", width=1)
    dr.rectangle([0, 0, base.width - 1, base.height - 1], outline="#9a968e")
    return base


def sheet(out, pages, title, width=520):
    rows = OrderedDict()
    for r in pages:
        rows.setdefault(r["row"], OrderedDict()).setdefault(r["col"], r)
    ncol = max(len(c) for c in rows.values())
    tiles = {(ri, ci): tile(out, r, width) for ri, cols in enumerate(rows.values()) for ci, r in enumerate(cols.values())}
    th = max(t.height for t in tiles.values())
    lab, pad, head = 22, 14, 40
    S = Image.new("RGB", (pad + ncol * (width + pad), head + len(rows) * (th + lab + pad) + pad), "#d8d4cc")
    dr = ImageDraw.Draw(S)
    dr.text((pad, 10), title, fill="black", font=font(20))
    for ri, (rname, cols) in enumerate(rows.items()):
        for ci, (cname, _) in enumerate(cols.items()):
            x = pad + ci * (width + pad)
            y = head + ri * (th + lab + pad)
            dr.text((x, y + 2), f"{rname}  |  {cname}", fill="black", font=font(14))
            S.paste(tiles[(ri, ci)], (x, y + lab))
    S.save(out / "sheet.png")


def main(out, title=""):
    toolproc.install()
    out = Path(out)
    with open(out / "pages.tsv") as f:
        pages = list(csv.DictReader(f, delimiter="\t"))
    rows = [m for r in pages for m in measure(out, r)]
    with open(out / "measure.tsv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()), delimiter="\t")
        w.writeheader()
        w.writerows(rows)
    (out / "summary.md").write_text(summary(rows))
    sheet(out, [r for r in pages if r["seed"] == pages[0]["seed"]], title or out.name)
    print(f"frame_flora: {out / 'measure.tsv'}, {out / 'summary.md'}, {out / 'sheet.png'}")


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: python3 -I tools/frame_flora.py OUTDIR [TITLE]")
    main(*sys.argv[1:])
