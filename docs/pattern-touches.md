# Pattern prototypes

Three prototypes of the pattern field sit behind keys of `spec.pattern_opts` (lua/flora/pattern_touches.lua), not settings, each off unless set.
A page without the keys is painted byte for byte as before (`just bodies-compare`), a value that is none of the key's is logged and left off, and a pattern that cannot give a key what it needs says so in the page's log and is painted without it.
Nothing here is a default: a variant is chosen from the sheets.

## Keys

`gold` says where the gold lies in the field: `core` (the band's core, accent and core both gold), `cells` (a few whole cells gilded, chosen by seed), `knobs` (a gold knob at the middle of every cell), `crossings` (a few glints where bands cross, chosen by seed) or `hero` (none in the field, the hero's lines in gold).
Every value but `core` takes the field's own gold out (the accent turns to the core's colour) so the variants do not add to gold that is there already; the hero, the border's rule and the frame keep the accent they had.

`deviant=true` turns at most one whole cell on each side of the text and paints it in another colour (the hue turned 150 degrees), its place drawn by seed.
`loose=true` moves one cell at the field's edge out beyond it, a little tilted, and draws a dotted path back to the gap it left.

The places are drawn from the page's seed on a stream of their own, so the same page and seed give the same places.
Cells with no tile to turn or middle to mark are listed in `NO_CELLS`, `NO_CENTRES` and `NO_CROSSINGS` with the reason.
In a perimeter band whose edge is whole rows each side is painted as a strip of its own, so the keys act once per side there.

## Sheets

`just pattern-touches OUT SET` (tools/pattern-touches.sh) bakes the layouts (tools/pattern-bake.sh: tex/lorem.tex and the 16:9 slide of tools/pattern-slide.tex), renders the variants of tools/pattern_variants.lua that carry that `set` with tools/pattern_roles.lua, and lays out OUT/sheets/:

- `gold`: per pattern, today's field and the five values side by side, field and hero, on paper and on the dark backdrop.
- `deviant` and `loose`: per pattern, three seeds, the whole 16:9 page and a close-up, off and on.
- `perimeter`: per pattern, the keys in a 12 mm band.
- `inventory`: inventory.tsv, one pattern a row: its roles, the field's ink, the gold's share of it and the places each key lays.

Under each tile stand the gold's share of the field's ink (pixels at 50 dpi more than half opaque; the gold is painted again as pure magenta, in `probe/`, and counted) and the places laid.
A new variant is a line in tools/pattern_variants.lua with `set`, `opts`, `seed` and the other fields tools/pattern_roles.lua lists; a new set needs a sheet function in tools/pattern-touches.sh.
