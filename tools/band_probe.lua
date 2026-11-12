-- Straps of rising width, drawn as the pattern bands are (pat_kit.lua's
-- K.band) and as they were before its contour and core limits (a core of
-- 0.45 of the width at any width), for comparing renderers.
--
--   texlua tools/band_probe.lua OUTDIR [SPEC]
--
-- Writes OUTDIR/probe.pdf and OUTDIR/probe.json (pdfout.lua's scene, as
-- the web renderer reads it): one row per width, the old rule on the
-- left and K.band on the right, a dark band with a paper core on paper.
-- OUTDIR/probe.tsv lists each row's width, the old and new core widths and
-- where each row's centre lies (bp from the page's foot). With SPEC (a
-- baked page, tools/pattern_audit.lua), OUTDIR/page.pdf and page.json are
-- that page filled with stars_8_4 in the ember colourway, its broad straps
-- as they are painted by default.

package.path = "./lua/?.lua;" .. package.path
local Paint = require("flora.paint")
local Pdf = require("flora.pdfout")
local K = require("flora.pat_kit")

local out = assert(arg[1], "usage: band_probe.lua OUTDIR [SPEC]")
local W, H = 200, 160
local WIDTHS = { 0.8, 1.0, 1.2, 1.5, 1.8, 2.2, 2.6, 3.2, 4.0 }
Paint.reset_resources()
local pt = Paint.new({ backend = "pdf" })
local band, paper = { 0.0, 0.13, 0.11 }, Paint.palette.paper
pt:fill({ { "m", 0, 0 }, { "l", W, 0 }, { "l", W, H }, { "l", 0, H }, { "z" } }, paper, 1)
local tsv = assert(io.open(out .. "/probe.tsv", "w"))
tsv:write("width\told_core\tnew_core\ty\n")
for i, w in ipairs(WIDTHS) do
  local y = H - 12 - (i - 1) * 16
  local left = { { "m", 10, y }, { "l", 95, y } }
  pt:stroke(left, band, w, 1)
  pt:stroke(left, paper, w * 0.45, 1)
  -- The new rule, through the strap K.band paints.
  local ink = { band = band, core = paper, width = w, bands = "strap", corefrac = 0.45 }
  local right = { { "m", 105, y }, { "l", 190, y } }
  local strokes = {}
  local probe = setmetatable({ stroke = function(_, p, c, sw) strokes[#strokes + 1] = sw; pt:stroke(p, c, sw, 1) end }, { __index = pt })
  K.band(probe, right, ink)
  tsv:write(string.format("%.2f\t%.2f\t%.2f\t%.2f\n", w, w * 0.45, strokes[2] or 0, y))
end
tsv:close()
Pdf.write(out .. "/probe.pdf", pt, W, H)
local f = assert(io.open(out .. "/probe.json", "w"))
f:write(Pdf.scene(pt, W, H))
f:close()

if arg[2] then
  local Serial, Settings, Compose = require("flora.serial"), require("flora.settings"), require("flora.compose")
  local fh = assert(io.open(arg[2]))
  local spec = Serial.decode(fh:read("a"))
  fh:close()
  spec.seed = require("flora.init").seed("11", 4)
  Settings.to_spec(Settings.merge(Settings.from_spec(spec, Settings.fresh_keys()), Settings.parse("pattern=stars_8_4, colourway=ember")), spec)
  spec.layout = "left"
  Paint.reset_resources()
  local page = Compose.page(spec)
  Pdf.write(out .. "/page.pdf", page, spec.width, spec.height)
  local g = assert(io.open(out .. "/page.json", "w"))
  g:write(Pdf.scene(page, spec.width, spec.height))
  g:close()
end
