-- Kikkō, the tortoiseshell pattern: a honeycomb of hexagons, each with a
-- smaller hexagon set inside it, as on Japanese textiles and lacquer.

local K = require("flora.pat_kit")
local sqrt = math.sqrt

local function paint(pt, c, ink)
  pt:fill(c.path, ink.fill[c.tone], 1)
  pt:stroke(c.path, ink.band, ink.width, 1)
  pt:stroke(c.path, ink.core, ink.width * 0.45, 1)
  pt:fill(c.inner, ink.fill[3 - c.tone], 1)
  pt:stroke(c.inner, ink.band, ink.width * 0.5, 1)
end

local function construct(pt, c, ink)
  pt:stroke(c.path, ink.line, 0.4, 1)
end

return {
  name = "kikko",
  title = "Kikkō (tortoiseshell), a honeycomb of hexagons with a hexagon inside each",
  tags = { "japanese", "hexagonal", "lattice" },
  scale = 12,
  width = 1.4,
  cells = function(env)
    local s = env.size
    local dx, dy = 1.5 * s, sqrt(3) * s
    local out = {}
    for i = math.floor(env.x0 / dx) - 1, math.ceil(env.x1 / dx) + 1 do
      for j = math.floor(env.y0 / dy) - 1, math.ceil(env.y1 / dy) + 1 do
        local x, y = i * dx, j * dy + (i % 2) * dy / 2
        local P = K.regular(x, y, 6, s, 0)
        out[#out + 1] = { x = x, y = y, verts = P, tile = P, path = K.path(P), inner = K.path(K.scaled(P, x, y, 0.58)),
          tone = (i + j) % 3 == 0 and 2 or 1, paint = paint, construct = construct }
      end
    end
    return out
  end,
}
