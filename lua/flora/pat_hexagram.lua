-- Hexagrams (two triangles, one turned half a turn) on a triangular
-- lattice, each tip touching the tip of a neighbour. An emblem pattern: it
-- is opt-in (patterns.lua), picked only by its own name or by the group
-- `symbol`.

local K = require("flora.pat_kit")
local sqrt, cos, sin, rad = math.sqrt, math.cos, math.sin, math.rad

local function paint(pt, c, ink)
  K.fill(pt, c.up, ink.fill[1], ink)
  K.fill(pt, c.down, ink.fill[2], ink)
  K.band(pt, c.up, ink, { core = false })
  K.band(pt, c.down, ink, { core = false })
end

local function construct(pt, c, ink)
  pt:stroke(c.up, ink.line, 0.4, 1)
  pt:stroke(c.down, ink.line, 0.4, 1)
end

local function triangle(x, y, R, a0)
  local P = {}
  for k = 0, 2 do
    local a = rad(a0 + 120 * k)
    P[#P + 1] = { x + R * cos(a), y + R * sin(a) }
  end
  return P
end

return {
  name = "hexagram_lattice",
  title = "Hexagrams on a triangular lattice, tips touching",
  tags = { "symbol", "hexagram", "triangular", "star" },
  roles = { "band", "a", "b" },
  surface = true,
  opt_in = true,
  scale = 30,
  width = 1.2, bands = "strap",
  cells = function(env)
    local d = env.size
    local h = d * sqrt(3) / 2
    local R = d / sqrt(3)
    local out = {}
    for j = math.floor(env.y0 / h) - 1, math.ceil(env.y1 / h) + 1 do
      for i = math.floor(env.x0 / d) - 2, math.ceil(env.x1 / d) + 2 do
        local x, y = d * (i + (j % 2) / 2), h * j
        local star = {}
        for k = 0, 5 do
          local a = rad(90 + 60 * k)
          star[#star + 1] = { x + R * cos(a), y + R * sin(a) }
          local b = rad(120 + 60 * k)
          star[#star + 1] = { x + R / sqrt(3) * cos(b), y + R / sqrt(3) * sin(b) }
        end
        -- The lattice's hexagon round the star, for a ground under it.
        local hex = {}
        for k = 0, 5 do
          local a = rad(30 + 60 * k)
          hex[#hex + 1] = { x + R * cos(a), y + R * sin(a) }
        end
        out[#out + 1] = { x = x, y = y, verts = star, pad = d * 0.02, under = K.path(hex),
          up = K.path(triangle(x, y, R, 90)), down = K.path(triangle(x, y, R, 270)),
          paint = paint, construct = construct }
      end
    end
    return out
  end,
}
