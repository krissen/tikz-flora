-- Shippō, the "seven treasures" pattern: circles on a square grid, each
-- radius half the grid's diagonal, so every circle overlaps its four
-- neighbours by a quarter and the overlaps make four-petalled flowers.
-- The overlaps, the petals, are the first field; a dot of the second
-- marks each flower's heart. A cell paints the petals it shares with its
-- right and upper neighbours, so each petal is painted once.

local K = require("flora.pat_kit")

local function paint(pt, c, ink)
  K.fill(pt, c.petals, ink.fill[1], ink, { many = true })
  K.band(pt, c.path, ink, { core = "accent" })
  K.fill(pt, c.dot, ink.fill[2], ink, { outline = true })
end

local function construct(pt, c, ink)
  pt:stroke(c.path, ink.line, 0.4, 1)
end

-- The petal two circles of radius r about (x0, y0) and (x1, y1), a apart,
-- share: an arc of each between the points where they cross.
local function petal(x0, y0, x1, y1, r)
  local a = math.atan(y1 - y0, x1 - x0)
  local q = math.pi / 4
  local c = { { "m", x0 + r * math.cos(a - q), y0 + r * math.sin(a - q) } }
  for _, s in ipairs(K.arc(x0, y0, r, a - q, a + q)) do c[#c + 1] = s end
  for _, s in ipairs(K.arc(x1, y1, r, a + math.pi - q, a + math.pi + q)) do c[#c + 1] = s end
  c[#c + 1] = { "z" }
  return c
end

return {
  name = "shippo",
  title = "Shippō (seven treasures), circles overlapping their neighbours by a quarter",
  tags = { "japanese", "circles", "lattice" },
  roles = { "band", "accent", "a", "b" },
  surface = true,
  scale = 18,
  width = 1.3, core = 0.4, bands = "strap",
  cells = function(env)
    local a = env.size
    local r = a / math.sqrt(2)
    local out = {}
    for i = math.floor(env.x0 / a) - 1, math.ceil(env.x1 / a) + 1 do
      for j = math.floor(env.y0 / a) - 1, math.ceil(env.y1 / a) + 1 do
        local x, y = i * a, j * a
        out[#out + 1] = { x = x, y = y, verts = K.ring(x, y, r), circle = { x, y, r }, pad = a * 0.07, path = { { "o", x, y, r } },
          petals = { petal(x, y, x + a, y, r), petal(x, y, x, y + a, r) },
          tile = { { x - a / 2, y - a / 2 }, { x + a / 2, y - a / 2 }, { x + a / 2, y + a / 2 }, { x - a / 2, y + a / 2 } },
          dot = { { "o", x + a / 2, y + a / 2, a * 0.07 } }, sweep = { x, y, math.pi / 2 }, paint = paint, construct = construct }
      end
    end
    return out
  end,
}
