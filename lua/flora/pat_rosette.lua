-- Rosettes on a quincunx: small eight-petalled rosettes at the points of
-- a square grid, larger twelve-petalled ones at the centres of its
-- squares, and a strap grid joining the small ones. Each grid point's
-- cell carries its rosette and the four half-straps that leave it, so
-- two neighbouring cells meet at the middle of the strap between them;
-- the large rosettes stand free in the squares the straps enclose.

local K = require("flora.pat_kit")
local sin, cos, pi = math.sin, math.cos, math.pi

-- A petal from radius r0 to r1 along angle a about (cx, cy), w wide at
-- its middle: two cubic arcs that bulge to either side and meet at the tip.
local function petal(cx, cy, r0, r1, a, w)
  local rm = (r0 + r1) / 2
  local dl = w / rm
  local function at(r, b) return cx + r * cos(b), cy + r * sin(b) end
  local x0, y0 = at(r0, a)
  local x1, y1 = at(r1, a)
  local p1x, p1y = at(rm, a + dl)
  local q1x, q1y = at(rm * 1.08, a + dl)
  local p2x, p2y = at(rm, a - dl)
  local q2x, q2y = at(rm * 1.08, a - dl)
  return { { "m", x0, y0 }, { "c", p1x, p1y, q1x, q1y, x1, y1 }, { "c", q2x, q2y, p2x, p2y, x0, y0 }, { "z" } }
end

-- A rosette of n petals in radius R about (cx, cy), with n smaller
-- petals between them; every point of it lies within R.
local function rosette(cx, cy, R, n)
  local outer, inner = {}, {}
  for k = 0, n - 1 do
    local a = 2 * pi * k / n
    outer[#outer + 1] = petal(cx, cy, R * 0.18, R * 0.9, a, R * 0.17)
    inner[#inner + 1] = petal(cx, cy, R * 0.12, R * 0.58, a + pi / n, R * 0.1)
  end
  return { outer = outer, inner = inner }
end

local function paint_rosette(pt, c, ink, f1, f2)
  local r = c.rosette
  K.fill(pt, { { "o", c.x, c.y, c.R } }, ink.core, ink)
  K.fill(pt, r.outer, f1, ink, { many = true })
  K.band(pt, r.outer, ink, { many = true, core = false, w = 0.3 })
  K.fill(pt, r.inner, f2, ink, { many = true, outline = true })
  K.band(pt, { { "o", c.x, c.y, c.R } }, ink, { core = false, w = 0.45 })
  K.fill(pt, { { "o", c.x, c.y, c.R * 0.12 } }, ink.accent, ink, { outline = true })
end

local function paint(pt, c, ink)
  if c.straps then
    K.band(pt, c.straps, ink, { many = true })
    paint_rosette(pt, c, ink, ink.fill[1], ink.accent)
  else
    paint_rosette(pt, c, ink, ink.fill[2], ink.fill[1])
  end
end

local function construct(pt, c, ink)
  if c.straps then pt:stroke(c.straps, ink.line, 0.4, 1, { many = true }) end
  pt:stroke({ { "o", c.x, c.y, c.R } }, ink.line, 0.4, 1)
end

-- The outline of a grid point's cell: the polygon round its rosette's
-- circle (a 16-gon whose edges touch it), drawn out at the four axes to
-- the tips of its half-straps.
local function cross(x, y, R, h)
  local N = 16
  local Rc = R / cos(pi / N)
  local out = {}
  for k = 0, N - 1 do
    local a = 2 * pi * (k + 0.5) / N
    out[#out + 1] = { x + Rc * cos(a), y + Rc * sin(a) }
    if k % 4 == 3 then
      -- After the vertex just before an axis, its strap's tip.
      local b = 2 * pi * (k + 1) / N
      out[#out + 1] = { x + h * cos(b), y + h * sin(b) }
    end
  end
  return out
end

return {
  name = "rosette_lattice",
  title = "Rosettes on a quincunx, small at the grid points and large in the squares, joined by a strap grid",
  tags = { "rosette", "quincunx", "lattice", "square" },
  roles = { "band", "core", "a", "b", "accent", "ground" },
  surface = true,
  -- A light ground, as in the mock (f-14).
  ground = 0.80,
  scale = 30,
  width = 1.6, core = 0.4, bands = "strap",
  cells = function(env)
    local a = env.size
    local out = {}
    for i = math.floor(env.x0 / a) - 1, math.ceil(env.x1 / a) + 1 do
      for j = math.floor(env.y0 / a) - 1, math.ceil(env.y1 / a) + 1 do
        local x, y = i * a, j * a
        local R = a * 0.3
        local h = a / 2
        out[#out + 1] = { x = x, y = y, R = R, rosette = rosette(x, y, R, 8), verts = cross(x, y, R, h),
          straps = { K.seg({ x, y }, { x + h, y }), K.seg({ x, y }, { x, y + h }),
            K.seg({ x, y }, { x - h, y }), K.seg({ x, y }, { x, y - h }) },
          paint = paint, construct = construct,
          -- The grid point's square, for a ground under the field.
          under = K.path({ { x - h, y - h }, { x + h, y - h }, { x + h, y + h }, { x - h, y + h } }) }
        local cx, cy, Rb = x + a / 2, y + a / 2, a * 0.4
        out[#out + 1] = { x = cx, y = cy, R = Rb, rosette = rosette(cx, cy, Rb, 12), circle = { cx, cy, Rb }, rests = true,
          verts = K.ring(cx, cy, Rb), paint = paint, construct = construct }
      end
    end
    return out
  end,
}
