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
  title's box alone. solid is the share of the ink outside the text block
  that is at least SOLID_MM thick (what is left after an opening by a
  square that size: leaves, blooms and stems, not dots and hairlines),
  and solid_mm2_per_cm that ink in mm2 per cm of the paper's edge: a band
  that has become a scatter of specks has little of it. secs is the CPU
  time the page took to paint.
- OUTDIR/summary.md, a table of the same, the seeds of one page taken
  together (the least near, the greatest far, the mean covers).
- OUTDIR/sheet.png, the pages in the rows and columns pages.tsv names,
  each with its text block in grey, the frame title darker, and the band
  as laid as a dashed line (narrower than asked where a margin is),
  under TITLE.

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
# Pixels per page unit. The engine's page units are written to the PDF as
# TeX points (pdfout.lua scales by 72/72.27), so a pixel at DPI is
# 72.27/DPI of them; their mm are the engine's, 72/25.4 to the mm.
PX = DPI / 72.27
PX_MM = 1 / PX / (72 / 25.4)  # mm per pixel, in the engine's mm
MM = 72 / 25.4
SIDES = ("left", "right", "foot", "top")
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
# The sheet's title for each of tools/frame_flora.lua's sets.
TITLES = {
    "measure": "Today: layout=perimeter and surround with flora (band asked and laid dashed)",
    "alts": "(1) The prototypes side by side: 16:9, frame title, 12 mm band",
    "widths": "(2) Each prototype at 8, 12 and 18 mm (16:9, frame title)",
    "papers": "(3) Each prototype on 4:3 and A4 (12 mm, frame title)",
    "band": "(4) Each prototype beside the pattern band (kikko), 12 mm, 16:9",
    "margins": "(5) Margins 25/10/8/12 mm, 12 mm asked: every band narrows to 4.8 mm all round",
    "join": "Vine: how the ring closes (16:9, 12 mm), with where the plants meet enlarged",
    "root": "Vine: the roots at the foot's centre, abutting or crossing (16:9, 12 mm)",
    "scale": "Vine: scaled, fixed or clamped to the band, at 8, 12 and 18 mm, beside today's surround",
    "corners": "Vine: corners rounded to the band, to half of it, mitred, and cut to the band, at 8 and 18 mm",
    "mark": "Vine: without and with the running-head mark by the frame title (12 mm)",
    "minwidth": "Vine: the narrowest bands, 4 to 8 mm, and margins 25/10/8/12, in each scale",
    "vpapers": "Vine (clamped, pass, corner 0.5) on 16:9, 4:3 and A4, with and without a frame title",
    "cfix": "C corners and vine: as in ORDER #1 and fixed (no runners, vine into the arms)",
    "choice": "B vine as the default, and A, C and D at their best (16:9, 12 mm)",
}


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


SOLID_MM = 1.0  # mm: ink at least this thick reads as plant, not specks


def opened(mask, n):
    """The mask opened by an n x n square: what is left of the ink once
    every part thinner than n pixels is taken away."""
    def run(m, axis, op):
        out = m.copy()
        for k in range(1, n):
            sh = np.roll(m, -k, axis=axis)
            if axis == 0:
                sh[-k:, :] = False
            else:
                sh[:, -k:] = False
            out = op(out, sh)
        return out
    e = run(run(mask, 0, np.logical_and), 1, np.logical_and)
    # Dilation back, shifting the other way.
    def grow(m, axis):
        out = m.copy()
        for k in range(1, n):
            sh = np.roll(m, k, axis=axis)
            if axis == 0:
                sh[:k, :] = False
            else:
                sh[:, :k] = False
            out = out | sh
        return out
    return grow(grow(e, 0), 1)


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
    px_mm2 = PX_MM ** 2
    text_mm2 = float((a & inside).sum()) * px_mm2
    tb = box(r["title"])
    title_mm2 = 0.0
    if tb:
        tin = (X > tb[0]) & (X < tb[2]) & (Y > tb[1]) & (Y < tb[3])
        title_mm2 = float((a & tin).sum()) * px_mm2
    # Plant against specks: the share of the ink outside the text block at
    # least SOLID_MM thick (leaves, blooms and stems that read as such),
    # and that solid ink in mm2 per cm of the paper's edge.
    ink = a & ~inside
    solid = opened(ink, max(2, round(SOLID_MM / PX_MM))) & ink
    plant = float(solid.sum()) / max(1, int(ink.sum()))
    solid_per_cm = float(solid.sum()) * PX_MM ** 2 / (2 * (W + H) / MM / 10)
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
                     "text_mm2": f"{text_mm2:.1f}", "title_mm2": f"{title_mm2:.1f}",
                     "solid": f"{plant:.2f}", "solid_mm2_per_cm": f"{solid_per_cm:.1f}", "secs": r["secs"]})
    return rows


def summary(rows):
    groups = OrderedDict()
    for m in rows:
        groups.setdefault((m["row"], m["col"]), {}).setdefault(m["side"], []).append(m)
    lines = ["| page | | " + " | ".join(f"{s} near-far mm, cover (in band) %, beyond %" for s in SIDES) + " | text mm2 (title) | solid %, solid mm2/cm | s |",
             "|---|---|" + "---|" * len(SIDES) + "---|---|---|"]
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
        plant = np.mean([float(m["solid"]) for m in ms]) * 100
        specks = np.mean([float(m["solid_mm2_per_cm"]) for m in ms])
        secs = np.mean([float(m["secs"]) for m in ms])
        lines.append(f"| {row} | {col} (laid {laid:.1f}) | " + " | ".join(cells) + f" | {text:.1f} ({title:.1f}) | {plant:.0f}, {specks:.1f} | {secs:.1f} |")
    return "\n".join(lines) + "\n"


def font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default()


def tile(out, r, width):
    """The page as a tile `width` px wide, or its crop box enlarged to it."""
    W, H = float(r["W"]), float(r["H"])
    crop = box(r.get("crop", ""))
    k = width / ((crop[2] - crop[0]) if crop else W)
    dpi = 72 * k
    im = Image.open(render(out, r["file"], f"{dpi:.2f}", transparent=False)).convert("RGB")
    im = im.resize((round(W * k), round(H * k)))
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
    # The band as laid (the asked width, or less where a margin is narrower), dashed.
    b = float(r["band_pt"])
    pts = [(b, b), (W - b, b), (W - b, H - b), (b, H - b), (b, b)]
    for (x0, y0), (x1, y1) in pairwise(pts):
        n = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) * k / 8))
        for i in range(0, n, 2):
            u0, u1 = i / n, min(1, (i + 1) / n)
            dr.line([((x0 + (x1 - x0) * u0) * k, (H - (y0 + (y1 - y0) * u0)) * k),
                     ((x0 + (x1 - x0) * u1) * k, (H - (y0 + (y1 - y0) * u1)) * k)], fill="#c0392b", width=1)
    if crop:
        base = base.crop((round(crop[0] * k), round((H - crop[3]) * k), round(crop[2] * k), round((H - crop[1]) * k)))
        dr = ImageDraw.Draw(base)
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
    sheet(out, [r for r in pages if r["seed"] == pages[0]["seed"]], TITLES.get(title, title) or out.name)
    print(f"frame_flora: {out / 'measure.tsv'}, {out / 'summary.md'}, {out / 'sheet.png'}")


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: python3 -I tools/frame_flora.py OUTDIR [TITLE]")
    main(*sys.argv[1:])
