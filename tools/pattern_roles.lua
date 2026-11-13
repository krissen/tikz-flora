-- Renders the pattern variants tools/pattern_variants.lua lists, each a
-- \florasetup line, and measures each page's role colours (pattern.lua's
-- role model), for tools/pattern-roles.sh to lay out.
--
--   texlua tools/pattern_roles.lua SPECDIR OUTDIR VARIANTS.lua [ONLY]
--
-- SPECDIR holds tex/lorem.tex's baked layouts (spec-N.lua, as for
-- tools/pattern_audit.lua) and, for the slides, a 160 x 90 mm page's
-- spec-slide.lua. Every page is built as the mixer builds it (the opening
-- seed 11, the left page 4 for the fields, the right page 3 for the heroes,
-- which sit over stars_8_4), with the variant's settings on light paper
-- and on the dark backdrop. ONLY limits the run to the variants named
-- (comma-separated).
--
-- Writes OUTDIR/<variant>/<backdrop>/<pattern>.pdf (and hero-<name>.pdf,
-- and slide-<pattern>.pdf for a variant with `slide`) and appends to
-- OUTDIR/roles.tsv: per variant, backdrop and pattern, each role's colour
-- as the page shows it (hex, OKLab L and chroma) and the contrast of the
-- roles that meet (WCAG contrast ratio / OKLab lightness difference).

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

-- The page for `setup` (a \florasetup key list) on the baked page, as
-- tools/preview.lua builds it with "fresh": the page's own settings
-- without its inks, then the setup's.
local function page_spec(page, layout, setup, backdrop)
  local spec = load(page)
  spec.seed = Init.seed(tostring(SEED), tonumber(page) or 1)
  local own = Settings.from_spec(spec, Settings.fresh_keys())
  own.layout, own.header = layout, spec.header
  local set = Settings.merge(own, Settings.parse(setup .. ", backdrop=" .. backdrop))
  Settings.to_spec(set, spec)
  spec.layout = layout
  spec.ornaments = {}
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

local tsv = assert(io.open(outdir .. "/roles.tsv", "a"))
local ROLE_COLS = { "surface", "band", "core", "a", "b", "accent", "ground" }

local function measure(vname, bd, p, spec)
  local Rng = require("flora.rng")
  local base = require("flora.mix").with_palette(spec.palette, function()
    return Pattern.role_inks(Rng.new(spec.seed):fork("pattern inks"), p, spec)
  end)
  local back = Color.backdrop(spec.backdrop)
  -- A colour as the page shows it: repainted for a dark backdrop
  -- (Paint:ink) unless the pattern is painted as it is, or it is gold.
  local function shown(rgb)
    if not rgb then return nil end
    if not back or base.lit or rgb == Paint.palette.gold then return rgb end
    return Color.on_ground(rgb, back, Paint.palette.paper)
  end
  local s = {
    surface = base.ground and shown(base.ground) or (back or Paint.palette.paper),
    band = shown(base.band), core = shown(base.core), a = shown(base.fill1), b = shown(base.fill2),
    accent = shown(base.accent), ground = base.ground and shown(base.ground),
  }
  local row = { vname, bd, p.name, base.lit and "as-is" or "", base.ground and "ground" or "" }
  for _, k in ipairs(ROLE_COLS) do
    local c = s[k]
    if c then
      local L, Ch = Color.lch(c)
      row[#row + 1] = string.format("%s L%.2f C%.3f", hex(c), L, Ch)
    else
      row[#row + 1] = ""
    end
  end
  local function pair(a, b) return (s[a] and s[b]) and string.format("%.2f/%.2f", cr(s[a], s[b]), math.abs(Color.lightness(s[a]) - Color.lightness(s[b]))) or "" end
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
    for _, bd in ipairs(v.backdrops or { "light", "dark" }) do
      local dir = outdir .. "/" .. v.name .. "/" .. bd
      mkdir(dir)
      for _, p in ipairs(Patterns.list) do
        local spec = page_spec("4", "left", "pattern=" .. p.name .. ", " .. v.setup, bd)
        render(spec, dir .. "/" .. p.name .. ".pdf")
        measure(v.name, bd, p, spec)
        if v.slide then
          render(page_spec("slide", "right", "pattern=" .. p.name .. ", " .. v.setup, bd), dir .. "/slide-" .. p.name .. ".pdf")
        end
      end
      for _, h in ipairs({ "rosette", "phyllotaxis", "rose", "guilloche" }) do
        render(page_spec("3", "right", "pattern=stars_8_4, hero=" .. h .. ", " .. v.setup, bd), dir .. "/hero-" .. h .. ".pdf")
      end
    end
  end
end
tsv:close()
