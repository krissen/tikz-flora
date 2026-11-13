-- Renders every pattern filled, with the ground off and on, for each edge
-- mode, on the mixer's left page, and records how its field ends, for
-- tools/edge_measure.py to measure.
--
--   texlua tools/edge_measure.lua SPECDIR OUTDIR [SETUP]
--
-- Writes OUTDIR/<pattern>__ground-<off|on>__<edge>.pdf and OUTDIR/cells.tsv:
-- per page the cells kept, the cells at the field's edge (a neighbour on
-- the page not in the field) and those isolated (no neighbour in the
-- field), as pattern.lua's M.field_edges counts them, and the text block's
-- left edge in pt.

package.path = "./lua/?.lua;" .. package.path
local Serial = require("flora.serial")
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Init = require("flora.init")
local Pdf = require("flora.pdfout")
local Settings = require("flora.settings")
local Patterns = require("flora.patterns")

local specdir, out, setup = arg[1], arg[2], arg[3] or "colourway=tsuki-mi"
assert(specdir and out, "usage: edge_measure.lua SPECDIR OUTDIR [SETUP]")
local tsv = assert(io.open(out .. "/cells.tsv", "w"))
tsv:write("pattern\tground\tedge\tkept\tedge_cells\tisolated\ttext_x0\twidth\theight\tsize\n")
for _, p in ipairs(Patterns.list) do
  for _, ground in ipairs({ "off", "on" }) do
    for _, edge in ipairs({ "dissolve", "cell", "fade", "border" }) do
      local f = assert(io.open(specdir .. "/spec-4.lua"))
      local spec = Serial.decode(f:read("a"))
      f:close()
      spec.seed = Init.seed("11", 4)
      local own = Settings.from_spec(spec, Settings.fresh_keys())
      own.layout = "left"
      Settings.to_spec(Settings.merge(own, Settings.parse("pattern=" .. p.name .. ", edge=" .. edge .. ", ground=" .. ground .. ", " .. setup)), spec)
      spec.layout = "left"
      spec.ornaments = {}
      spec.pattern_opts = { measure = true }
      Paint.reset_resources()
      local pt = Compose.page(spec)
      Pdf.write(string.format("%s/%s__ground-%s__%s.pdf", out, p.name, ground, edge), pt, spec.width, spec.height)
      local q = pt.pattern
      tsv:write(table.concat({ p.name, ground, edge, q.cells, q.edge_cells, q.isolated, string.format("%.1f", spec.text.x0),
        string.format("%.1f", spec.width), string.format("%.1f", spec.height), p.scale }, "\t") .. "\n")
    end
  end
end
tsv:close()
