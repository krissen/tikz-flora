-- Renders every registered pattern (patterns.lua) in every role it takes
-- on a page, for a set of palettes, as one-page PDFs for contact sheets
-- (tools/pattern-audit.sh lays them out).
--
--   texlua tools/pattern_audit.lua SPECDIR OUTDIR [ONLY]
--
-- SPECDIR holds the layouts a compile of tex/lorem.tex wrote with
-- FLORA_SPEC_DIR set (spec-N.lua), the same files `just site-bake` copies
-- to site/public/bake for the mixer. Each page is built as the mixer's
-- render worker builds it (site/src/lib/render.worker.js): the baked
-- spec, the mixer's seed and page, its layout, mix, palette, backdrop and
-- the pattern keys that worker passes on (pattern, edge, outer, scale).
-- The hero is a \florasetup key the worker does not pass, so the hero
-- roles are built as tools/preview.lua builds a page for TeX
-- (Settings.to_spec), and the "parity" role builds a few pages both ways
-- to show whether the two paths paint the same. ONLY, if given, limits the
-- run to the roles named in it (comma-separated).
--
-- Writes OUTDIR/<role>/<palette>/<pattern>.pdf and OUTDIR/index.tsv: one
-- row per page with the role, palette, pattern, cells kept and offered,
-- painted objects, milliseconds, and the error if it failed.

package.path = "./lua/?.lua;" .. package.path
local Serial = require("flora.serial")
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Init = require("flora.init")
local Pdf = require("flora.pdfout")
local Settings = require("flora.settings")
local Patterns = require("flora.patterns")
local Inks = require("flora.inks")
local Tune = require("flora.tune")

local specdir, outdir, only = arg[1], arg[2], arg[3]
assert(specdir and outdir, "usage: pattern_audit.lua SPECDIR OUTDIR [ONLY]")

-- The mixer's pages (just site-bake's manifest.json) and its first
-- colourway's seed (site/src/lib/colourways.json), which it opens on.
local PAGES = { left = 4, right = 3, centered = 6, title = 1, surround = 2 }
local SEED = 11

-- The mixer's palette: every part at its default (tune.lua), then a
-- colourway's inks over them, as Mixer.svelte sets it.
local function colourway(name)
  local p = {}
  for k, v in pairs(Tune.color.palette) do p[k] = v end
  for k, v in pairs(Inks.colourways[name] or {}) do p[k] = v end
  return p
end

-- light: the mixer's opening colourway on paper; look: flora's own navy,
-- gold and sky; accent: a colourway with a strong warm accent; dark: the
-- opening colourway on the dark backdrop.
local PALETTES = {
  { "light", colourway("ember"), "light" },
  { "look", colourway("original"), "light" },
  { "accent", colourway("autumn"), "light" },
  { "dark", colourway("ember"), "dark" },
}

-- The roles: the layout's page, and the pattern keys as \florasetup
-- writes them. `tex` builds the page the TeX way (for keys the mixer
-- does not pass).
local ROLES = {
  { "field-left", "left", "" },
  { "field-right", "right", "" },
  { "field-centered", "centered", "" },
  { "field-surround", "surround", "" },
  { "field-title", "title", "" },
  { "edge-cell", "left", "edge=cell" },
  { "edge-fade", "left", "edge=fade" },
  { "edge-border", "left", "edge=border" },
  { "edge-guilloche", "left", "edge=guilloche" },
  { "outer-margin", "left", "outer=margin" },
  { "density-0.5", "left", "", { density = 0.5 } },
  { "density-3", "left", "", { density = 3 } },
  { "hero-rosette", "right", "hero=rosette", nil, true },
  { "hero-phyllotaxis", "right", "hero=phyllotaxis", nil, true },
  { "hero-rose", "right", "hero=rose", nil, true },
  { "hero-guilloche", "right", "hero=guilloche", nil, true },
  { "hero-rosette-margin", "right", "hero=rosette, outer=margin", nil, true },
}

local wanted
if only and only ~= "" then
  wanted = {}
  for r in only:gmatch("[^,]+") do wanted[r] = true end
end

local function load(page)
  local f = assert(io.open(specdir .. "/spec-" .. page .. ".lua"))
  local s = Serial.decode(f:read("a"))
  f:close()
  return s
end

-- The page as the mixer's worker builds it (render.worker.js): its seed
-- for the page, the layout, mix, ornaments, palette, spin, gilt and
-- backdrop, and the pattern keys it parses from the setup line.
local function mixer_spec(layout, keys, mix, palette, backdrop)
  local page = PAGES[layout]
  local spec = load(page)
  spec.seed = Init.seed(tostring(SEED), page)
  spec.layout = layout
  spec.mix = mix or {}
  spec.ornaments = {}
  spec.palette = palette
  spec.spin = 0
  spec.gilt = "raster"
  spec.gilt_env = "studio"
  spec.gilt_look = Settings.parse("giltlook={}").giltlook
  spec.backdrop = Settings.parse("backdrop=" .. backdrop).backdrop
  local ps = Settings.parse(keys)
  spec.pattern, spec.pattern_edge, spec.pattern_outer, spec.pattern_scale = ps.pattern, ps.edge, ps.outer, ps.scale
  spec.gilt_dpi = 150
  return spec
end

-- The same page as tools/preview.lua builds it for TeX with "fresh": the
-- page's own settings but its mix, palette, spin and tune, then the keys.
local function tex_spec(layout, keys, mix, palette, backdrop)
  local page = PAGES[layout]
  local spec = load(page)
  spec.seed = Init.spec_seed(spec, tostring(SEED), page)
  local own = Settings.from_spec(spec, Settings.fresh_keys())
  own.layout, own.header = layout, spec.header
  local set = Settings.merge(own, Settings.parse(keys))
  set.mix = mix
  set.palette = palette
  set.backdrop = Settings.parse("backdrop=" .. backdrop).backdrop
  Settings.to_spec(set, spec)
  spec.layout = set.layout
  return spec
end

local function mkdir(p) os.execute("mkdir -p '" .. p .. "'") end

local index = assert(io.open(outdir .. "/index.tsv", "w"))
index:write("role\tpalette\tpattern\tkept\toffered\tobjects\tms\terror\n")

local function render(role, pal, name, spec, file)
  Paint.reset_resources()
  local t0 = os.clock()
  local ok, pt = pcall(Compose.page, spec)
  local ms = math.floor((os.clock() - t0) * 1000 + 0.5)
  if not ok then
    index:write(table.concat({ role, pal, name, "", "", "", ms, (tostring(pt):gsub("[\t\n]", " ")) }, "\t") .. "\n")
    io.stderr:write("FAIL " .. role .. " " .. pal .. " " .. name .. ": " .. tostring(pt) .. "\n")
    return nil
  end
  Pdf.write(file, pt, spec.width, spec.height)
  local p = pt.pattern or {}
  index:write(table.concat({ role, pal, name, p.cells or "", p.offered or "", pt.count or "", ms, p.name and "" or "no pattern painted" }, "\t") .. "\n")
  return pt
end

for _, r in ipairs(ROLES) do
  local role, layout, keys, mix, tex = r[1], r[2], r[3], r[4], r[5]
  if not wanted or wanted[role] then
    for _, P in ipairs(PALETTES) do
      local dir = outdir .. "/" .. role .. "/" .. P[1]
      mkdir(dir)
      for _, p in ipairs(Patterns.list) do
        local line = "pattern=" .. p.name .. (keys ~= "" and ", " .. keys or "")
        local build = tex and tex_spec or mixer_spec
        render(role, P[1], p.name, build(layout, line, mix, P[2], P[3]), dir .. "/" .. p.name .. ".pdf")
      end
    end
  end
end

-- Parity: the same page built the mixer's way and the TeX way, for every
-- pattern on the opening page and palette. tools/pattern-audit.sh
-- compares the two PDFs' pixels.
if not wanted or wanted.parity then
  local P = PALETTES[1]
  for _, way in ipairs({ { "parity-mixer", mixer_spec }, { "parity-tex", tex_spec } }) do
    local dir = outdir .. "/" .. way[1] .. "/" .. P[1]
    mkdir(dir)
    for _, p in ipairs(Patterns.list) do
      render(way[1], P[1], p.name, way[2]("left", "pattern=" .. p.name, nil, P[2], P[3]), dir .. "/" .. p.name .. ".pdf")
    end
  end
end

index:close()
