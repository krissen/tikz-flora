"""How far two renderings of a page differ, in pixels.

    python3 -I tools/page_diff.py A.pdf B.pdf [DPI] [OUT.png]

Rasterises the first page of each PDF at DPI (default 300) with pdftocairo
and prints, on one line: the share of pixels whose colour differs at all,
the share that differs by more than 8 of 255 in some channel (what a reader
might see), and the largest difference in any channel (0 to 255). With
OUT.png it also writes the difference, amplified, for looking at. The pages
must have the same size. Needs numpy and Pillow.
"""
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import toolproc

SEEN = 8


def raster(pdf, dpi, tmp, name):
    out = Path(tmp) / name
    toolproc.run(["pdftocairo", "-png", "-singlefile", "-r", str(dpi), "-f", "1", "-l", "1", str(pdf), str(out)], check=True)
    return np.asarray(Image.open(str(out) + ".png").convert("RGB")).astype(np.int16)


def main(argv):
    toolproc.install()
    if len(argv) not in (2, 3, 4):
        print("usage: python3 -I tools/page_diff.py A.pdf B.pdf [DPI] [OUT.png]")
        return 2
    for f in argv[:2]:
        if not Path(f).is_file():
            print(f"page_diff: no file {f}")
            return 2
    if len(argv) > 2 and not argv[2].isdigit():
        print(f"page_diff: DPI must be a whole number, not {argv[2]}")
        return 2
    dpi = int(argv[2]) if len(argv) > 2 else 300
    with tempfile.TemporaryDirectory() as tmp:
        try:
            a, b = raster(argv[0], dpi, tmp, "a"), raster(argv[1], dpi, tmp, "b")
        except toolproc.subprocess.CalledProcessError as e:
            print(f"page_diff: pdftocairo could not read a page: {e.stderr or e}")
            return 2
    if a.shape != b.shape:
        print(f"page_diff: the pages differ in size, {a.shape[1]}x{a.shape[0]} and {b.shape[1]}x{b.shape[0]}")
        return 1
    d = np.abs(a - b).max(axis=2)
    n = d.size
    print(f"changed {np.count_nonzero(d) / n:.5%}  seen (>{SEEN}) {np.count_nonzero(d > SEEN) / n:.5%}  largest {int(d.max())}  at {dpi} dpi")
    if len(argv) > 3:
        Image.fromarray(np.clip(255 - d * 8, 0, 255).astype(np.uint8)).save(argv[3])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
