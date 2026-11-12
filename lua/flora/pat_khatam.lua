-- Khatam: eight-pointed stars, each of two squares turned 45 degrees to
-- one another, on a square lattice. An emblem pattern: opt-in
-- (patterns.lua), picked only by its own name or by the group `symbol`.
-- The stars are light, on the paper's colour, with a dot of the second
-- field at their hearts, and the gaps between them are the first field:
-- each star's cell fills its square of the lattice and lays the star over
-- it, its tips short of its neighbours'.

local K = require("flora.pat_kit")
local cos, sin, rad = math.cos, math.sin, math.rad
local STAR = 0.78

local function paint_star(pt, c, ink)
  pt:fill(c.cellsq, ink.fill[1], 1)
  pt:fill(c.star, ink.core, 1)
  pt:stroke(c.star, ink.band, ink.width, 1)
  pt:fill(c.dot, ink.fill[2], 1)
  pt:stroke(c.dot, ink.band, ink.width * 0.5, 1)
end

local function construct_star(pt, c, ink)
  pt:stroke(c.square, ink.line, 0.4, 1)
  pt:stroke(c.diamond, ink.line, 0.4, 1)
end

local function square(x, y, r, a0)
  local P = {}
  for k = 0, 3 do
    local a = rad(a0 + 90 * k)
    P[#P + 1] = { x + r * cos(a), y + r * sin(a) }
  end
  return P
end

return {
  name = "khatam",
  title = "Khatam, eight-pointed stars of two squares on a square lattice, light on a coloured ground",
  tags = { "symbol", "khatam", "star", "square" },
  roles = { "band", "core", "a", "b" },
  opt_in = true,
  scale = 28,
  width = 1.2,
  cells = function(env)
    local a = env.size
    local out = {}
    -- The star's tips, short of the square's edge so the field shows
    -- between neighbours.
    local r = a * 0.5 * STAR
    local rin = r * math.cos(rad(45)) / math.cos(rad(22.5))
    for i = math.floor(env.x0 / a) - 1, math.ceil(env.x1 / a) + 1 do
      for j = math.floor(env.y0 / a) - 1, math.ceil(env.y1 / a) + 1 do
        local x, y = i * a, j * a
        local outline = {}
        for k = 0, 7 do
          local t, u = rad(45 * k), rad(45 * k + 22.5)
          outline[#outline + 1] = { x + r * cos(t), y + r * sin(t) }
          outline[#outline + 1] = { x + rin * cos(u), y + rin * sin(u) }
        end
        local sq = { { x - a / 2, y - a / 2 }, { x + a / 2, y - a / 2 }, { x + a / 2, y + a / 2 }, { x - a / 2, y + a / 2 } }
        out[#out + 1] = { x = x, y = y, verts = sq, pad = a * 0.02, cellsq = K.path(sq), star = K.path(outline),
          dot = { { "o", x, y, a * 0.08 } },
          square = K.path(square(x, y, r, 45)), diamond = K.path(square(x, y, r, 0)),
          paint = paint_star, construct = construct_star }
      end
    end
    return out
  end,
}
