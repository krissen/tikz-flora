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
-- and on the dark backdrop; a variant's `layout` replaces the page's left
-- and the slide's right, moves the text block where that layout puts it,
-- and writes the moved text's boxes beside the page (<pattern>.text); a
-- variant's `grow` renders that frame of the growth (spec.grow). ONLY limits the run to the variants named
-- (comma-separated), or, as set:NAME, to the variants of that set; a
-- variant with a `set` is left out of every other run.
--
-- A variant of the prototype sets (pattern_proto.lua's keys) may also give:
--   opts     the page's pattern_opts
--   seed     the page's seed, in place of 11
--   keep_text  its layout is kept without the text moved (layout=perimeter)
--   heroes   hero names, each drawn over every pattern of the variant on
--            page 3 as hero-NAME-PATTERN
--   probe    render the gold as pure magenta again, as probe/NAME.pdf, for
--            tools/pattern-proto.sh to measure the gold's share by
-- and OUTDIR/proto.tsv gets a row for every page: what the prototype laid
-- (places, the cells' spacing, where the first deviant or loose plate lies
-- in mm from the page's lower left corner), the pattern's roles and the
-- page's log.
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
local wanted, only_set
if only and only ~= "" then
  only_set = only:match("^set:(.+)$")
  if not only_set then
    wanted = {}
    for r in only:gmatch("[^,]+") do wanted[r] = true end
  end
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
local function page_spec(page, layout, setup, backdrop, opts, seed)
  local spec = load(page)
  spec.seed = Init.seed(tostring(seed or SEED), tonumber(page) or 1)
  local own = Settings.from_spec(spec, Settings.fresh_keys())
  own.layout, own.header = layout, spec.header
  local set = Settings.merge(own, Settings.parse(setup .. ", backdrop=" .. backdrop))
  Settings.to_spec(set, spec)
  spec.layout = layout
  spec.ornaments = {}
  spec.pattern_opts = opts
  return spec
end

-- For a variant with its own layout the text block (and its lines) moves
-- as that layout sets it: flush with the far margin under left, flush with
-- the near one under right, centred under centered and surround. The
-- baked page's narrower margin is kept.
local function place_text(spec, layout)
  local t, W = spec.text, spec.width
  local m = math.min(t.x0, W - t.x1)
  local x0
  if layout == "left" then x0 = W - m - (t.x1 - t.x0)
  elseif layout == "right" then x0 = m
  else x0 = (W - (t.x1 - t.x0)) / 2 end
  local dx = x0 - t.x0
  spec.text = { x0 = t.x0 + dx, y0 = t.y0, x1 = t.x1 + dx, y1 = t.y1 }
  for _, l in ipairs(spec.lines or {}) do l.x0, l.x1 = l.x0 + dx, l.x1 + dx end
end

-- The text block as boxes (its lines, or the block), beside a page drawn
-- with its text moved, for the sheets to draw in place of the text.
local function write_text(spec, file)
  local f = assert(io.open(file, "w"))
  f:write(string.format("%.2f %.2f\n", spec.width, spec.height))
  local boxes = spec.lines and #spec.lines > 0 and spec.lines or { spec.text }
  for _, b in ipairs(boxes) do f:write(string.format("%.2f %.2f %.2f %.2f\n", b.x0, b.y0, b.x1, b.y1)) end
  f:close()
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

local ptsv = assert(io.open(outdir .. "/proto.tsv", "a"))
local MM = 25.4 / 72

-- Render `spec` to `file`; returns the painter, or nil when it failed.
local function render(spec, file)
  Paint.reset_resources()
  local ok, pt = pcall(Compose.page, spec)
  if not ok then
    io.stderr:write("FAIL " .. file .. ": " .. tostring(pt) .. "\n")
    return nil
  end
  Pdf.write(file, pt, spec.width, spec.height)
  return pt
end

-- The page again with the gold as pure magenta, in place so that every
-- check against it holds, to probe/NAME.pdf beside the page.
local function render_probe(spec, dir, name)
  mkdir(dir .. "/probe")
  local gold = Paint.palette.gold
  local was = { gold[1], gold[2], gold[3] }
  gold[1], gold[2], gold[3] = 1, 0, 1
  render(spec, dir .. "/probe/" .. name .. ".pdf")
  gold[1], gold[2], gold[3] = was[1], was[2], was[3]
end

-- A row of proto.tsv for the page just rendered: variant, backdrop, name,
-- seed, places the prototype laid, the cells' spacing (mm), the page's
-- size and where the first deviant or loose plate lies (mm, from the
-- lower left corner), how many deviants, whether a plate is loose, the
-- pattern's roles and the page's log.
local function proto_row(v, bd, name, spec, pt, p)
  local pp = pt and pt.pattern
  local r = pp and pp.proto or {}
  local fx, fy
  if r.deviants and r.deviants[1] then fx, fy = r.deviants[1].x, r.deviants[1].y end
  if r.loose then fx, fy = (r.loose.x + r.loose.to_x) / 2, (r.loose.y + r.loose.to_y) / 2 end
  local function mm(x) return x and string.format("%.1f", x * MM) or "" end
  ptsv:write(table.concat({ v.name, bd, name, tostring(v.seed or SEED), tostring(r.places or ""), mm(r.spacing),
    mm(spec.width), mm(spec.height), mm(fx), mm(fy), tostring(r.deviants and #r.deviants or 0), r.loose and "1" or "0",
    table.concat(p.roles, ","), table.concat(pp and pp.warnings or {}, " | ") }, "\t") .. "\n")
end

local function wanted_variant(v)
  if wanted then return wanted[v.name] end
  if only_set then return v.set == only_set end
  return not v.set
end

for _, v in ipairs(V.variants) do
  if wanted_variant(v) then
    for _, bd in ipairs(v.backdrops or { "light", "dark" }) do
      local dir = outdir .. "/" .. v.name .. "/" .. bd
      mkdir(dir)
      for _, p in ipairs(Patterns.list) do
        if v.patterns and not v.patterns[p.name] then goto skip end
        local spec = page_spec("4", v.layout or "left", "pattern=" .. p.name .. ", " .. v.setup, bd, v.opts, v.seed)
        if v.layout and not v.keep_text then place_text(spec, v.layout); write_text(spec, dir .. "/" .. p.name .. ".text") end
        spec.grow = v.grow
        local pt = render(spec, dir .. "/" .. p.name .. ".pdf")
        measure(v.name, bd, p, spec)
        proto_row(v, bd, p.name, spec, pt, p)
        if v.probe then render_probe(spec, dir, p.name) end
        if v.slide then
          local sspec = page_spec("slide", v.layout or "right", "pattern=" .. p.name .. ", " .. v.setup, bd, v.opts, v.seed)
          if v.layout and not v.keep_text then place_text(sspec, v.layout); write_text(sspec, dir .. "/slide-" .. p.name .. ".text") end
          sspec.grow = v.grow
          local spt = render(sspec, dir .. "/slide-" .. p.name .. ".pdf")
          proto_row(v, bd, "slide-" .. p.name, sspec, spt, p)
          if v.probe then render_probe(sspec, dir, "slide-" .. p.name) end
        end
        for _, h in ipairs(v.heroes or {}) do
          local hspec = page_spec("3", "right", "pattern=" .. p.name .. ", hero=" .. h .. ", " .. v.setup, bd, v.opts, v.seed)
          local name = "hero-" .. h .. "-" .. p.name
          local hpt = render(hspec, dir .. "/" .. name .. ".pdf")
          proto_row(v, bd, name, hspec, hpt, p)
          if v.probe then render_probe(hspec, dir, name) end
        end
        ::skip::
      end
      for _, h in ipairs(v.patterns and {} or { "rosette", "phyllotaxis", "rose", "guilloche" }) do
        render(page_spec("3", "right", "pattern=stars_8_4, hero=" .. h .. ", " .. v.setup, bd, v.opts, v.seed), dir .. "/hero-" .. h .. ".pdf")
      end
    end
  end
end
tsv:close()
ptsv:close()
