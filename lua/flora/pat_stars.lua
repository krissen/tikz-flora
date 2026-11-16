-- Eight- and four-pointed stars: Hankin's polygons-in-contact method on
-- the 4.8.8 tiling (octagons and squares). From the midpoint of every
-- tile edge two rays leave at the contact angle and run until they meet
-- their neighbours' rays; each tile keeps the star its rays outline, and
-- the tiling itself is never drawn. Kaplan, "Islamic star patterns from
-- polygons in contact", Graphics Interface 2005.

local sin, cos, pi, sqrt = math.sin, math.cos, math.pi, math.sqrt
local CONTACT = 67.5 * pi / 180

-- The regular n-gon of side s centred at (cx, cy), first vertex at a0
-- degrees, counter-clockwise.
local function regular(cx, cy, n, s, a0)
  local R = s / (2 * sin(pi / n))
  local P = {}
  for k = 0, n - 1 do
    local a = (a0 + 360 * k / n) * pi / 180
    P[#P + 1] = { cx + R * cos(a), cy + R * sin(a) }
  end
  return P
end

-- The star of polygon P (counter-clockwise) at contact angle th: the
-- midpoint of each edge, then the point where its ray meets the next
-- edge's, in turn.
local function star(P, th)
  local n, mids, dirs = #P, {}, {}
  for i = 1, n do
    local a, b = P[i], P[i % n + 1]
    local ex, ey = b[1] - a[1], b[2] - a[2]
    local l = sqrt(ex * ex + ey * ey)
    mids[i] = { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 }
    dirs[i] = { ex / l, ey / l }
  end
  local ct, st = cos(th), sin(th)
  local out = {}
  for i = 1, n do
    local j = i % n + 1
    local m1, e1, m2, e2 = mids[i], dirs[i], mids[j], dirs[j]
    local ax, ay = e1[1] * ct - e1[2] * st, e1[1] * st + e1[2] * ct
    local bx, by = -e2[1] * ct - e2[2] * st, e2[1] * st - e2[2] * ct
    local den = ax * (-by) + ay * bx
    local dx, dy = m2[1] - m1[1], m2[2] - m1[2]
    local t = math.abs(den) > 1e-9 and (dx * (-by) + dy * bx) / den or 0
    out[#out + 1] = m1
    out[#out + 1] = { m1[1] + t * ax, m1[2] + t * ay }
  end
  return out
end

local function path(pts)
  local c = { { "m", pts[1][1], pts[1][2] } }
  for i = 2, #pts do c[#c + 1] = { "l", pts[i][1], pts[i][2] } end
  c[#c + 1] = { "z" }
  return c
end

local K = require("flora.pat_kit")

local function paint(pt, c, ink)
  K.fill(pt, c.path, c.kind == 8 and ink.fill[1] or ink.fill[2], ink)
  K.band(pt, c.path, ink)
end

local function construct(pt, c, ink)
  pt:stroke(c.path, ink.line, 0.4, 1)
end

return {
  name = "stars_8_4",
  title = "Eight- and four-pointed stars, by Hankin's method on the 4.8.8 tiling",
  tags = { "girih", "hankin", "star", "lattice" },
  roles = { "band", "core", "a", "b" },
  surface = true,
  scale = 9,
  -- Broad light straps with a fine contour between the stars, as in the
  -- mock (t-03).
  width = 2.6, core = 0.7, bands = "strap", lines_bands = "line",
  cells = function(env)
    local s = env.size
    local a = s * (1 + sqrt(2))
    local out = {}
    for i = math.floor(env.x0 / a) - 1, math.ceil(env.x1 / a) + 1 do
      for j = math.floor(env.y0 / a) - 1, math.ceil(env.y1 / a) + 1 do
        -- Octagons turned to face the axes; each square, a diamond, fills
        -- the hole between four of them, edge to edge.
        for _, t in ipairs({ { i * a, j * a, 8, 22.5 }, { (i + .5) * a, (j + .5) * a, 4, 0 } }) do
          local P = regular(t[1], t[2], t[3], s, t[4])
          local S = star(P, CONTACT)
          out[#out + 1] = { x = t[1], y = t[2], kind = t[3], verts = S, tile = P, path = path(S),
            paint = paint, construct = construct }
        end
      end
    end
    return out
  end,
}
