-- Squares of pattern drawn to stand beside the mocks (the t sheet of the
-- geometry study): each pattern or hero that has a mock, over the whole
-- square with no text, as many cells across as the mock shows.
--
--   texlua tools/mock_match.lua OUTDIR SETUP
--
-- SETUP is a \florasetup key list (colourway=fresco). Writes
-- OUTDIR/<mock>.pdf for each mock in MOCKS below.

package.path = "./lua/?.lua;" .. package.path
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Pdf = require("flora.pdfout")
local Settings = require("flora.settings")

local out, setup = assert(arg[1], "usage: mock_match.lua OUTDIR SETUP"), arg[2] or ""
-- mock, pattern or hero, the square's side in pt (as many cells as the
-- mock shows across).
local MOCKS = {
  { "t-01", "overlapping_circles", 110 }, { "t-03", "stars_8_4", 76 }, { "t-05", "penrose_rhombs", 240 },
  { "t-06", "truchet", 126 }, { "t-10", "sikku_kolam", 150 }, { "t-11", "asanoha", 117 },
  { "t-07", "hero=phyllotaxis", 200 }, { "t-08", "hero=rosette", 200 }, { "t-09", "hero=guilloche", 200 },
  { "t-13", "hero=rose", 200 },
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
  Paint.reset_resources()
  local pt = Compose.page(spec)
  Pdf.write(out .. "/" .. m[1] .. ".pdf", pt, side, side)
end
