"""Optional integration test: texlua, pdftoppm and Pillow required.

Run python3 tests/test_progression_raster.py from the repository root.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import tempfile
import time

from PIL import Image, ImageChops

LUA = r"""
package.path='./lua/?.lua;'..package.path
local P=require('flora.progression')
local PDF=require('flora.pdfout')
local prefix=arg[1]
local s={width=360,height=270,text={x0=65,y0=35,x1=295,y1=235},seed=7,
  layout='centered',mix={gyps=0,cyme=0,umbel=0,ghost=0},
  tune={compose={sprays=0,leaves=2,small_blooms=1,curls=0,no_leaflets=true}}}
local p=P.plan(s)
assert(#P.stages(p,64)==64)
for i=0,64 do
  PDF.write(string.format('%s-%02d.pdf',prefix,i),P.render(p,i/64),s.width,s.height)
end
PDF.write(prefix..'-ordinary.pdf',p.final,s.width,s.height)
local names={}
for i,part in ipairs(p.parts) do names[i]=part.form; part.form=nil end
local unfactored=P.render(p,.5); unfactored.xobjects=nil
PDF.write(prefix..'-unfactored.pdf',unfactored,s.width,s.height)
for i,part in ipairs(p.parts) do part.form=names[i] end
s.reserve={{15,80,55,100},{30,90,70,110}}
local protected=P.plan(s)
PDF.write(prefix..'-protected.pdf',P.render(protected,.5),s.width,s.height)
print(string.format('%d parts; %.1f pt2; Lua memory %.1f MiB',#p.parts,p.area,collectgarbage('count')/1024))
"""


def raster(path):
    subprocess.run(
        ['pdftoppm', '-r', '72', '-singlefile', '-png', str(path), str(path.with_suffix(''))],
        check=True, capture_output=True,
    )
    with Image.open(path.with_suffix('.png')) as image:
        return image.convert('RGB')


def pixels(image):
    # Pillow 13 deprecates getdata; Ubuntu's packaged Pillow predates its
    # replacement. Support both for the optional test and CI.
    return image.get_flattened_data() if hasattr(image, 'get_flattened_data') else image.getdata()


def painted(image):
    return sum(min(pixel) < 245 for pixel in pixels(image))


def main():
    start = time.monotonic()
    with tempfile.TemporaryDirectory(prefix='flora-growth-') as directory:
        root = Path(directory)
        script = root / 'stages.lua'
        script.write_text(LUA)
        prefix = root / 'stage'
        subprocess.run(['texlua', str(script), str(prefix)], check=True)
        paths = [root / f'stage-{i:02d}.pdf' for i in range(65)]
        with ThreadPoolExecutor(max_workers=4) as pool:
            images = list(pool.map(raster, paths))
        changes = [sum(max(pixel) > 3 for pixel in pixels(ImageChops.difference(a, b)))
                   for a, b in zip(images, images[1:])]
        assert min(changes) > 0, 'a stage failed to change visible pixels'
        areas = list(map(painted, images))
        assert areas[0] == 0, 'zero progression paints visible content'
        errors = [abs(area / areas[-1] - i / 64) for i, area in enumerate(areas)]
        assert max(errors) < .10, f'painted area deviates by {max(errors):.3f}'
        unfactored = raster(root / 'stage-unfactored.pdf')
        difference = ImageChops.difference(unfactored, images[32])
        differences = list(pixels(difference))
        # Poppler can antialias a Form's clip differently from a page path.
        # Bound both the peak change and the total pixel error.
        assert max(map(max, differences)) <= 32, 'XObject factoring changed painting'
        assert sum(sum(pixel) for pixel in differences) / (3 * len(differences)) < .05, 'XObject raster error too large'
        ordinary = raster(root / 'stage-ordinary.pdf')
        assert ImageChops.difference(ordinary, images[-1]).getbbox() is None, 'final composition changed'
        protected = raster(root / 'stage-protected.pdf')
        # The interior of each exclusion is white, including their overlap.
        bp = 72 / 72.27
        for x0, y0, x1, y1 in [(15, 80, 55, 100), (30, 90, 70, 110), (65, 35, 295, 235)]:
            region = protected.crop((int(x0 * bp) + 2, int((270 - y1) * bp) + 2,
                                     int(x1 * bp) - 2, int((270 - y0) * bp) - 2))
            assert painted(region) == 0, 'intermediate growth crossed fixed protection'
        size = sum(path.stat().st_size for path in paths)
        print(f'progression raster: 64 distinct transitions; minimum {min(changes)} changed pixels; '
              f'max area error {max(errors):.3f}; PDFs {size / 1024**2:.1f} MiB; '
              f'{time.monotonic() - start:.1f}s')


if __name__ == '__main__':
    main()
