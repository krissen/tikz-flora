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
local FLOORS = { band = 0.15, fields = 0.06, band_any = 0.08 }

local cells, failures = M.run(FLOORS)
if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("matrix: %d cells, %d saturation cells, %d failures", #cells, M.saturation_cells, #failures)) end
H.check(M.saturation_cells == #require("flora.inks").colourway_order * 4, "saturation cells: " .. tostring(M.saturation_cells))
H.check(#cells == #Patterns.list * #require("flora.inks").colourway_order * 2 * 2 * 2, "matrix cells: " .. #cells)
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

H.done("pattern matrix")
