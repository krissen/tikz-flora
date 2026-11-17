-- The pattern colour invariants (tests/pattern_matrix.lua) over every
-- pattern x colourway x backdrop x finish, and proof that the matrix fails
-- when an invariant is broken.
local H = dofile("tests/helper.lua")
local M = dofile("tests/pattern_matrix.lua")
local Patterns = require("flora.patterns")
local Pattern = require("flora.pattern")

-- The floors, set after measuring the colourways (geo-roles3 report). The
-- band stands 0.18 to 0.76 off its surface in OKLab L; the lowest is
-- tsuki-mi's, whose soft contour is the mocks' own (0.25 off their ochre,
-- 0.11 off their green). The fields lie 0.15 to 0.22 apart in OKLab. The
-- floors sit below both and catch a band or a field that loses itself.
-- band_any holds the band off every surface it lies on, a surface's second
-- field and ground too: clear above a band that cannot be seen (0.004, a
-- band lit on a dark ground onto the ochre field of the rosette lattice)
-- and clear below the lowest composition approved as seen (0.105,
-- tsuki-mi's contour on its green field on the dark backdrop).
-- No kept cell stands alone in any cell of the matrix (measured: 0 % for
-- every pattern, ORDER #10 of the geometry work), so none may.
local FLOORS = { band = 0.15, fields = 0.06, band_any = 0.08, isolated = 0 }

local cells, failures = M.run(FLOORS)
if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("matrix: %d cells, %d saturation cells, %d failures", #cells, M.saturation_cells, #failures)) end
H.check(M.saturation_cells == #require("flora.inks").colourway_order * 4, "saturation cells: " .. tostring(M.saturation_cells))
H.check(#cells == #Patterns.list * #require("flora.inks").colourway_order * 3 * 2 * 2, "matrix cells: " .. #cells)
for _, f in ipairs(failures) do H.check(false, f) end

-- The band's distance from every surface it lies on, by colourway and
-- backdrop (min, p10, median), and the cells under the band floor, so the
-- figure shows when it does not fail.
if os.getenv("FLORA_MATRIX_VERBOSE") then
  local by, low = {}, {}
  for _, c in ipairs(cells) do
    local k = c.colourway .. " " .. c.backdrop
    by[k] = by[k] or {}
    table.insert(by[k], c.band_any)
    if c.band_any < FLOORS.band then
      low[#low + 1] = string.format("  %.3f %s %s ground=%s %s %s on %s", c.band_any, c.pattern, c.colourway, c.ground, c.backdrop, c.finish, c.band_any_on)
    end
  end
  local keys = {}
  for k in pairs(by) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = by[k]
    table.sort(v)
    print(string.format("band_any %-18s min %.3f p10 %.3f median %.3f (%d cells)", k, v[1], v[math.max(1, math.ceil(#v * 0.1))], v[math.ceil(#v / 2)], #v))
  end
  print(#low .. " cells with band_any under " .. FLOORS.band .. ":")
  table.sort(low)
  for _, l in ipairs(low) do print(l) end
end

-- Each mutation breaks one invariant; the matrix must say so.
local function caught(what, name, mutate, restore)
  mutate()
  local ok, _, fs = pcall(function() return M.run(FLOORS, function(n) return n == name end) end)
  restore()
  local found, n = false, 0
  for _, f in ipairs(ok and fs or {}) do if f:find(": " .. what .. ":", 1, true) then found = true; n = n + 1 end end
  H.check(ok and found, "the matrix missed a broken " .. what .. " invariant")
  if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation %s on %s: %d of %d failures", what, name, n, ok and #fs or -1)) end
end

-- A module that picks an ink itself.
local stars = Patterns.by_name.stars_8_4
local cells0 = stars.cells
caught("roles", "stars_8_4", function()
  stars.cells = function(env)
    local out = cells0(env)
    for _, c in ipairs(out) do
      local paint = c.paint
      c.paint = function(pt, cell, ink) paint(pt, cell, ink); pt:stroke(cell.path, { 0.9, 0.1, 0.1 }, 1, 1) end
    end
    return out
  end
end, function() stars.cells = cells0 end)

-- A role that swaps its lightness order with the ground on the dark backdrop.
local role_inks = Pattern.role_inks
caught("order", "asanoha", function()
  Pattern.role_inks = function(rng, p, spec)
    local base = role_inks(rng, p, spec)
    if spec.backdrop == "dark" and base.ground then base.band, base.ground = base.ground, base.band end
    return base
  end
end, function() Pattern.role_inks = role_inks end)

-- A hole in the ground.
local asa = Patterns.by_name.asanoha
local asa_cells = asa.cells
caught("ground", "asanoha", function()
  asa.cells = function(env)
    local out = asa_cells(env)
    for i, c in ipairs(out) do if i % 5 == 0 then c.tile = nil end end
    return out
  end
end, function() asa.cells = asa_cells end)

-- A fill under the lines finish.
local kikko = Patterns.by_name.kikko
local kikko_cells = kikko.cells
caught("nofill", "kikko", function()
  kikko.cells = function(env)
    local out = kikko_cells(env)
    for _, c in ipairs(out) do
      local paint = c.paint
      c.paint = function(pt, cell, ink) paint(pt, cell, ink); pt:fill(cell.inner, ink.fill[1], 1) end
    end
    return out
  end
end, function() kikko.cells = kikko_cells end)

-- Fields that cannot be told apart.
caught("fields", "kikko", function()
  Pattern.role_inks = function(rng, p, spec)
    local base = role_inks(rng, p, spec)
    base.fill2 = base.fill1
    return base
  end
end, function() Pattern.role_inks = role_inks end)

-- A band that loses its contrast.
caught("contrast", "truchet", function()
  Pattern.role_inks = function(rng, p, spec)
    local base = role_inks(rng, p, spec)
    base.band = require("flora.paint").palette.paper
    return base
  end
end, function() Pattern.role_inks = role_inks end)

-- A share the palette gives replacing the saturation's, as it did before
-- saturation scaled it (tsuki-mi's and usu-zumi's fields stay coloured).
local role_share = Pattern.role_share
caught("saturation", "kikko", function()
  Pattern.role_share = function(r, vs, sat) return vs or role_share(r, nil, sat) end
end, function() Pattern.role_share = role_share end)

-- A band lit on a surface's dark ground, as before a band's lightness was
-- set against the surface it lies on: on the rosette lattice in tsuki-mi
-- it lands on the ochre field's lightness. Put back into pattern.lua's
-- source; both band floors must catch it.
for _, what in ipairs({ "contrast", "vanish" }) do
  local real = package.loaded["flora.pattern"]
  caught(what, "rosette_lattice", function()
    local f = io.open("lua/flora/pattern.lua")
    local src = f:read("a")
    f:close()
    local old = "Color.lightness(base.ground) < DARK and not p.surface then"
    local i, j = src:find(old, 1, true)
    H.check(i ~= nil, "mutation: the surface rule is gone from pattern.lua")
    if i then
      package.loaded["flora.pattern"] = assert(load(src:sub(1, i - 1) .. "Color.lightness(base.ground) < DARK then" .. src:sub(j + 1),
        "@pattern.lua (mutated)"))()
    end
  end, function() package.loaded["flora.pattern"] = real end)
end

-- The ground's edge: a ground on paper under ground=auto.
caught("edge", "rosette_lattice", function()
  Pattern.role_inks = function(rng, p, spec)
    local base = role_inks(rng, p, spec)
    base.ground = base.ground or require("flora.paint").palette.gold
    return base
  end
end, function() Pattern.role_inks = role_inks end)

-- A kolam dot left without its loop, and a strand ending loose: the
-- lines cut cell by cell again.
local kolam = Patterns.by_name.sikku_kolam
caught("units", "sikku_kolam", function() kolam.ends, kolam.panels = "cut", "off" end,
  function() kolam.ends, kolam.panels = "closed", "on" end)
local knot = Patterns.by_name.celtic_knot
caught("units", "celtic_knot", function() knot.ends = "cut" end, function() knot.ends = "closed" end)

-- khatam's stars back at their old size, alone on the lattice: the stars
-- and crosses no longer fill the plane.
local khatam = Patterns.by_name.khatam
local khatam_cells = khatam.cells
caught("tiling", "khatam", function()
  khatam.cells = function(env)
    local out = khatam_cells(env)
    for _, c in ipairs(out) do
      local P = khatam.star(c.x, c.y, env.size * 0.39)
      c.star = require("flora.pat_kit").path(P)
    end
    return out
  end
end, function() khatam.cells = khatam_cells end)

-- hexagram's star in two colours again: the up triangle in one field, the
-- down triangle over it in the other.
local hexagram = Patterns.by_name.hexagram_lattice
local hexagram_cells = hexagram.cells
caught("onecolour", "hexagram_lattice", function()
  hexagram.cells = function(env)
    local out = hexagram_cells(env)
    for _, c in ipairs(out) do
      local K = require("flora.pat_kit")
      c.paint = function(pt, cell, ink)
        K.fill(pt, cell.up, ink.fill[1], ink)
        K.fill(pt, cell.down, ink.fill[2], ink)
        K.band(pt, cell.star, ink, { core = false, w = 0.6 })
      end
    end
    return out
  end
end, function() hexagram.cells = hexagram_cells end)

-- Cells standing off the ground's panel again: the field no longer holds
-- a cell to the panel, nor a turn to the field's side.
do
  local on_panel = Pattern.on_panel
  caught("onpanel", "sikku_kolam", function() Pattern.on_panel = function() return true end end,
    function() Pattern.on_panel = on_panel end)
end

-- A hole in the field: one hexagram star in eleven placed as though it
-- reached into the text, its neighbours kept round it.
local hex_cells2 = hexagram.cells
caught("holes", "hexagram_lattice", function()
  hexagram.cells = function(env)
    local out = hex_cells2(env)
    for i, c in ipairs(out) do if i % 11 == 0 then c.pad = 1000 end end
    return out
  end
end, function() hexagram.cells = hex_cells2 end)

-- A rhomb between two stars drawn a fifth larger than the gap it fills,
-- out past the stars' outlines.
caught("between", "hexagram_lattice", function()
  hexagram.cells = function(env)
    local out = hex_cells2(env)
    local K = require("flora.pat_kit")
    for _, c in ipairs(out) do
      for _, pl in ipairs(c.plates or {}) do
        local P = {}
        for _, q in ipairs(pl[1]) do if q[1] == "m" or q[1] == "l" then P[#P + 1] = { q[2], q[3] } end end
        local cx, cy = 0, 0
        for _, q in ipairs(P) do cx, cy = cx + q[1] / #P, cy + q[2] / #P end
        pl[1] = K.path(K.scaled(P, cx, cy, 1.2))
      end
    end
    return out
  end
end, function() hexagram.cells = hex_cells2 end)

-- The knot's field panel: no strand ends loose in any layout.
local kcells, kfails = M.knot()
if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("knot field: %d cells, %d failures", #kcells, #kfails)) end
H.check(#kcells == 1 * 4 * 2 * 2, "knot field cells: " .. #kcells)
for _, f in ipairs(kfails) do H.check(false, f) end
-- Its cells thinned out toward the text again, as an ordinary field's:
-- the strands end loose where cells fall away.
do
  local mutated = 0
  local knot_cells = knot.cells
  knot.cells = function(env)
    local out = knot_cells(env)
    for _, c in ipairs(out) do c.fixed = nil end
    return out
  end
  local _, fs = M.knot(function(n, layout) return n == "celtic_knot" and layout == "surround" end)
  knot.cells = knot_cells
  for _, f in ipairs(fs) do if f:find(": units:", 1, true) then mutated = mutated + 1 end end
  H.check(mutated > 0, "the knot field missed strands ending loose")
  if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation units on the knot field: %d of %d failures", mutated, #fs)) end
end

-- finish=lacquer: a panel, a gold line, keys set on the page first, and
-- nothing changed on a pattern without a ground.
do
  local lc, lf = M.lacquer()
  H.check(#lc == #Patterns.list * 3 * 2, "lacquer cells: " .. #lc)
  for _, f in ipairs(lf) do H.check(false, f) end
  if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("lacquer: %d cells, %d failures", #lc, #lf)) end
  local finish_spec = Pattern.finish_spec
  local function mutant(name, fn, only)
    Pattern.finish_spec = fn
    local _, fs = M.lacquer(function(n) return n == only end)
    Pattern.finish_spec = finish_spec
    H.check(#fs > 0, "the lacquer check missed " .. name)
    if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation lacquer %s: %d failures", name, #fs)) end
  end
  -- The ground left to the colourway's own edge, not laid as a panel.
  mutant("a ground not laid as a panel", function(spec, p)
    local out, w = finish_spec(spec, p)
    if out ~= spec and not w then out.pattern_ground = "cells" end
    return out, w
  end, "asanoha")
  -- A key set on the page overridden.
  mutant("a page's own ground overridden", function(spec, p)
    local out, w = finish_spec(spec, p)
    if out ~= spec and not w then out.pattern_ground = "panel" end
    return out, w
  end, "sikku_kolam")
  -- The band fitted to the dark ground again, a colour made from the gold
  -- rather than the gold ink: put back into pattern.lua's source.
  do
    local real = package.loaded["flora.pattern"]
    local f = io.open("lua/flora/pattern.lua")
    local src = f:read("a")
    f:close()
    local old = "if base.band ~= pal.gold then base.band = Color.on_ground"
    local i, j = src:find(old, 1, true)
    H.check(i ~= nil, "mutation: the gold rule is gone from pattern.lua")
    if i then
      package.loaded["flora.pattern"] = assert(load(src:sub(1, i - 1) .. "if true then base.band = Color.on_ground" .. src:sub(j + 1), "@pattern.lua (mutated)"))()
      local _, fs = M.lacquer(function(n) return n == "asanoha" or n == "sikku_kolam" end)
      package.loaded["flora.pattern"] = real
      H.check(#fs > 0, "the lacquer check missed a band fitted to the ground")
      if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation lacquer band fitted to the ground: %d failures", #fs)) end
    end
  end
  -- The rosette lattice claiming lacquer again: its page is no longer the
  -- filled one.
  do
    local rl = Patterns.by_name.rosette_lattice
    rl.finishes = { "lacquer" }
    local _, fs = M.lacquer(function(n) return n == "rosette_lattice" end)
    rl.finishes = nil
    H.check(#fs > 0, "the lacquer check missed the rosette lattice taking lacquer")
    if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation lacquer on rosette_lattice: %d failures", #fs)) end
  end
  -- Lacquer's line work put on a pattern without a ground.
  mutant("a half look on a pattern without a ground", function(spec, p)
    local out, w = finish_spec(spec, p)
    if w then out.pattern_bands, out.pattern_bandwidth = "line", 0.5 end
    return out, w
  end, "kikko")
end

-- density=0 paints nothing of the pattern; and the check fails when a
-- placed panel's cells (celtic_knot's) or the ground's panel paint anyway,
-- the faults put back into pattern.lua's source.
do
  local pages, fs = M.density0()
  H.check(pages == 360, "density0 pages: " .. pages)
  for _, f in ipairs(fs) do H.check(false, f) end
  if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("density0: %d pages, %d failures", pages, #fs)) end
  local real = package.loaded["flora.pattern"]
  local f = io.open("lua/flora/pattern.lua")
  local src = f:read("a")
  f:close()
  for _, m in ipairs({
    { "the knot's fixed cells", "local ok = dens > 0 and d >= gap", "local ok = d >= gap", "celtic_knot" },
    { "an empty panel", "if #grounded > 0 then", "if true then", "asanoha" },
  }) do
    local i, j = src:find(m[2], 1, true)
    H.check(i ~= nil, "mutation: the line is gone from pattern.lua: " .. m[2])
    if i then
      package.loaded["flora.pattern"] = assert(load(src:sub(1, i - 1) .. m[3] .. src:sub(j + 1), "@pattern.lua (mutated)"))()
      local _, mf = M.density0(function(n) return n == m[4] end)
      package.loaded["flora.pattern"] = real
      H.check(#mf > 0, "the density0 check missed " .. m[1])
      if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation density0 %s: %d failures", m[1], #mf)) end
    end
  end
end

-- A key written out at its default paints the page the key left out
-- paints, and the check fails when lacquer fills in its own values only
-- for keys left out.
do
  local pages, fs = M.defaults()
  H.check(pages > 0, "defaults painted no page")
  for _, f in ipairs(fs) do H.check(false, f) end
  if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("defaults: %d pages, %d failures", pages, #fs)) end
  local real = package.loaded["flora.pattern"]
  local f = io.open("lua/flora/pattern.lua")
  local src = f:read("a")
  f:close()
  local line = "return v == nil or v == Settings.PATTERN[k] or tonumber(v) ~= nil and tonumber(v) == tonumber(Settings.PATTERN[k])"
  local i, j = src:find(line, 1, true)
  H.check(i ~= nil, "mutation: the line is gone from pattern.lua: " .. line)
  if i then
    package.loaded["flora.pattern"] = assert(load(src:sub(1, i - 1) .. "return v == nil" .. src:sub(j + 1), "@pattern.lua (mutated)"))()
    local _, mf = M.defaults()
    package.loaded["flora.pattern"] = real
    H.check(#mf > 0, "the defaults check missed lacquer reading a written default as the page's own choice")
    if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation defaults lacquer fills in only keys left out: %d failures", #mf)) end
  end
end

-- A unit falls on one draw, and the check fails when each of its cells is
-- judged on a draw of its own again.
do
  local pages, units, fs = M.unitdraw(function(n) return n == "sikku_kolam" or n == "celtic_knot" end)
  H.check(pages == 288, "unitdraw pages: " .. pages)
  H.check(units > 0, "unitdraw found no kept unit")
  for _, f in ipairs(fs) do H.check(false, f) end
  if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("unitdraw: %d pages, %d kept units, %d failures", pages, units, #fs)) end
  local real = package.loaded["flora.pattern"]
  local f = io.open("lua/flora/pattern.lua")
  local src = f:read("a")
  f:close()
  local line = "        r = g.r\n"
  local i, j = src:find(line, 1, true)
  H.check(i ~= nil, "mutation: the line is gone from pattern.lua: r = g.r")
  if i then
    package.loaded["flora.pattern"] = assert(load(src:sub(1, i - 1) .. src:sub(j + 1), "@pattern.lua (mutated)"))()
    local _, _, mf = M.unitdraw(function(n) return n == "sikku_kolam" end)
    package.loaded["flora.pattern"] = real
    H.check(#mf > 0, "the unitdraw check missed cells of a unit judged on draws of their own")
    if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation unitdraw a draw per cell: %d failures", #mf)) end
  end
end

-- The ground under a cell is never laid after it: by the progression's
-- births on every pattern with a ground, and in grow frames on asanoha;
-- and the check fails when the panel waits for the first cell the
-- generator lists, or a piece for its cell's painting.
do
  local pages, checked, _, fs = M.groundtime()
  H.check(pages == 144, "groundtime pages: " .. pages)
  H.check(checked > 0, "groundtime checked no cells")
  for _, f in ipairs(fs) do H.check(false, f) end
  local fp, _, _, ffs = M.groundtime(function(n) return n == "asanoha" end, M.GROW)
  for _, f in ipairs(ffs) do H.check(false, f) end
  if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("groundtime: %d pages, %d cell parts, %d failures; frames on asanoha: %d pages, %d failures", pages, checked, #fs, fp, #ffs)) end
  local real = package.loaded["flora.pattern"]
  local f = io.open("lua/flora/pattern.lua")
  local src = f:read("a")
  f:close()
  local line = "if plate(g.anchor, g.at, "
  for _, m in ipairs({
    { "the panel laid with the first cell listed", "if plate(g.anchor, g.form == \"panel\" and g.k.painted or g.at, " },
    { "a piece laid with its cell's painting", "if plate(g.anchor, g.form == \"piece\" and g.k.painted or g.at, " },
  }) do
    local i, j = src:find(line, 1, true)
    H.check(i ~= nil, "mutation: the line is gone from pattern.lua: " .. line)
    if i then
      package.loaded["flora.pattern"] = assert(load(src:sub(1, i - 1) .. m[2] .. src:sub(j + 1), "@pattern.lua (mutated)"))()
      local _, _, _, mf = M.groundtime(function(n) return n == "asanoha" end, { 0.1 })
      package.loaded["flora.pattern"] = real
      H.check(#mf > 0, "the groundtime check missed " .. m[1])
      if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation groundtime %s: %d failures", m[1], #mf)) end
    end
  end
end

-- A faded cell fades into what lies under it, the ground or the page, and
-- the check fails when every cell fades toward the page again.
do
  local pages, compared, fs = M.fadeunder()
  H.check(pages == 144, "fadeunder pages: " .. pages)
  H.check(compared > 0, "fadeunder compared no colours")
  for _, f in ipairs(fs) do H.check(false, f) end
  if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("fadeunder: %d pages, %d faded colours, %d failures", pages, compared, #fs)) end
  local real = package.loaded["flora.pattern"]
  local f = io.open("lua/flora/pattern.lua")
  local src = f:read("a")
  f:close()
  local line = "to = to or (not hero and base.fade) or pal.paper"
  local i, j = src:find(line, 1, true)
  H.check(i ~= nil, "mutation: the line is gone from pattern.lua: " .. line)
  if i then
    package.loaded["flora.pattern"] = assert(load(src:sub(1, i - 1) .. "to = (not hero and base.fade) or pal.paper" .. src:sub(j + 1), "@pattern.lua (mutated)"))()
    local _, _, mf = M.fadeunder()
    package.loaded["flora.pattern"] = real
    H.check(#mf > 0, "the fadeunder check missed cells faded toward the page over a ground")
    if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation fadeunder toward the page: %d failures", #mf)) end
  end
end

-- A field woven again at its edge keeps the edge's treatment, and the
-- check fails when the woven cells are all painted whole again.
do
  local pages, compared, fs = M.reweave()
  H.check(pages == 480, "reweave pages: " .. pages)
  H.check(compared > 0, "reweave compared no cells")
  for _, f in ipairs(fs) do H.check(false, f) end
  if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("reweave: %d pages, %d cells compared, %d failures", pages, compared, #fs)) end
  local real = package.loaded["flora.pattern"]
  local f = io.open("lua/flora/pattern.lua")
  local src = f:read("a")
  f:close()
  local line = "kept[#kept + 1] = { cell = v.c, a = v.a,"
  local i, j = src:find(line, 1, true)
  H.check(i ~= nil, "mutation: the line is gone from pattern.lua: " .. line)
  if i then
    package.loaded["flora.pattern"] = assert(load(src:sub(1, i - 1) .. "kept[#kept + 1] = { cell = v.c, a = 1," .. src:sub(j + 1), "@pattern.lua (mutated)"))()
    local _, _, mf = M.reweave(function(n) return n == "sikku_kolam" end)
    package.loaded["flora.pattern"] = real
    H.check(#mf > 0, "the reweave check missed woven cells painted whole")
    if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation reweave a = 1: %d failures", #mf)) end
  end
end

-- An alias paints as the pattern it is kept for, byte for byte, named in
-- a spec and in a setup line; and the check fails when the field stops
-- reading the alias (patterns.lua's weight).
local ALIASES = { celtic_panels = "celtic_knot" }
do
  local n, bad = M.aliases(ALIASES)
  H.check(n == 4, "alias pages compared: " .. n)
  for _, b in ipairs(bad) do H.check(false, "alias: " .. b) end
  if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("aliases: %d pages, %d differ", n, #bad)) end
  local weight = Patterns.weight
  Patterns.weight = function(weights, p)
    if weights[p.name] ~= nil then return weights[p.name] end
    return weight(setmetatable({}, { __index = function(_, k) if not ALIASES[k] then return weights[k] end end }), p)
  end
  local _, bad2 = M.aliases(ALIASES)
  Patterns.weight = weight
  H.check(#bad2 > 0, "the alias check missed an alias the field no longer reads")
  if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation alias: %d of 4 pages differ", #bad2)) end
end

-- Cells standing alone: one cell in 23 kept.
local kikko_cells2 = kikko.cells
caught("fragments", "kikko", function()
  kikko.cells = function(env)
    local out, sparse = kikko_cells2(env), {}
    for i, c in ipairs(out) do if i % 23 == 0 then sparse[#sparse + 1] = c end end
    return sparse
  end
end, function() kikko.cells = kikko_cells2 end)

H.done("pattern matrix")
