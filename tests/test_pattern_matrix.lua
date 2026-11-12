-- The pattern colour invariants (tests/pattern_matrix.lua) over every
-- pattern x colourway x backdrop x finish, and proof that the matrix fails
-- when an invariant is broken.
local H = dofile("tests/helper.lua")
local M = dofile("tests/pattern_matrix.lua")
local Patterns = require("flora.patterns")
local Pattern = require("flora.pattern")

-- The floors, set after measuring the colourways (geo-roles3 report): the
-- band stands at least 0.45 off its surface in OKLab L in every cell, the
-- fields at least 0.10 apart (charcoal's greys the closest). The floors
-- leave room below those and catch a role that loses its contrast.
local FLOORS = { band = 0.30, fields = 0.06 }

local cells, failures = M.run(FLOORS)
if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("matrix: %d cells, %d failures", #cells, #failures)) end
H.check(#cells == #Patterns.list * #require("flora.inks").colourway_order * 2 * 2, "matrix cells: " .. #cells)
for _, f in ipairs(failures) do H.check(false, f) end

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

H.done("pattern matrix")
