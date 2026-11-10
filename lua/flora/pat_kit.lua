-- Small geometry shared by the pattern modules (patterns.lua).

local sin, cos, pi = math.sin, math.cos, math.pi
local K = {}

-- The regular n-gon of side s centred at (cx, cy), its first vertex at
-- a0 degrees, counter-clockwise.
function K.regular(cx, cy, n, s, a0)
  local R = s / (2 * sin(pi / n))
  local P = {}
  for k = 0, n - 1 do
    local a = (a0 + 360 * k / n) * pi / 180
    P[#P + 1] = { cx + R * cos(a), cy + R * sin(a) }
  end
  return P
end

-- The same polygon about its centre, scaled by k.
function K.scaled(P, cx, cy, k)
  local out = {}
  for i, q in ipairs(P) do out[i] = { cx + (q[1] - cx) * k, cy + (q[2] - cy) * k } end
  return out
end

-- A closed path through `pts`.
function K.path(pts)
  local c = { { "m", pts[1][1], pts[1][2] } }
  for i = 2, #pts do c[#c + 1] = { "l", pts[i][1], pts[i][2] } end
  c[#c + 1] = { "z" }
  return c
end

-- A segment from a to b.
function K.seg(a, b) return { { "m", a[1], a[2] }, { "l", b[1], b[2] } } end

-- The circle's outline as n points, for the field's distance and edge tests.
function K.ring(x, y, r, n)
  local out = {}
  n = n or 8
  for k = 0, n - 1 do
    local a = 2 * pi * k / n
    out[#out + 1] = { x + r * cos(a), y + r * sin(a) }
  end
  return out
end

-- An arc of radius r about (x, y) from angle a0 to a1 (radians), as Bezier
-- segments of at most a quarter turn, without the move to its start.
function K.arc(x, y, r, a0, a1)
  local out = {}
  local n = math.max(1, math.ceil(math.abs(a1 - a0) / (pi / 2) - 1e-9))
  local d = (a1 - a0) / n
  local k = 4 / 3 * math.tan(d / 4) * r
  for i = 0, n - 1 do
    local s, e = a0 + d * i, a0 + d * (i + 1)
    out[#out + 1] = { "c",
      x + r * cos(s) - k * sin(s), y + r * sin(s) + k * cos(s),
      x + r * cos(e) + k * sin(e), y + r * sin(e) - k * cos(e),
      x + r * cos(e), y + r * sin(e) }
  end
  return out
end

-- A closed smooth curve through `pts` (Catmull-Rom, as cubic Beziers).
function K.smooth(pts, tension)
  local n, t = #pts, (tension or 1) / 6
  local c = { { "m", pts[1][1], pts[1][2] } }
  for i = 1, n do
    local p0, p1 = pts[(i - 2) % n + 1], pts[i]
    local p2, p3 = pts[i % n + 1], pts[(i + 1) % n + 1]
    c[#c + 1] = { "c",
      p1[1] + (p2[1] - p0[1]) * t, p1[2] + (p2[2] - p0[2]) * t,
      p2[1] - (p3[1] - p1[1]) * t, p2[2] - (p3[2] - p1[2]) * t,
      p2[1], p2[2] }
  end
  c[#c + 1] = { "z" }
  return c
end

return K
