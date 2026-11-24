"""How much of a filled pattern's field is fill and how much is band, on
the pages tools/edge_measure.lua renders (ground off, edge=cell).

    python3 -I tools/form_measure.py OUTDIR [BAND_L]

Rasterises each page at 100 dpi, takes a square well inside the field
(15 to 115 pt across, the middle of the page's height) and sorts its
pixels by OKLab lightness: the paper (L above 0.93), the band (darker
than BAND_L, default 0.40, set it between the colourway's band and its
fields) and the fill (the rest). Writes OUTDIR/form.tsv: the shares of
each, fill over band, and the fill's mean lightness against the band's,
so a pattern whose fill outweighs its lines stands out. Needs numpy and
Pillow.
"""
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import toolproc

DPI = 100


def lightness(rgb):
    c = rgb / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    l = np.cbrt(0.4122214708 * c[..., 0] + 0.5363325363 * c[..., 1] + 0.0514459929 * c[..., 2])
    m = np.cbrt(0.2119034982 * c[..., 0] + 0.6806995451 * c[..., 1] + 0.1073969566 * c[..., 2])
    s = np.cbrt(0.0883024619 * c[..., 0] + 0.2817188376 * c[..., 1] + 0.6299787005 * c[..., 2])
    return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s


def main(out, band_l=0.40):
    toolproc.install()
    out = Path(out)
    with open(out / "cells.tsv") as f:
        rows = [r for r in csv.DictReader(f, delimiter="\t") if r["ground"] == "off" and r["edge"] == "cell"]
    res = []
    for r in rows:
        name = f"{r['pattern']}__ground-off__cell"
        toolproc.run(["pdftocairo", "-png", "-singlefile", "-r", str(DPI), str(out / (name + ".pdf")), str(out / ("form-" + name))], check=True)
        img = np.asarray(Image.open(str(out / ("form-" + name)) + ".png").convert("RGB")).astype(float)
        px = DPI / 72.27
        h = img.shape[0]
        y0 = int(h / 2 - 50 * px)
        crop = img[y0:y0 + int(100 * px), int(15 * px):int(115 * px)]
        L = lightness(crop)
        paper = np.mean(L > 0.93)
        bandm = L < band_l
        fillm = ~bandm & (L <= 0.93)
        band = np.mean(bandm)
        fill = np.mean(fillm)
        res.append({"pattern": r["pattern"], "paper": f"{paper:.2f}", "band": f"{band:.2f}", "fill": f"{fill:.2f}",
                    "fill_over_band": f"{fill / max(band, 1e-3):.1f}",
                    "fill_L": f"{L[fillm].mean():.2f}" if fillm.any() else "",
                    "band_L": f"{L[bandm].mean():.2f}" if bandm.any() else ""})
    with open(out / "form.tsv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(res[0].keys()), delimiter="\t")
        w.writeheader()
        w.writerows(res)
    for x in res:
        print("\t".join(x.values()))


if __name__ == "__main__":
    main(sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 0.40)
