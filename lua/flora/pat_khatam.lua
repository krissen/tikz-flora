-- Khatam: eight-pointed stars, each of two equal squares turned 45 degrees
-- to one another, on a square lattice, their tips meeting their
-- neighbours' so that the stars tile the plane with crosses with pointed
-- arms between them. An emblem pattern: opt-in (patterns.lua), picked only
-- by its own name or by the group `symbol`.
--
-- Sources (ORDER #12 of the geometry work, read 2026-11-13):
--   The regular eight-pointed star, sixteen equal sides and a right angle
--   at every tip, is called a khatem: B. Wichmann, the introduction to
--   the Tiling Search database (2021), https://tilingsearch.mit.edu/intro.pdf,
--   p. 1.
--   Repeated, the star in its square brings out the cross between, and
--   either may be the foreground: D. Wade, "Pattern No 6 (Commentary): One
--   Common Motif", https://geometricdesign.co.uk/is6_fr2.htm; and "The 8
--   pointed star when tessellated produces a pattern of stars and
--   crosses": Museum of Design Excellence, Mumbai, "Erogenius Eight Pointed
--   Star", Google Arts & Culture.
--
-- The geometry. Two equal squares of circumradius r about one centre, one
-- on its point and one square to the page: a corner of the one stands out
-- past the other's side as a right isosceles triangle of height
-- r (1 - 1/sqrt 2). With r half the lattice's period a the tips meet, and
-- what is left between four stars is a cross whose arms are
-- a (2 - sqrt 2) / 4 wide on each side of its axis.
--
-- The star is the cell; a cross lies between four stars and is laid only
-- when all four are kept (pattern.lua's plates, `between`), so the field
-- ends along the stars' own outline. Thin dark lines throughout. The
-- figure and gaps keys (Settings.PATTERN) choose the colours:
--   figure=whole (the default)  the whole star in the first field
--   figure=split                the square on its point in the first field
--                               and the other square's corners in the
--                               second; the crosses the paper
--   gaps=field (the default)    the crosses in the second field
--   gaps=paper                  the crosses the paper

local K = require("flora.pat_kit")
local cos, sin, rad, sqrt = math.cos, math.sin, math.rad, math.sqrt

local function square(x, y, r, a0)
  local P = {}
  for k = 0, 3 do
    local a = rad(a0 + 90 * k)
    P[#P + 1] = { x + r * cos(a), y + r * sin(a) }
  end
  return P
end

local function paint(pt, c, ink)
  if c.split then
    K.fill(pt, c.diamond, ink.fill[1], ink)
    K.fill(pt, c.corners, ink.fill[2], ink, { many = true })
    K.band(pt, c.corners, ink, { core = false, many = true, w = 0.6 })
  else
    K.fill(pt, c.star, ink.fill[1], ink)
  end
  K.band(pt, c.star, ink, { core = false, w = 0.6 })
end

local function construct(pt, c, ink)
  pt:stroke(c.square, ink.line, 0.4, 1)
  pt:stroke(c.diamond, ink.line, 0.4, 1)
end

-- The star's outline about (x, y), tip radius r: sixteen points, a tip and
-- an inner corner by turns.
local function star(x, y, r)
  local rin = r * cos(rad(45)) / cos(rad(22.5))
  local P = {}
  for k = 0, 7 do
    local t, u = rad(45 * k), rad(45 * k + 22.5)
    P[#P + 1] = { x + r * cos(t), y + r * sin(t) }
    P[#P + 1] = { x + rin * cos(u), y + rin * sin(u) }
  end
  return P
end

-- The cross whose centre is (X, Y), between four stars a apart.
local function cross(X, Y, a)
  local h, w = a / 2, a * (2 - sqrt(2)) / 4
  local P = {}
  for k = 0, 3 do
    local ca, sa = cos(rad(90 * k)), sin(rad(90 * k))
    local function at(u, v) return { X + u * ca - v * sa, Y + u * sa + v * ca } end
    P[#P + 1] = at(h, 0)
    P[#P + 1] = at(h - w, w)
    P[#P + 1] = at(w, w)
    P[#P + 1] = at(w, h - w)
  end
  return P
end

local M = {
  name = "khatam",
  title = "Khatam, eight-pointed stars of two squares tiling the plane with crosses between them",
  tags = { "symbol", "khatam", "star", "square" },
  roles = { "band", "a", "b" },
  surface = true,
  opt_in = true,
  scale = 28,
  width = 1.2, bands = "strap",
  figure = "whole", gaps = "field",
}

-- The outlines, for tests/pattern_matrix.lua's tiling check.
M.star, M.cross = star, cross

function M.cells(env)
  local a = env.size
  local style = env.style or {}
  local split = style.figure == "split"
  local crosses = not split and style.gaps ~= "paper"
  local r = a / 2
  local q = r / sqrt(2)
  local out = {}
  for i = math.floor(env.x0 / a) - 1, math.ceil(env.x1 / a) + 1 do
    for j = math.floor(env.y0 / a) - 1, math.ceil(env.y1 / a) + 1 do
      local x, y = i * a, j * a
      local outline = star(x, y, r)
      local corners = {}
      for _, s in ipairs({ { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }) do
        local sx, sy = s[1], s[2]
        corners[#corners + 1] = K.path({ { x + sx * q, y + sy * q }, { x + sx * q, y + sy * (r - q) }, { x + sx * (r - q), y + sy * q } })
      end
      local plates = {}
      if crosses then
        plates[1] = { K.path(cross(x + r, y + r, a)), "b",
          between = { { x, y }, { x + a, y }, { x, y + a }, { x + a, y + a } } }
      end
      out[#out + 1] = { x = x, y = y, verts = outline, pad = a * 0.02, plates = plates, under = K.path(outline),
        star = K.path(outline), diamond = K.path(square(x, y, r, 0)), square = K.path(square(x, y, r, 45)),
        corners = corners, split = split, paint = paint, construct = construct }
    end
  end
  return out
end

return M
