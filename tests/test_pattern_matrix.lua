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
