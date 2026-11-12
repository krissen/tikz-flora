-- Overlapping circles on a triangular grid, each circle's radius the
-- grid's spacing, so every circle passes through its six neighbours'
-- centres: the lattice a finite Flower of Life is cut from.

local K = require("flora.pat_kit")
local sqrt = math.sqrt

local function paint(pt, c, ink)
  pt:stroke(c.path, ink.band, ink.width, 1)
  pt:stroke(c.path, ink.accent, ink.width * 0.35, 1)
end

local function construct(pt, c, ink)
  pt:stroke(c.path, ink.line, 0.4, 1)
end

return {
  name = "overlapping_circles",
  title = "Overlapping circles, each through its six neighbours' centres (the Flower of Life lattice)",
  tags = { "circle_lattice", "circles", "triangular", "lattice" },
  roles = { "band", "accent" },
  scale = 16,
  width = 1.1,
  cells = function(env)
    local r = env.size
    local h = r * sqrt(3) / 2
    local out = {}
    for j = math.floor(env.y0 / h) - 1, math.ceil(env.y1 / h) + 1 do
      for i = math.floor(env.x0 / r) - 1, math.ceil(env.x1 / r) + 1 do
        local x, y = r * (i + (j % 2) / 2), h * j
        out[#out + 1] = { x = x, y = y, verts = K.ring(x, y, r), circle = { x, y, r }, path = { { "o", x, y, r } },
          sweep = { x, y, math.pi / 2 }, paint = paint, construct = construct }
      end
    end
    return out
  end,
}
