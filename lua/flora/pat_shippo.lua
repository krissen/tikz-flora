-- Shippō, the "seven treasures" pattern: circles on a square grid, each
-- radius half the grid's diagonal, so every circle overlaps its four
-- neighbours by a quarter and the overlaps make four-petalled flowers.

local K = require("flora.pat_kit")

local function paint(pt, c, ink)
  pt:stroke(c.path, ink.band, ink.width, 1)
  pt:stroke(c.path, ink.accent, ink.width * 0.4, 1)
  pt:fill(c.dot, ink.fill[1], 1)
end

local function construct(pt, c, ink)
  pt:stroke(c.path, ink.line, 0.4, 1)
end

return {
  name = "shippo",
  title = "Shippō (seven treasures), circles overlapping their neighbours by a quarter",
  tags = { "japanese", "circles", "lattice" },
  scale = 18,
  width = 1.3,
  cells = function(env)
    local a = env.size
    local r = a / math.sqrt(2)
    local out = {}
    for i = math.floor(env.x0 / a) - 1, math.ceil(env.x1 / a) + 1 do
      for j = math.floor(env.y0 / a) - 1, math.ceil(env.y1 / a) + 1 do
        local x, y = i * a, j * a
        out[#out + 1] = { x = x, y = y, verts = K.ring(x, y, r), circle = { x, y, r }, pad = a * 0.07, path = { { "o", x, y, r } },
          dot = { { "o", x + a / 2, y + a / 2, a * 0.07 } }, paint = paint, construct = construct }
      end
    end
    return out
  end,
}
