-- Document settings from \florasetup and \florathispage: a key=value list,
-- parsed and checked here so mistakes are reported with the key's name.
-- M.about describes every key; the guide's table of settings is made
-- from it (catalog.lua).

local M = {}

local Frames = require("flora.frames")
local Tune = require("flora.tune")
local Inks = require("flora.inks")
local Mix = require("flora.mix")
local Orn = require("flora.ornaments")
local Look = require("flora.gilt_look")
local Band = require("flora.band")

-- Every key, in the order the guide lists them: {key, values, effect}.
M.about = {
  { "layout", "left, right, centered, split, title, surround, " .. Band.LAYOUT .. ", flank, wreath, bouquet, scrollwork",
    "Where the flora grows (see Layouts)." },
  { "header", "body, margin", "Keep flora below the measured frame title, or grow in the margins beside it." },
  { "tune", "{section={key=value, ...}, ...}", "Override engine tuning values for this document or page." },
  { "seed", "a number, or random", "Which garden. Each page varies it, so pages differ." },
  { "mix", "{kind=weight, ...}, weights 0 to 10",
    "How much of each kind of growth, and how often each leaf shape and bloom style is drawn: 1 the usual amount, 0 none, 2 about twice as much." },
  { "density", "0 to 10", "How full the border grows: fuller above 1, airier below." },
  { "visitors", "0 to 10", "The weight of every visitor at once: bees, butterflies, birds and snails. mix={bee=0} after it still turns one off." },
  { "palette", "{part=ink, ...}",
    "What paints each part: look (the original blue gradients), an ink group, one iroshizuku ink by name, or random for one ink picked per page." },
  { "colourway", "original, spring, summer, autumn (or fall), winter, ember, plum, rose, usu-zumi, tsuki-mi",
    "A whole palette at once, for flora and for patterns (patternpalette). A palette={...} or patternpalette={...} after it changes single parts; a colourway after them sets every part and role again." },
  { "spin", "a whole number", "Picks the random inks again. The shapes stay where they are." },
  { "ornaments", "{kind=weight, ...}, weights 0 to 10",
    "How often each ornament kind is picked for its place on the page, against the other kinds for that place: 0 never." },
  { "gilt", "raster, vector", "How ornament gold is painted: raster, gold computed per pixel; or vector, gold in relief built of flat strips." },
  { "giltdpi", "50 to 1200", "Pixels per inch of raster gilt." },
  { "giltenv", "studio, mirror", "Which look raster gilt takes (see Gilt)." },
  { "giltlook", "{key=value, ...}", "Changes keys of that look, such as giltlook={horizon=0.1, grain=0} (see Gilt)." },
  { "backdrop", "light, dark, or a dark colour as #rrggbb",
    "What the flora is painted over: light, white paper (the default); dark, a near-black page; or that colour. On a dark backdrop every ink is painted light, as if lit, and gold stays gold." },
  { "pattern", "a pattern or group name, {name=weight, ...} with weights 0 to 10, or none",
    "Fills the page with a geometric pattern instead of flora: one picked per page by weight. A group name (such as japanese or girih) weighs every pattern in it, except the emblem patterns (hexagram_lattice, khatam, greek_crosses), which only their own name or the group symbol picks. Each setting replaces the last; none grows flora again." },
  { "edge", "dissolve, cell, fade, border, guilloche",
    "How a pattern meets the text: cells falling away (the default), whole cells to a hard edge, cells paling into the paper, a ruled frame round the text, or a guilloche band round it. In a perimeter band (layout=" .. Band.LAYOUT .. ") it is how the band ends toward the text: border a straight edge with a rule, cell whole cells, fade cells paling, dissolve cells falling away into the margin, and " .. Band.ROWS .. " whole rows that fill the band; left out, each pattern's own (whole rows for asanoha, celtic_knot and stars_8_4, border for the others). guilloche has no form in a band. For flora in a perimeter band, border cuts it along a rule at the band's inner edge, and any other value cuts it there softly." },
  { "hero", "rosette, phyllotaxis, rose, guilloche, turned_circles, circle_disc, none",
    "One large radial motif at a top corner of a pattern page, which the cells give way to: rings of petals, seeds set as a sunflower sets them, a rose window, guilloche rings, a ring of turned circles, or a disc of overlapping circles in a rim. It sits in the top corner of the pattern's side (top right for right, top left for left; top right for layouts with both sides or the whole page): centred on the paper's corner and running off it under outer=bleed, a whole disc inside the margin under outer=margin. It grows ring by ring from its centre. none (the default) paints none." },
  { "outer", "bleed, margin", "How a pattern meets the paper's edge: running off the page (the default), or whole cells, and a whole hero, inside a small margin." },
  { "scale", "0.25 to 4", "The size of a pattern's cells, as a factor of their size for the field: a pattern's own size on a 53 mm margin, in proportion smaller in a narrower field (the strip it stands in), down to half its own size, and never larger in a wider one." },
  { "patternpalette", "{role=ink, ...} for the roles band, core, fielda, fieldb, ground, accent",
    "What paints each part of a pattern: an ink group, one iroshizuku ink by name (as ink:L or ink:L:share with its lightness and chroma kept), paper or gold, and for the ground also none. A colourway sets them all; a role left out takes its colour from the palette's flora parts. An ink without a lightness takes the role's own, and for core and accent, which have none, the ink's richest (most chromatic) shade." },
  { "saturation", "0 to 1", "How much of its inks' colour a pattern's fields and ground keep: 0.5 (the default) mutes them as tiles and mosaics are, 1 keeps the ink's full colour. A share patternpalette gives a field or the ground (ink:L:share) is the one it keeps at 0.5, and other values scale it." },
  { "finish", "filled, lines, lacquer", "How a pattern is drawn: filled (the default), with its fields and ground; lines, its bands and outlines alone with nothing filled; or lacquer, for sikku_kolam and asanoha, thin gold line work on the ground laid as one panel (ground, bands and bandwidth set on the page go before it; on another pattern it is filled, and the log says so)." },
  { "bands", "auto, line, strap", "How a pattern's bands are drawn: auto (the default), each pattern's own; line, one thin line; or strap, a broad band with a fine contour and a light core." },
  { "ground", "auto, off, panel, motif, round, cells", "Whether a pattern that has a ground (asanoha, sikku_kolam, rosette_lattice) lays it under its cells, and how it ends toward the text: auto (the default) leaves the paper on light paper and lays a panel on a dark backdrop; off leaves the page; panel lays one panel with a straight edge; motif ends it along the pattern's own motifs; round gives it a rounded edge; cells lays a piece under every cell. on is panel." },
  { "ends", "auto, closed, bleed, whole, cut", "How a pattern's lines end where the field ends (sikku_kolam, celtic_knot): auto (the default), each pattern's own, closed; closed turns every line back at the field's edge, so none ends loose, and lays celtic_knot as one closed panel filling the field, its loops turning back just inside the paper's edges; bleed lets celtic_knot's panel run off the paper's edges (under outer=margin it closes at the margin, as closed does) and is closed for the other patterns; whole lets each line fall away whole with its dots; cut cuts the lines cell by cell." },
  { "panels", "auto, on, off", "Whether sikku_kolam is laid out in symmetric panels, each walled in and the same under turns and reflections: auto (the default) and on do, off draws one free kolam over the field." },
  { "starfill", "auto, whole, split", "How a star pattern's star is coloured (khatam): auto (the default) and whole lay the whole star in the first field; split lays the star's two squares in the two fields, its square on its point in the first and the other's four corners in the second." },
  { "gapfill", "auto, field, paper", "What fills the space between a star pattern's stars (khatam's crosses, hexagram_lattice's rhombs): auto (the default) and field the second field, paper the paper. Under starfill=split khatam's crosses are always the paper." },
  { "alternate", "auto, off, rows, three", "Whether a star pattern's stars take turns in the fields (hexagram_lattice): auto (the default) and off lay every star in the first field; rows alternate the first and second field row by row; three deal the first field, the second and the accent so that no two touching stars share one." },
  { "glint", "off, on, core, cells, knobs",
    "Where gold lies in a pattern's field, in place of the pattern's own (off, the default, leaves it as it is): on lays a few glints where the bands cross, spread by the page's seed; core makes the band's core gold (it shows only where the core is drawn, at least 0.6 pt wide, and the log says where it is not); cells gilds a few whole cells; knobs sets a gold knob at the middle of every cell. A pattern with nothing to lay it by (see the guide) is painted as it is, and the log says so." },
  { "herogold", "on, off", "Paints the hero's lines in gold (off, the default). It combines with glint." },
  { "deviant", "on, off", "Turns at most one whole cell on each side of the text, or of a perimeter band, and paints it in another colour, its place drawn by the page's seed (off, the default)." },
  { "loose", "on, off", "Lets one cell come loose from the field's edge and lie a little way outside it, a dotted path leading back to the gap it left, clear of the text as the field is (off, the default)." },
  { "lighten", "0 to 1", "Lightens a pattern's fields toward the paper: 0 (the default) keeps their inks' lightness, 1 makes them nearly the paper." },
  { "bandwidth", "0.25 to 4", "The width of a pattern's bands and lines, as a factor of its own." },
  { Band.WIDTH, Band.WIDTH_MIN .. " to " .. Band.WIDTH_MAX, "The width in mm of a perimeter band (layout=" .. Band.LAYOUT .. "), the same on all four sides: " .. Band.WIDTH_DEFAULT .. " by default. Where a margin is narrower, the whole band narrows to what the narrowest side holds, the same all round and clear of the text block (none under 4 mm), and the log says so." },
  { Band.FLORA_DENSITY, table.concat(Band.DENSITIES, ", "), "How densely the vine of a perimeter band grows: " .. Band.DENSITIES[1] .. " (the default), many small leaves and blooms; open, fewer and larger; sparse, fewest and largest, its stem as fine as at " .. Band.DENSITIES[1] .. ". The sparser it is, the quicker the page: about half the time at sparse. open needs a band of " .. Band.DENSITY_NARROWEST.open .. " mm and sparse one of " .. Band.DENSITY_NARROWEST.sparse .. " mm; in a narrower band the vine is laid at the sparsest density the band holds, and the log says so." },
  { Band.FLORA, table.concat(Band.FLORAS, ", "), "The form of flora in a perimeter band (layout=" .. Band.LAYOUT .. " without a pattern): " .. Band.FLORAS[1] .. " (the default), one vine round all four sides, rooted in the foot-left corner and meeting itself in the top-right one, its corners rounded; pinwheel, two plants turning round the page, one up the left side and along the foot, the other down the right side and along the top; corners, a plant in each corner with its arms along the two sides and a sparser vine along the middle of each side. The flora keeps to the band, cut softly along its inner edge, or along a rule there under edge=border. A band narrower than " .. Band.FLORA_NARROWEST .. " mm has no flora, and the log says so. corners in a band wider than 0.4 of the paper's shorter side, where its arms do not fit, is laid as vine, and the log says so." },
  { "cache", "true, false",
    "true (the default) keeps each page's flora in a folder <jobname>-flora beside the PDF, so a later compile reuses it; false grows every page afresh." },
}

-- Key name -> function(value string) returning the parsed value, or nil
-- and a message.
local keys = {}

function M.define(name, parse)
  keys[name] = parse
end

-- The names of every defined key, sorted.
function M.defined()
  local out = {}
  for k in pairs(keys) do out[#out + 1] = k end
  table.sort(out)
  return out
end

M.define("layout", function(v)
  if Frames.layouts[v] then return v end
  return nil, "layout must be one of " .. table.concat(Frames.order, ", ")
end)

M.define("header", function(v)
  if v == "body" or v == "margin" then return v end
  return nil, "header must be body or margin"
end)

M.define("seed", function(v)
  if v == "random" or tonumber(v) then return v end
  return nil, "seed must be a number or random"
end)

local function weight(v)
  local n = tonumber(v)
  if n and n >= 0 and n <= 10 then return n end
end

local function known(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return table.concat(out, ", ")
end

local function is_list(t)
  return type(t) == "table" and #t > 0
end

M.define("density", function(v)
  local n = weight(v)
  if n then return n end
  return nil, "density must be a number from 0 to 10"
end)

-- A shorthand for every visitor's weight.
M.define("visitors", function(v)
  local n = weight(v)
  if n then return n end
  return nil, "visitors must be a number from 0 to 10"
end)

M.define("mix", function(v)
  local t = {}
  for _, kv in ipairs(M.parse_list(v)) do
    local k, w = kv[1], weight(kv[2])
    if Tune.mix[k] == nil then return nil, "no kind \"" .. k .. "\" (kinds: " .. known(Tune.mix) .. ")" end
    if not w then return nil, k .. " needs a weight from 0 to 10" end
    t[k] = w
  end
  return t
end)

M.define("ornaments", function(v)
  local t = {}
  for _, kv in ipairs(M.parse_list(v)) do
    local k, w = kv[1], weight(kv[2])
    if not Orn.kinds[k] then return nil, "no ornament \"" .. k .. "\" (kinds: " .. known(Orn.kinds) .. ")" end
    if not w then return nil, k .. " needs a weight from 0 to 10" end
    t[k] = w
  end
  return t
end)

M.define("pattern", function(v)
  -- none returns the page to flora.
  if v == "none" then return {} end
  local P = require("flora.patterns")
  local names, tags = P.known()
  local ok = {}
  for _, n in ipairs(names) do ok[n] = true end
  for _, n in ipairs(tags) do ok[n] = true end
  for alias in pairs(P.aliases) do ok[alias] = true end
  local t = {}
  for _, kv in ipairs(M.parse_list(v)) do
    -- An alias (patterns.lua) is read as the pattern it names.
    local k, w = P.canonical(kv[1]), kv[2] == nil and 1 or weight(kv[2])
    if not ok[k] then
      return nil, "no pattern or group \"" .. k .. "\" (patterns: " .. table.concat(names, ", ")
        .. "; groups: " .. table.concat(tags, ", ") .. ")"
    end
    if not w then return nil, k .. " needs a weight from 0 to 10" end
    t[k] = w
  end
  return t
end)

M.define("edge", function(v)
  if require("flora.pattern").edges[v] then return v end
  return nil, "edge must be dissolve, cell, fade, border, guilloche or " .. Band.ROWS
end)

M.define("hero", function(v)
  local names = require("flora.pattern_hero").names()
  for _, n in ipairs(names) do if v == n then return v end end
  return nil, "hero must be " .. table.concat(names, ", ")
end)

M.define("outer", function(v)
  if require("flora.pattern").outers[v] then return v end
  return nil, "outer must be bleed or margin"
end)

M.define(Band.WIDTH, function(v)
  local n = tonumber(v)
  if n and n >= Band.WIDTH_MIN and n <= Band.WIDTH_MAX then return n end
  return nil, string.format("%s must be a number of mm from %d to %d", Band.WIDTH, Band.WIDTH_MIN, Band.WIDTH_MAX)
end)

M.define(Band.FLORA_DENSITY, function(v)
  for _, d in ipairs(Band.DENSITIES) do if v == d then return v end end
  return nil, Band.FLORA_DENSITY .. " must be " .. table.concat(Band.DENSITIES, ", ")
end)

M.define(Band.FLORA, function(v)
  for _, f in ipairs(Band.FLORAS) do if v == f then return v end end
  return nil, Band.FLORA .. " must be " .. table.concat(Band.FLORAS, ", ")
end)

M.define("scale", function(v)
  local n = tonumber(v)
  if n and n >= 0.25 and n <= 4 then return n end
  return nil, "scale must be a number from 0.25 to 4"
end)

-- A pattern palette value split into its name and the rest, when it has
-- one of the forms patternpalette takes: name, name:L, name:L:share or
-- name::share, with L and share numbers from 0 to 1. The rest is "" for a
-- bare name, the suffix when it is well formed, and nil when it is not;
-- the name is nil when there is none.
local function palette_form(v)
  local name, rest = tostring(v):match("^([^:]+)(.*)$")
  if not name then return nil end
  if rest == "" then return name, rest end
  local function unit(s) local n = tonumber(s); return n and n >= 0 and n <= 1 end
  local L = rest:match("^:([^:]+)$")
  if L then return name, unit(L) and rest or nil end
  local L2, share = rest:match("^:([^:]*):([^:]+)$")
  if share and (L2 == "" or unit(L2)) and unit(share) then return name, rest end
  return name, nil
end

M.define("patternpalette", function(v)
  local Pattern = require("flora.pattern")
  local roles = {}
  for _, r in ipairs(Pattern.ROLE_KEYS) do roles[r.key] = true end
  local t = {}
  for _, kv in ipairs(M.parse_list(v)) do
    local role, ink = kv[1], kv[2]
    if not roles[role] then
      local names = {}
      for _, r in ipairs(Pattern.ROLE_KEYS) do names[#names + 1] = r.key end
      return nil, "no pattern role \"" .. role .. "\" (roles: " .. table.concat(names, ", ") .. ")"
    end
    local name, rest = palette_form(ink)
    if not (name and ((name == "paper" or name == "gold" or (name == "none" and role == "ground")) and rest == ""
        or (Inks.groups[name] or Inks.ramps[name]) and rest ~= nil)) then
      return nil, "\"" .. tostring(ink) .. "\" is not paper, gold, an ink group or an ink name (with :L or :L:share from 0 to 1)" .. (role == "ground" and ", or none" or "")
    end
    t[role] = ink
  end
  return t
end)

M.define("saturation", function(v)
  local n = tonumber(v)
  if n and n >= 0 and n <= 1 then return n end
  return nil, "saturation must be a number from 0 to 1"
end)

M.define("finish", function(v)
  if require("flora.pattern").finishes[v] then return v end
  return nil, "finish must be filled, lines or lacquer"
end)

M.define("bands", function(v)
  if v == "auto" or require("flora.pattern").band_kinds[v] then return v end
  return nil, "bands must be auto, strap or line"
end)

M.define("ground", function(v)
  if v == "on" then return "panel" end
  for _, m in ipairs({ "auto", "off", "panel", "motif", "round", "cells" }) do if v == m then return v end end
  return nil, "ground must be auto, off, panel, motif, round or cells"
end)

M.define("ends", function(v)
  for _, m in ipairs({ "auto", "closed", "bleed", "whole", "cut" }) do if v == m then return v end end
  return nil, "ends must be auto, closed, bleed, whole or cut"
end)

M.define("panels", function(v)
  if v == "auto" or v == "on" or v == "off" then return v end
  return nil, "panels must be auto, on or off"
end)

M.define("starfill", function(v)
  for _, m in ipairs({ "auto", "whole", "split" }) do if v == m then return v end end
  return nil, "starfill must be auto, whole or split"
end)

M.define("gapfill", function(v)
  for _, m in ipairs({ "auto", "field", "paper" }) do if v == m then return v end end
  return nil, "gapfill must be auto, field or paper"
end)

M.define("alternate", function(v)
  for _, m in ipairs({ "auto", "off", "rows", "three" }) do if v == m then return v end end
  return nil, "alternate must be auto, off, rows or three"
end)

M.define("glint", function(v)
  if require("flora.pattern_touches").GLINT[v] then return v end
  return nil, "glint must be off, on, core, cells or knobs"
end)

for _, k in ipairs({ "herogold", "deviant", "loose" }) do
  M.define(k, function(v)
    if v == "on" or v == "off" then return v end
    return nil, k .. " must be on or off"
  end)
end

M.define("lighten", function(v)
  local n = tonumber(v)
  if n and n >= 0 and n <= 1 then return n end
  return nil, "lighten must be a number from 0 to 1"
end)

M.define("bandwidth", function(v)
  local n = tonumber(v)
  if n and n >= 0.25 and n <= 4 then return n end
  return nil, "bandwidth must be a number from 0.25 to 4"
end)

M.define("cache", function(v)
  if v == "true" then return true end
  if v == "false" then return false end
  return nil, "cache must be true or false"
end)

M.define("backdrop", function(v)
  local rgb, msg = require("flora.color").backdrop(v)
  if rgb ~= nil or v == "light" then return v:lower() end
  return nil, msg
end)

M.define("gilt", function(v)
  if v == "vector" or v == "raster" then return v end
  return nil, "gilt must be vector or raster"
end)

M.define("giltdpi", function(v)
  local n = tonumber(v)
  if n and n >= 50 and n <= 1200 then return n end
  return nil, "giltdpi must be a number from 50 to 1200"
end)

M.define("giltenv", function(v)
  if v == "studio" or v == "mirror" then return v end
  return nil, "giltenv must be studio or mirror"
end)

M.define("giltlook", function(v)
  local t = {}
  for _, kv in ipairs(M.parse_list(v)) do
    local n, msg = Look.check(kv[1], kv[2])
    if not n then return nil, msg end
    t[kv[1]] = n
  end
  return t
end)

M.define("palette", function(v)
  local t = {}
  for _, kv in ipairs(M.parse_list(v)) do
    local part, ink = kv[1], kv[2]
    if Tune.color.palette[part] == nil then
      return nil, "no part \"" .. part .. "\" (parts: " .. known(Tune.color.palette) .. ")"
    end
    if not (ink == "look" or ink == "random" or Inks.groups[ink] or Inks.ramps[ink]) then
      return nil, "\"" .. tostring(ink) .. "\" is not look, random, an ink group or an ink name"
    end
    t[part] = ink
  end
  return t
end)

M.define("colourway", function(v)
  v = Inks.colourway_alias[v] or v
  local src = v == "original" and Tune.color.palette or Inks.colourways[v]
  if not src then return nil, "colourway must be one of " .. table.concat(Inks.colourway_order, ", ") end
  local t = {}
  for part in pairs(Tune.color.palette) do t[part] = src[part] or Tune.color.palette[part] end
  return t
end)

M.define("spin", function(v)
  local n = tonumber(v)
  if n and n == math.floor(n) and n >= 0 then return n end
  return nil, "spin must be a whole number"
end)

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Split "a=1, b={x=2, y=3}" at top-level commas into {name, value} pairs;
-- braces around a value are removed. A key without "=" has value nil.
function M.parse_list(s)
  local out, depth, start = {}, 0, 1
  local function take(piece)
    piece = trim(piece)
    if piece == "" then return end
    local k, v = piece:match("^([^=]-)%s*=%s*(.*)$")
    if not k then
      out[#out + 1] = { trim(piece), nil }
      return
    end
    v = trim(v)
    local inner = v:match("^{(.*)}$")
    out[#out + 1] = { trim(k), inner and trim(inner) or v }
  end
  for i = 1, #s do
    local ch = s:sub(i, i)
    if ch == "{" then depth = depth + 1
    elseif ch == "}" then depth = depth - 1
      if depth < 0 then error("unbalanced braces in \"" .. s .. "\"") end
    elseif ch == "," and depth == 0 then
      take(s:sub(start, i - 1))
      start = i + 1
    end
  end
  if depth ~= 0 then error("unbalanced braces in \"" .. s .. "\"") end
  take(s:sub(start))
  return out
end

-- Tune overrides for the engine: a table of settings mirroring tune.lua's
-- T, e.g. tune={compose={hero=0.3}, plant={root=0.72}}. Dotted names
-- (compose.hero=0.3) are accepted too. Every path is checked against the
-- tuner's own index (tune.lua's _doc), so a typo names the key and lists
-- what may be set there.
local parse_tune_table

local function split_fields(s)
  local out, depth, start = {}, 0, 1
  for i = 1, #s do
    local ch = s:sub(i, i)
    if ch == "{" then depth = depth + 1
    elseif ch == "}" then depth = depth - 1
      if depth < 0 then error("unbalanced braces in \"" .. s .. "\"", 0) end
    elseif ch == "," and depth == 0 then
      local piece = trim(s:sub(start, i - 1))
      if piece ~= "" then out[#out + 1] = piece end
      start = i + 1
    end
  end
  if depth ~= 0 then error("unbalanced braces in \"" .. s .. "\"", 0) end
  local piece = trim(s:sub(start))
  if piece ~= "" then out[#out + 1] = piece end
  return out
end

local function parse_tune_value(v)
  v = trim(v)
  local inner = v:match("^{(.*)}$")
  if inner then return parse_tune_table(inner) end
  local n = tonumber(v)
  if n then return n end
  if v == "" then error("empty tune value", 0) end
  return v
end

-- Assign a.b.c like a={b={c=...}} in `map`.
local function nest(map, name, value)
  local parts = {}
  for part in name:gmatch("[^.]+") do parts[#parts + 1] = part end
  local t = map
  for i = 1, #parts - 1 do
    local k = parts[i]
    if type(t[k]) ~= "table" then t[k] = {} end
    t = t[k]
  end
  t[parts[#parts]] = value
end

parse_tune_table = function(s)
  local fields = split_fields(s)
  local list, map = {}, {}
  local has_list, has_map = false, false
  for _, f in ipairs(fields) do
    local k, v = f:match("^([^=]-)%s*=%s*(.*)$")
    if k then
      has_map = true
      nest(map, trim(k), parse_tune_value(v))
    else
      has_list = true
      list[#list + 1] = parse_tune_value(f)
    end
  end
  if has_list and has_map then
    error("a tune table mixes a list and named keys", 0)
  end
  return has_list and list or map
end

local function tune_names(t)
  local out = {}
  for k in pairs(t) do
    if type(k) == "string" and k:sub(1, 1) ~= "_" then out[#out + 1] = k end
  end
  table.sort(out)
  return table.concat(out, ", ")
end

local function validate_tune(over, base, path)
  if is_list(over) then
    if not is_list(base) then
      error(string.format("%s: expected named settings, got a list", path:gsub("%.$", "")), 0)
    end
    if #over ~= #base then
      error(string.format("%s: expected %d values, got %d", path:gsub("%.$", ""), #base, #over), 0)
    end
    for i, v in ipairs(over) do
      local p = path:gsub("%.$", "") .. "[" .. i .. "]"
      local b = base[i]
      if type(b) == "table" then
        if type(v) ~= "table" then error(p .. ": expected a list or table", 0) end
        validate_tune(v, b, p .. ".")
      elseif type(v) ~= type(b) then
        error(string.format("%s: expected %s, got %s", p, type(b), type(v)), 0)
      end
    end
    return
  end
  for k, v in pairs(over) do
    if type(k) ~= "string" or k:sub(1, 1) == "_" then
      error(string.format("%s: \"%s\" is not a tune setting", path:gsub("%.$", ""), tostring(k)), 0)
    end
    local b = base[k]
    if b == nil then
      error(string.format("%s: no tune key \"%s\" (keys here: %s)",
        path:gsub("%.$", ""), path .. k, tune_names(base)), 0)
    end
    local p = path .. k
    if type(b) == "table" then
      if type(v) ~= "table" then
        error(string.format("%s: expected a list or table", p), 0)
      end
      validate_tune(v, b, p .. ".")
    elseif type(v) ~= type(b) then
      error(string.format("%s: expected %s, got %s", p, type(b), type(v)), 0)
    end
  end
end

M.define("tune", function(v)
  local ok, t = pcall(parse_tune_table, v)
  if not ok then return nil, tostring(t) end
  local valid, msg = pcall(validate_tune, t, Tune, "tune.")
  if not valid then return nil, tostring(msg) end
  return t
end)

-- Parse a key=value list into a settings table. Errors name the key.
function M.parse(s)
  local t = {}
  for _, kv in ipairs(M.parse_list(s)) do
    local k, v = kv[1], kv[2]
    local parse = keys[k]
    if not parse then
      local names = {}
      for name in pairs(keys) do names[#names + 1] = name end
      table.sort(names)
      error(string.format("unknown key \"%s\" (known keys: %s)", k, table.concat(names, ", ")))
    end
    if v == nil then error(string.format("key \"%s\" needs a value", k)) end
    local val, msg = parse(v)
    if val == nil then error(string.format("%s: %s (got \"%s\")", k, msg, v)) end
    if k == "density" then
      t.mix = M.merge({ mix = t.mix }, { mix = { density = val } }).mix
    elseif k == "colourway" then
      t.palette = M.merge({ palette = t.palette }, { palette = val }).palette
      -- A colourway sets its pattern roles too (inks.lua), every one of
      -- them: a role it leaves out goes back to its derived colour (false),
      -- so what a colourway paints does not depend on an earlier colourway
      -- or patternpalette. A patternpalette after it still changes one role.
      local roles = {}
      for _, r in ipairs(require("flora.pattern").ROLE_KEYS) do roles[r.key] = false end
      for role, ink in pairs(Inks.pattern_palette(Inks.colourway_alias[v] or v)) do roles[role] = ink end
      t.patternpalette = M.merge({ patternpalette = t.patternpalette }, { patternpalette = roles }).patternpalette
    elseif k == "visitors" then
      local m = {}
      for _, name in ipairs(Mix.visitors) do m[name] = val end
      t.mix = M.merge({ mix = t.mix }, { mix = m }).mix
    else
      t[k] = M.merge({ [k] = t[k] }, { [k] = val })[k]
    end
  end
  return t
end

-- Merge settings table `over` onto `base`, returning a new table. Named
-- tables (such as mix, palette and tune) merge key by key at every depth,
-- so a later \florasetup can adjust one engine value without repeating the
-- rest. Lists (ranges, control points) are replaced whole.
local function merge_into(base, over)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(over) do
    if type(v) == "table" and type(t[k]) == "table"
      and not is_list(v) and not is_list(t[k]) then
      t[k] = merge_into(t[k], v)
    else
      t[k] = v
    end
  end
  return t
end

-- The settings that pass to a page's spec as they are, by key -> spec
-- field. Every place that builds a spec from settings (init.lua,
-- garden.lua, tools/preview.lua) copies them with M.to_spec, so a new key
-- reaches all of them. The others are folded into these (density,
-- visitors, colourway) or set by each caller (layout, header, seed,
-- cache): M.OWN lists them, and tests/test_settings.lua holds every key
-- to one list or the other.
M.SPEC = {
  mix = "mix", ornaments = "ornaments", palette = "palette", spin = "spin", tune = "tune",
  gilt = "gilt", giltdpi = "gilt_dpi", giltenv = "gilt_env", giltlook = "gilt_look", backdrop = "backdrop",
  pattern = "pattern", edge = "pattern_edge", outer = "pattern_outer", scale = "pattern_scale",
  hero = "pattern_hero", patternpalette = "patternpalette", saturation = "pattern_saturation",
  finish = "pattern_finish", bands = "pattern_bands", bandwidth = "pattern_bandwidth", ground = "pattern_ground",
  ends = "pattern_ends", panels = "pattern_panels", lighten = "pattern_lighten",
  starfill = "pattern_starfill", gapfill = "pattern_gapfill", alternate = "pattern_alternate",
  glint = "pattern_glint", herogold = "pattern_herogold", deviant = "pattern_deviant", loose = "pattern_loose",
  [Band.WIDTH] = "perimeter_width", [Band.FLORA] = "perimeter_flora", [Band.FLORA_DENSITY] = "perimeter_density",
}
-- The pattern keys besides `pattern` itself, by key -> default. A mixer's
-- pattern state, its \florasetup line and the preview's spec all carry
-- exactly these (catalog.lua lists them as pattern_keys), and
-- tests/test_settings.lua holds every M.SPEC key naming a pattern_* field
-- to this table, so a new pattern key cannot be left out of one of them.
-- pattern.lua reads its defaults from here too. patternpalette is a
-- palette, set role by role as palette is, so it is not one of them.
M.PATTERN = { edge = "dissolve", hero = "none", outer = "bleed", scale = 1,
  saturation = 0.5, finish = "filled", bands = "auto", bandwidth = 1, ground = "auto",
  ends = "auto", panels = "auto", lighten = 0, starfill = "auto", gapfill = "auto", alternate = "auto",
  glint = "off", herogold = "off", deviant = "off", loose = "off" }
M.OWN = { layout = true, header = true, seed = true, cache = true, density = true, visitors = true, colourway = true }

-- What a "fresh" restyle (tools/preview.lua, the site's mixer) drops of a
-- page's own settings: its growth mix, inks and tuning. Every other
-- M.SPEC key is kept, so a new key is kept without being listed.
M.FRESH_DROPS = { mix = true, palette = true, patternpalette = true, spin = true, tune = true }

-- The M.SPEC keys a fresh restyle keeps, for M.from_spec.
function M.fresh_keys()
  local kept = {}
  for k in pairs(M.SPEC) do if not M.FRESH_DROPS[k] then kept[k] = true end end
  return kept
end

-- The mixer's preview of a page (site/src/lib/render.worker.js): its
-- pattern keys and its colours from the very \florasetup parts its setup
-- line writes (setup.js: patternParts, colourParts), parsed here as the
-- document parses them, so the preview paints the roles the downloaded
-- document does. "" leaves either out (flora; no colourway). Returns spec.
function M.pattern_preview(spec, pattern, colours)
  local cs = (colours and colours ~= "") and M.parse(colours) or {}
  spec.patternpalette = cs.patternpalette
  if pattern and pattern ~= "" then
    local ps = M.parse(pattern)
    spec.pattern = ps.pattern
    for k in pairs(M.PATTERN) do spec[M.SPEC[k]] = ps[k] end
  end
  return spec
end

-- Copy settings `set` onto `spec` (M.SPEC); returns spec.
function M.to_spec(set, spec)
  for k, f in pairs(M.SPEC) do spec[f] = set[k] end
  return spec
end

-- The settings a spec was made from (the inverse of M.to_spec), for
-- `only` (default: all of M.SPEC).
function M.from_spec(spec, only)
  local set = {}
  for k, f in pairs(M.SPEC) do
    if not only or only[k] then set[k] = spec[f] end
  end
  return set
end

-- Keys a later setting replaces whole rather than merging into: a new
-- pattern={...} names the pattern(s) wanted now, not weights to add.
local REPLACED = { pattern = true }

function M.merge(base, over)
  local t = merge_into(base or {}, over or {})
  for k in pairs(REPLACED) do
    if over and over[k] ~= nil then t[k] = over[k] end
  end
  return t
end

return M
