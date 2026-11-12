-- Renders the pattern colour-role variants that tools/pattern_variants.lua
-- describes, and measures each variant's role colours (pattern.lua's
-- M.roles), for tools/pattern-roles.sh to lay out.
--
--   texlua tools/pattern_roles.lua SPECDIR OUTDIR VARIANTS.lua [ONLY]
--
-- SPECDIR holds tex/lorem.tex's baked layouts (spec-N.lua, as for
-- tools/pattern_audit.lua) and, for the slide, spec-slide.lua. Every page
-- is built as the mixer builds it (the opening seed 11, the left page 4
-- for the fields, the right page 3 for the heroes, which sit over
-- stars_8_4), with the variant's palette, backdrop and spec.pattern_roles.
-- ONLY limits the run to the variants named (comma-separated).
--
-- Writes OUTDIR/<variant>/<palette>-<backdrop>/<pattern>.pdf (and
-- hero-<name>.pdf, slide-<pattern>.pdf where the variant asks for the
-- slide) and OUTDIR/roles.tsv: per variant, palette, backdrop and
-- pattern, each role's colour as painted (hex, OKLab L and chroma) and the
-- contrast of the roles that meet (WCAG contrast ratio and OKLab
-- lightness difference). A source tree without pattern.lua's roles (the
-- reference V0) is rendered all the same and measured with the default
-- roles of this tree, which paint the colours patterns had before roles.

package.path = "./lua/?.lua;" .. package.path
local Serial = require("flora.serial")
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Init = require("flora.init")
local Pdf = require("flora.pdfout")
local Settings = require("flora.settings")
local Patterns = require("flora.patterns")
local Pattern = require("flora.pattern")
local Color = require("flora.color")
local Tune = require("flora.tune")

local specdir, outdir, vfile, only = arg[1], arg[2], arg[3], arg[4]
assert(specdir and outdir and vfile, "usage: pattern_roles.lua SPECDIR OUTDIR VARIANTS.lua [ONLY]")
local V = dofile(vfile)
local wanted
if only and only ~= "" then
  wanted = {}
  for r in only:gmatch("[^,]+") do wanted[r] = true end
end

local SEED = 11
local function load(name)
  local f = assert(io.open(specdir .. "/spec-" .. name .. ".lua"))
  local s = Serial.decode(f:read("a"))
  f:close()
  return s
end

local function page_spec(page, layout, palette, backdrop, keys, roles)
  local spec = load(page)
  spec.seed = Init.seed(tostring(SEED), tonumber(page) or 1)
  spec.layout = layout
  spec.mix = {}
  spec.ornaments = {}
  spec.palette = palette
  spec.spin = 0
  spec.backdrop = Settings.parse("backdrop=" .. backdrop).backdrop
  local ps = Settings.parse(keys)
  spec.pattern, spec.pattern_edge, spec.pattern_outer, spec.pattern_scale, spec.pattern_hero =
    ps.pattern, ps.edge, ps.outer, ps.scale, ps.hero
  spec.pattern_roles = roles
  return spec
end

local function mkdir(p) os.execute("mkdir -p '" .. p .. "'") end

local function hex(c)
  return string.format("#%02x%02x%02x", math.floor(c[1] * 255 + .5), math.floor(c[2] * 255 + .5), math.floor(c[3] * 255 + .5))
end
local function lum(c)
  local function d(v) return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
  return 0.2126 * d(c[1]) + 0.7152 * d(c[2]) + 0.0722 * d(c[3])
end
local function cr(p, q)
  local a, b = lum(p), lum(q)
  if a < b then a, b = b, a end
  return (a + 0.05) / (b + 0.05)
end

-- A role colour as the page shows it: repainted for a dark backdrop
-- (Paint:ink) unless the pattern is lit on a dark ground or it is gold.
local function shown(rgb, base, backdrop)
  if not rgb then return nil end
  if not backdrop or base.lit or rgb == Paint.palette.gold then return rgb end
  return Color.on_ground(rgb, backdrop, Paint.palette.paper)
end

local tsv = assert(io.open(outdir .. "/roles.tsv", "a"))
local ROLE_COLS = { "surface", "band", "core", "a", "b", "accent", "ground" }

local function measure(vname, pname, bd, name, spec)
  if not Pattern.role_inks then return end
  local Rng = require("flora.rng")
  local base = require("flora.mix").with_palette(spec.palette, function()
    return Pattern.role_inks(Rng.new(spec.seed):fork("pattern inks"), name, spec.pattern_roles)
  end)
  local back = type(spec.backdrop) == "table" and spec.backdrop or Color.backdrop(spec.backdrop)
  local surface = base.ground or (back or Paint.palette.paper)
  local s = {
    surface = base.ground and shown(base.ground, base, back) or surface,
    band = shown(base.band, base, back), core = shown(base.core, base, back),
    a = shown(base.fill1, base, back), b = shown(base.fill2, base, back),
    accent = shown(base.accent, base, back), ground = base.ground and shown(base.ground, base, back),
  }
  local row = { vname, pname, bd, name, base.lit and "lit" or (base.ground and "tint" or "") }
  for _, k in ipairs(ROLE_COLS) do
    local c = s[k]
    if c then
      local L, Ch = Color.lch(c)
      row[#row + 1] = string.format("%s L%.2f C%.3f", hex(c), L, Ch)
    else
      row[#row + 1] = ""
    end
  end
  local function pair(p, q) return (s[p] and s[q]) and string.format("%.2f/%.2f", cr(s[p], s[q]), math.abs(Color.lightness(s[p]) - Color.lightness(s[q]))) or "" end
  for _, pq in ipairs({ { "band", "surface" }, { "a", "surface" }, { "b", "surface" }, { "a", "b" }, { "band", "a" }, { "core", "band" }, { "accent", "surface" } }) do
    row[#row + 1] = pair(pq[1], pq[2])
  end
  tsv:write(table.concat(row, "\t") .. "\n")
end

local function render(spec, file)
  Paint.reset_resources()
  local ok, pt = pcall(Compose.page, spec)
  if not ok then
    io.stderr:write("FAIL " .. file .. ": " .. tostring(pt) .. "\n")
    return
  end
  Pdf.write(file, pt, spec.width, spec.height)
end

for _, v in ipairs(V.variants) do
  if not wanted or wanted[v.name] then
    for _, P in ipairs(v.palettes) do
      for _, bd in ipairs(v.backdrops or { "light", "dark" }) do
        local dir = outdir .. "/" .. v.name .. "/" .. P[1] .. "-" .. bd
        mkdir(dir)
        for _, p in ipairs(Patterns.list) do
          local spec = page_spec("4", "left", P[2], bd, "pattern=" .. p.name, v.roles)
          render(spec, dir .. "/" .. p.name .. ".pdf")
          measure(v.name, P[1], bd, p.name, spec)
          if v.slide then
            render(page_spec("slide", "right", P[2], bd, "pattern=" .. p.name, v.roles), dir .. "/slide-" .. p.name .. ".pdf")
          end
        end
        for _, h in ipairs({ "rosette", "phyllotaxis", "rose", "guilloche" }) do
          render(page_spec("3", "right", P[2], bd, "pattern=stars_8_4, hero=" .. h, v.roles), dir .. "/hero-" .. h .. ".pdf")
        end
      end
    end
  end
end
tsv:close()
