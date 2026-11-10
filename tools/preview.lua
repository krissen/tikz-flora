-- Draws one page's flora without TeX, for fast previews.
--
--   texlua tools/preview.lua SPEC SEED PAGE OUT.pdf [T] [SETTINGS]
--
-- SPEC is a layout written during a real compile with FLORA_SPEC_DIR set
-- (page size, text block and measured lines). The flora is grown exactly as
-- in that compile, for document seed SEED on page PAGE, and written as a
-- one-page PDF holding the flora alone; the text comes from that compile's
-- own pages. SEED "doc" takes the seed the document itself set. With T
-- (0-1) the flora is drawn as grown at that time (clock.lua), for "watch it
-- grow" frames; "-" or 1 draws the finished page. SETTINGS is a
-- \florasetup key list (any key that reaches a page: mix, palette, spin,
-- density, visitors, layout, header, ornaments, gilt, giltdpi, giltenv,
-- giltlook, backdrop, pattern, edge, outer, scale; see Settings.SPEC),
-- applied over the page's own. Two words in it are not settings: "fresh"
-- drops the page's own mix, palette, spin and tune first, as the site's
-- mixer does, and
-- "noheader" drops the running-head rule, for a picture of the flora alone. FLORA_TUNE applies as usual. Run
-- from the repository root.

package.path = "./lua/?.lua;" .. package.path
local Serial = require("flora.serial")
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Init = require("flora.init")
local Pdf = require("flora.pdfout")
local Settings = require("flora.settings")

local spec_path, seed, page, out, T, extra = arg[1], arg[2], tonumber(arg[3]), arg[4], tonumber(arg[5]), arg[6]
assert(spec_path and seed and page and out, "usage: preview.lua SPEC SEED PAGE OUT.pdf")
local f = assert(io.open(spec_path))
local spec = Serial.decode(f:read("a"))
f:close()
spec.seed = Init.spec_seed(spec, seed, page)
spec.grow = T
if extra then
  local flags = {}
  for _, word in ipairs({ "noheader", "fresh" }) do
    extra = extra:gsub("%f[%w]" .. word .. "%f[%W],?%s*", function() flags[word] = true return "" end)
  end
  -- "fresh" drops the page's own mix, palette, spin and tune, keeping its
  -- gilt, backdrop, ornaments and pattern.
  local own = Settings.from_spec(spec, flags.fresh
    and { gilt = true, giltdpi = true, giltenv = true, giltlook = true, backdrop = true, ornaments = true,
      pattern = true, edge = true, outer = true, scale = true } or nil)
  own.layout, own.header = spec.layout, spec.header
  local set = Settings.merge(own, Settings.parse(extra))
  local noheader = flags.noheader
  Settings.to_spec(set, spec)
  spec.layout = set.layout
  spec.header = set.header or spec.header
  if noheader then spec.header_y = nil end
end

Paint.reset_resources()
local pt = Compose.page(spec)
Pdf.write(out, pt, spec.width, spec.height)
