-- Asanoha, the hemp-leaf pattern of Japanese kumiko lattice and textiles:
-- a triangular grid in which every triangle is split into three by lines
-- from its corners to its centre, so that six triangles round each grid
-- point make a six-pointed leaf.

local sqrt = math.sqrt

local function paint(pt, c, ink)
  pt:stroke(c.edges, ink.band, ink.width, 1, { many = true })
  pt:stroke(c.spokes, ink.band, ink.width * 0.55, 1, { many = true })
  pt:stroke(c.edges, ink.accent, ink.width * 0.4, 1, { many = true })
  pt:stroke(c.spokes, ink.accent, ink.width * 0.22, 1, { many = true })
end

local function construct(pt, c, ink)
  pt:stroke(c.edges, ink.line, 0.4, 1, { many = true })
end

local function seg(a, b) return { { "m", a[1], a[2] }, { "l", b[1], b[2] } } end

return {
  name = "asanoha",
  title = "Asanoha (hemp leaf), triangles split at their centres",
  tags = { "japanese", "kumiko", "lattice", "triangular" },
  roles = { "band", "accent", "ground" },
  scale = 26,
  width = 1.4,
  cells = function(env)
    local s = env.size
    local h = s * sqrt(3) / 2
    local out = {}
    for j = math.floor(env.y0 / h) - 1, math.ceil(env.y1 / h) + 1 do
      for i = math.floor(env.x0 / s) - 2, math.ceil(env.x1 / s) + 2 do
        local x0 = s * (i + (j % 2) / 2)
        local y0 = h * j
        local A, B, C = { x0, y0 }, { x0 + s, y0 }, { x0 + s / 2, y0 + h }
        local D = { x0 + s * 1.5, y0 + h }
        for _, T in ipairs({ { A, B, C }, { B, D, C } }) do
          local g = { (T[1][1] + T[2][1] + T[3][1]) / 3, (T[1][2] + T[2][2] + T[3][2]) / 3 }
          out[#out + 1] = { x = g[1], y = g[2], verts = T, tile = T,
            edges = { seg(T[1], T[2]), seg(T[2], T[3]), seg(T[3], T[1]) },
            spokes = { seg(T[1], g), seg(T[2], g), seg(T[3], g) },
            paint = paint, construct = construct }
        end
      end
    end
    return out
  end,
}
