-- Squares of pattern drawn to stand beside the mocks (the geometry study's
-- sheets): each pattern or hero that has a mock, over the whole square
-- with no text, as many cells across as the mock shows, so mock and engine
-- compare at the same crop and scale.
--
--   texlua tools/mock_match.lua OUTDIR SETUP
--
-- SETUP is a \florasetup key list (colourway=tsuki-mi). Writes
-- OUTDIR/<name>.pdf for each entry in MOCKS below.

package.path = "./lua/?.lua;" .. package.path
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Pdf = require("flora.pdfout")
local Settings = require("flora.settings")

local out, setup = assert(arg[1], "usage: mock_match.lua OUTDIR SETUP"), arg[2] or ""
-- The output's name, the pattern or hero, the square's side in pt (as
-- many cells as the mock shows across), and prototype options
-- (pattern.lua's pattern_opts). The sides of the y and f mocks come from
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
  { "y-03", "khatam", 172 }, { "y-03__mock", "khatam", 172, { khatam = "mock" } },
  { "y-04", "greek_crosses", 176 }, { "y-06", "celtic_panels", 129 }, { "y-08", "celtic_knot", 129 },
  { "f-14", "rosette_lattice", 87 },
}
for _, m in ipairs(MOCKS) do
  local side = m[3]
  local hero = m[2]:match("^hero=(.*)")
  local spec = { width = side, height = side, seed = 7, layout = "surround",
    -- A text block of a point in the corner, so the field takes the square.
    text = { x0 = side - 1, y0 = 0, x1 = side, y1 = 1 } }
  local line = (hero and "pattern=stars_8_4, hero=" .. hero .. ", outer=margin, density=0" or "pattern=" .. m[2] .. ", density=10, edge=cell")
    .. (setup ~= "" and ", " .. setup or "")
  Settings.to_spec(Settings.merge(Settings.from_spec(spec), Settings.parse(line)), spec)
  spec.mix = spec.mix or {}
  spec.pattern_opts = m[4]
  Paint.reset_resources()
  local pt = Compose.page(spec)
  Pdf.write(out .. "/" .. m[1] .. ".pdf", pt, side, side)
end
