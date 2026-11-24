"""How a pattern's field ends against the page, measured on the pages
tools/edge_measure.lua renders.

    python3 -I tools/edge_measure.py OUTDIR

Rasterises each page (pdftocairo, 40 dpi, transparent where nothing is
painted), takes the left margin up to the text block, and per page writes
OUTDIR/edge.tsv with: ragged, the length of the field's edge (each row's
rightmost painted pixel, top to bottom) over the length of the same edge
smoothed over three cells, so 1 is a smooth edge and more is a stair or
a fringe; steps, how many times per cell of height the edge jumps by
more than 0.4 of a cell (a square stair jumps about once a cell); and
fragments, the painted pieces cut off from the field smaller than a
cell. Needs numpy and Pillow.
"""
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import toolproc

DPI = 40


def components(mask):
    """Sizes of the 4-connected components of a boolean mask."""
    h, w = mask.shape
    label = np.zeros((h, w), dtype=np.int32)
    sizes = []
    for y in range(h):
        for x in range(w):
            if mask[y, x] and not label[y, x]:
                n = len(sizes) + 1
                stack, size = [(y, x)], 0
                label[y, x] = n
                while stack:
                    cy, cx = stack.pop()
                    size += 1
                    for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not label[ny, nx]:
                            label[ny, nx] = n
                            stack.append((ny, nx))
                sizes.append(size)
    return sizes


def main(out):
    toolproc.install()
    out = Path(out)
    with open(out / "cells.tsv") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    res = []
    for r in rows:
        name = f"{r['pattern']}__ground-{r['ground']}__{r['edge']}"
        png = out / name
        toolproc.run(["pdftocairo", "-png", "-transp", "-singlefile", "-r", str(DPI), str(out / (name + ".pdf")), str(png)], check=True)
        a = np.asarray(Image.open(str(png) + ".png").convert("RGBA"))[:, :, 3] > 20
        px = DPI / 72.27
        x1 = int(float(r["text_x0"]) * px)
        m = a[:, :x1]
        cell = float(r["size"]) * px
        rowsp = np.where(m.any(axis=1))[0]
        if len(rowsp) < 2:
            res.append({**r, "ragged": "", "steps": "", "fragments": ""})
            continue
        e = np.array([np.max(np.where(m[y])[0]) for y in rowsp], dtype=float)
        win = max(3, round(3 * cell))
        k = np.ones(win) / win
        s = np.convolve(np.pad(e, win // 2, mode="edge"), k, mode="same")[win // 2: win // 2 + len(e)]
        length = np.sum(np.sqrt(1 + np.diff(e) ** 2))
        smooth = np.sum(np.sqrt(1 + np.diff(s) ** 2))
        sizes = components(m)
        frag = sum(1 for z in sizes if z < cell * cell)
        steps = np.sum(np.abs(np.diff(e)) > 0.4 * cell) / max(1.0, len(e) / cell)
        res.append({**r, "ragged": f"{length / smooth:.2f}", "steps": f"{steps:.2f}", "fragments": frag})
    with open(out / "edge.tsv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(res[0].keys()), delimiter="\t")
        w.writeheader()
        w.writerows(res)


if __name__ == "__main__":
    main(sys.argv[1])
