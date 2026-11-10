-- Seigaiha, "blue sea waves": rows of fans of concentric rings, each row
-- set half a fan along and laid over the row above, so only the fans'
-- upper halves show. Cells are given top row first, so later rows cover
-- earlier ones as the field paints them in order. A fan's compass starts
-- at its left and turns clockwise, over the crest that shows first.

local K = require("flora.pat_kit")

local RINGS = { 1, 0.78, 0.56, 0.34 }

local function paint(pt, c, ink)
  for k, f in ipairs(RINGS) do
    local disc = { { "o", c.x, c.y, c.r * f } }
    pt:fill(disc, k % 2 == 1 and ink.fill[2] or ink.core, 1)
    pt:stroke(disc, ink.band, ink.width * (k == 1 and 1 or 0.55), 1)
  end
end

local function construct(pt, c, ink)
  pt:stroke({ { "o", c.x, c.y, c.r } }, ink.line, 0.4, 1)
end

return {
  name = "seigaiha",
  title = "Seigaiha (blue sea waves), overlapping fans of concentric rings",
  tags = { "japanese", "circles", "wave" },
  scale = 20,
  width = 1.2,
  cells = function(env)
    local r = env.size
    local dx, dy = 2 * r, r / 2
    local out = {}
    for j = math.ceil(env.y1 / dy) + 2, math.floor(env.y0 / dy) - 2, -1 do
      for i = math.floor(env.x0 / dx) - 1, math.ceil(env.x1 / dx) + 1 do
        local x, y = i * dx + (j % 2) * r, j * dy
        out[#out + 1] = { x = x, y = y, r = r, verts = K.ring(x, y, r), circle = { x, y, r },
          sweep = { x, y, math.pi, -1 }, paint = paint, construct = construct }
      end
    end
    return out
  end,
}
