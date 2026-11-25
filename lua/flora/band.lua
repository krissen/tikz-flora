-- The perimeter band: a geometric pattern as a band round the paper's edge,
-- the same width on all four sides (pattern.lua draws it). This module
-- holds what users write for it and what each pattern does in it, so that
-- settings.lua, frames.lua, compose.lua and pattern.lua read them from one
-- place.

local M = {}

-- The names users write: the layout value, the key for the band's width
-- in mm, and the edge value for whole rows. Renaming one changes it here.
M.LAYOUT = "perimeter"
M.WIDTH = "perimeterwidth"
M.ROWS = "rows"

-- The band's width in mm: its default and the range the key takes.
M.WIDTH_DEFAULT = 12
M.WIDTH_MIN, M.WIDTH_MAX = 4, 40

-- How the band ends toward the text, by the edge key's value:
--   border    cut along a straight inner edge, with a rule there
--   cell      whole cells, each wholly inside the band
--   fade      whole cells paling into the paper toward the inner edge
--   dissolve  the band whole, its cells falling away past its inner edge
--             into the margin before the text
--   rows      whole rows: cells sized so that a whole number of the
--             pattern's repeats fills the band, ending on its inner edge
-- guilloche has no form in a band: the pattern's own edge is used, and the
-- log says so.
M.EDGES = { border = "border", cell = "cell", fade = "fade", dissolve = "dissolve", [M.ROWS] = "rows" }

-- Each pattern's edge in a band when the page sets none: whole rows for
-- the patterns whose rows end in a straight edge of whole cells (asanoha,
-- stars_8_4) and for celtic_knot, whose rows are its closed plait,
-- filling the band and running off the paper's edge with it; a
-- straight edge with a rule for every other (truchet's arcs close against
-- the rule).
M.DEFAULT_EDGE = { asanoha = M.ROWS, celtic_knot = M.ROWS, stars_8_4 = M.ROWS }
M.EDGE = "border"

-- The narrowest band in mm a pattern carries; a narrower one is drawn all
-- the same, and the log says so. math.huge: none (penrose_rhombs has no
-- repeat, and a band shows only fragments of it).
M.NARROWEST = { penrose_rhombs = math.huge, khatam = 12, hexagram_lattice = 12 }

-- Flora in a perimeter band (frames.lua's M.vine): the key choosing its
-- form and the forms it names, the first the default. vine is one vine
-- round all four sides; pinwheel and corners are named for later and laid
-- as vine for now, which the log says.
M.FLORA = "perimeterflora"
M.FLORAS = { "vine", "pinwheel", "corners" }
M.FLORA_BUILT = { vine = true }
-- The narrowest band in mm flora is laid in: under it the band has no
-- flora, and the log says so.
M.FLORA_NARROWEST = 6
-- How flora meets the band's inner edge, by the edge key: border cuts it
-- along the edge with a rule there; any other value, or none, cuts it
-- there softly, without a rule.
M.FLORA_RULE = "border"

-- Pattern `name`'s edge in a band when the page sets none.
function M.default_edge(name)
  return M.DEFAULT_EDGE[name] or M.EDGE
end

return M
