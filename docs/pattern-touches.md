# Pattern touches: the sheets

The touches are four settings (`glint`, `herogilding`, `deviant`, `stray`; README, "Touches on a pattern field") laid by lua/flora/pattern_touches.lua.
This page is about the tools that draw them for comparison.

## Sheets

`just pattern-touches OUT SET` (tools/pattern-touches.sh) bakes the layouts (tools/pattern-bake.sh: tex/lorem.tex and the 16:9 slide of tools/pattern-slide.tex), renders the variants of tools/pattern_variants.lua that carry that `set` with tools/pattern_roles.lua, and lays out OUT/sheets/:

- `gold`: per pattern, today's field and `glint=on`, `core`, `cells`, `knobs` and `herogilding=on` side by side, field and hero, on paper and on the dark backdrop.
- `deviant`: per pattern, three seeds, the whole 16:9 page off, with `on` and with `3`, and a close-up of the first turned cell.
- `stray`: per pattern, three seeds, the whole 16:9 page and a close-up, off and on.
- `perimeter`: per pattern, a corner and a side of a 12 mm band, off and with each key (`deviant` on and as 3).
- `survey`: `just pattern-touches OUT survey` renders `stray=on` on the 16:9 slide over seeds 1 to 12 (the page's seed as the tools draw it) for stars_8_4, kikko, asanoha and overlapping_circles, with no pictures, and writes OUT/sheets/survey.tsv: per pattern the seeds that lay a plate and those that do not, the least and mean of how far the plate lies from its gap and from the nearest cell drawn (in cell widths; the limits are MIN_MOVE and MIN_CLEAR in lua/flora/pattern_touches.lua), and the log's line. About ten seconds.
- `inventory`: inventory.tsv, one pattern a row: its roles, the field's ink, the gold's share of it and the places each key lays.

Under each tile stand the gold's share of the field's ink (pixels at 50 dpi more than half opaque; the gold is painted again as pure magenta, in `probe/`, and counted) and the places laid.
OUT/render/SET/touches.tsv has each page's numbers and log (and, for a stray plate, how far it lies from the nearest cell and from its gap, in cell widths).
`PATTERN_TOUCHES_SHEETS_ONLY=1` lays out sheets from an earlier render.

A new variant is a line in tools/pattern_variants.lua with `set`, `setup` (the `\florasetup` keys), `seed` and the other fields tools/pattern_roles.lua lists; a new set needs a sheet function in tools/pattern-touches.sh.

## Tests

tests/test_pattern_touches.lua holds the settings and the unit checks; tests/pattern_touches_suite.lua, run on paper and on the dark backdrop by test_pattern_touches_matrix_1.lua and _2, holds each invariant over six patterns, a field and a perimeter band, and proves each fails when the module is broken.
