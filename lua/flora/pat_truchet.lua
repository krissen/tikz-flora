-- Truchet tiles in Smith's quarter-circle form: square tiles, each with
-- two quarter circles joining the midpoints of neighbouring sides, turned
-- one of two ways at random, so the arcs join into winding bands.

local K = require("flora.pat_kit")
local pi = math.pi

local function paint(pt, c, ink)
  pt:stroke(c.arcs, ink.band, ink.width, 1, { many = true })
  pt:stroke(c.arcs, ink.accent, ink.width * 0.5, 1, { many = true })
end

local function construct(pt, c, ink)
  pt:stroke(c.arcs, ink.line, 0.4, 1, { many = true })
end

local function quarter(cx, cy, r, a0)
  local c = { { "m", cx + r * math.cos(a0), cy + r * math.sin(a0) } }
  for _, s in ipairs(K.arc(cx, cy, r, a0, a0 + pi / 2)) do c[#c + 1] = s end
  return c
end

return {
  name = "truchet",
  title = "Truchet tiles of quarter circles, turned at random into winding bands",
  tags = { "truchet", "tiles", "square" },
  roles = { "band", "accent" },
  scale = 18,
  width = 3,
  cells = function(env)
    local s, r = env.size, env.size / 2
    local out = {}
    for i = math.floor(env.x0 / s) - 1, math.ceil(env.x1 / s) do
      for j = math.floor(env.y0 / s) - 1, math.ceil(env.y1 / s) do
        local x, y = i * s, j * s
        local arcs
        if env.rng:next() < 0.5 then
          arcs = { quarter(x, y, r, 0), quarter(x + s, y + s, r, pi) }
        else
          arcs = { quarter(x + s, y, r, pi / 2), quarter(x, y + s, r, 3 * pi / 2) }
        end
        out[#out + 1] = { x = x + s / 2, y = y + s / 2, arcs = arcs,
          verts = { { x, y }, { x + s, y }, { x + s, y + s }, { x, y + s } }, paint = paint, construct = construct }
      end
    end
    return out
  end,
}
