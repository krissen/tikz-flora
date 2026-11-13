-- Squares of pattern drawn to stand beside the mocks (the geometry study's
-- sheets): each pattern or hero that has a mock, over the whole square
-- with no text, as many cells across as the mock shows, so mock and engine
-- compare at the same crop and scale.
--
--   texlua tools/mock_match.lua OUTDIR SETUP [ONLY]
--
-- SETUP is a \florasetup key list (colourway=tsuki-mi). Writes
-- OUTDIR/<name>.pdf for each entry in MOCKS below, or only for the names
-- ONLY lists (comma-separated).

package.path = "./lua/?.lua;" .. package.path
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Pdf = require("flora.pdfout")
local Settings = require("flora.settings")

local out, setup = assert(arg[1], "usage: mock_match.lua OUTDIR SETUP [ONLY]"), arg[2] or ""
local only
if arg[3] and arg[3] ~= "" then
  only = {}
  for n in arg[3]:gmatch("[^,]+") do only[n] = true end
end
-- The output's name, the pattern or hero, the square's side in pt (as
-- many cells as the mock shows across), prototype options (pattern.lua's
-- pattern_opts) and settings of its own after SETUP. The sides of the y and f mocks come from
-- their measured periods: y-02 6.15 periods of hexagram's 30 pt, y-03
-- 6.15 of khatam's 28, y-04 14.65 arm widths of the crosses' 12, y-06 and
-- y-08 8 grid units of the knotwork's 16, f-14 (its pattern, 182 px
-- square) 2.9 periods of the rosettes' 30. t-05 is 400 pt: measured on
-- the mock, its rhombs' edge is 1.65 times shorter than the 240 pt the
-- first sheet gave.
local MOCKS = {
  { "t-01", "overlapping_circles", 110 }, { "t-03", "stars_8_4", 76 }, { "t-05", "penrose_rhombs", 400 },
  { "t-06", "truchet", 126 }, { "t-10", "sikku_kolam", 150 }, { "t-11", "asanoha", 117 },
  { "t-07", "hero=phyllotaxis", 200 }, { "t-08", "hero=rosette", 200 }, { "t-09", "hero=guilloche", 200 },
  { "t-13", "hero=rose", 200 },
  { "y-02", "hexagram_lattice", 184 }, { "y-02__measured", "hexagram_lattice", 184, { hexagram = "measured" } },
  { "y-03", "khatam", 172 },
  { "y-03__two", "khatam", 172, { khatam = "two" } }, { "y-03__one", "khatam", 172, { khatam = "one" } },
  { "y-03__paper", "khatam", 172, { khatam = "paper" } }, { "y-03__dot", "khatam", 172, { khatam = "dot" } },
  { "y-04", "greek_crosses", 176 }, { "y-06", "celtic_panels", 129 }, { "y-08", "celtic_knot", 129 },
  { "f-14", "rosette_lattice", 87 },
  -- ORDER #12. Hexagram in a large crop, three periods across, every star
  -- one colour.
  { "y-02__big", "hexagram_lattice", 90 },
  { "y-02__big-star-thin", "hexagram_lattice", 90, { hexagram = "star-thin" } },
  { "y-02__big-plain", "hexagram_lattice", 90, { hexagram = "plain" } },
  { "y-02__big-rows", "hexagram_lattice", 90, { hexagram = "rows" } },
  { "y-02__big-three", "hexagram_lattice", 90, { hexagram = "three" } },
  { "y-02__big-lines", "hexagram_lattice", 90, { hexagram = "plain" }, "finish=lines" },
  -- The knot panels: y-06 and y-08 are 278 px, 8.97 of their 31 px units.
  { "y-06__panel", "celtic_panels", 144 }, { "y-08__panel", "celtic_knot", 144 },
  { "y-06__one", "celtic_panels", 144, { knot = "one", reweave = false, units = true } },
  { "y-08__one", "celtic_knot", 144, { knot = "one", reweave = false, units = true } },
  -- The two new heroes beside the two they are not to be taken for.
  { "t-09__new", "hero=turned_circles", 200 }, { "t-01__new", "hero=circle_disc", 200 },
  -- Asanoha on a ground, in thin gold lines.
  { "t-11__gold", "asanoha", 117, nil, "ground=panel, bands=line, bandwidth=0.5, patternpalette={band=gold}" },
}
for _, m in ipairs(MOCKS) do
  if only and not only[m[1]] then goto skip end
  local side = m[3]
  local hero = m[2]:match("^hero=(.*)")
  local spec = { width = side, height = side, seed = 7, layout = "surround",
    -- A text block of a point in the corner, so the field takes the square.
    text = { x0 = side - 1, y0 = 0, x1 = side, y1 = 1 } }
  local line = (hero and "pattern=stars_8_4, hero=" .. hero .. ", outer=margin, density=0" or "pattern=" .. m[2] .. ", density=10, edge=cell")
    .. (setup ~= "" and ", " .. setup or "") .. (m[5] and ", " .. m[5] or "")
  Settings.to_spec(Settings.merge(Settings.from_spec(spec), Settings.parse(line)), spec)
  spec.mix = spec.mix or {}
  spec.pattern_opts = m[4]
  Paint.reset_resources()
  local pt = Compose.page(spec)
  Pdf.write(out .. "/" .. m[1] .. ".pdf", pt, side, side)
  ::skip::
end
