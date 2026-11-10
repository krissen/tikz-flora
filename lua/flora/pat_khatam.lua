-- Khatam: eight-pointed stars, each of two squares turned 45 degrees to
-- one another, on a square lattice with a small dot in each gap between
-- four stars. An emblem pattern: opt-in (patterns.lua), picked only by
-- its own name or by the group `symbol`. A star is a cell, and so is
-- each dot.

local K = require("flora.pat_kit")
local cos, sin, rad = math.cos, math.sin, math.rad

local function paint_star(pt, c, ink)
  pt:fill(c.square, ink.fill[1], 1)
  pt:fill(c.diamond, ink.fill[2], 1)
  pt:stroke(c.square, ink.band, ink.width, 1)
  pt:stroke(c.diamond, ink.band, ink.width, 1)
end

local function construct_star(pt, c, ink)
  pt:stroke(c.square, ink.line, 0.4, 1)
  pt:stroke(c.diamond, ink.line, 0.4, 1)
end

local function paint_dot(pt, c, ink)
  pt:fill(c.path, ink.accent, 1)
  pt:stroke(c.path, ink.band, ink.width * 0.5, 1)
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
  title = "Khatam, eight-pointed stars of two squares on a square lattice, a dot in each gap",
  tags = { "symbol", "khatam", "star", "square" },
  opt_in = true,
  scale = 28,
  width = 1.2,
  cells = function(env)
    local a = env.size
    local out = {}
    local r = a * 0.5
    local rin = a * 0.5 * math.cos(rad(45)) / math.cos(rad(22.5))
    for i = math.floor(env.x0 / a) - 1, math.ceil(env.x1 / a) + 1 do
      for j = math.floor(env.y0 / a) - 1, math.ceil(env.y1 / a) + 1 do
        local x, y = i * a, j * a
        local outline = {}
        for k = 0, 7 do
          local t, u = rad(45 * k), rad(45 * k + 22.5)
          outline[#outline + 1] = { x + r * cos(t), y + r * sin(t) }
          outline[#outline + 1] = { x + rin * cos(u), y + rin * sin(u) }
        end
        out[#out + 1] = { x = x, y = y, verts = outline, pad = a * 0.02,
          square = K.path(square(x, y, r, 45)), diamond = K.path(square(x, y, r, 0)),
          paint = paint_star, construct = construct_star }
        local dx, dy, dr = x + a / 2, y + a / 2, a * 0.08
        out[#out + 1] = { x = dx, y = dy, verts = K.ring(dx, dy, dr, 8), circle = { dx, dy, dr },
          path = { { "o", dx, dy, dr } }, paint = paint_dot, construct = paint_dot }
      end
    end
    return out
  end,
}
