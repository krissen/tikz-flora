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

-- Bands and fills, as the page's finish and band character ask (pattern.lua
-- sets them on `ink`): ink.width is the band's full width, ink.bands
-- "strap" (a contour of the band role round a light core) or "line" (one
-- line ink.linew wide), ink.corefrac the core's share of the width, and
-- ink.lines true for the lines finish, which fills nothing.
--
-- A strap's contour is never narrower than CONTOUR_MIN either side, and a
-- core narrower than CORE_MIN is not drawn: the band is then one solid
-- line. A renderer that draws every stroke at least a device pixel wide
-- (the web's) would otherwise lay the core over the whole band. 0.55 pt
-- is a device pixel at 1.8 pixels per pt, a high-density screen showing
-- an A4 page about 1080 pixels wide (tools/band_probe.lua).
K.CONTOUR_MIN = 0.55
K.CORE_MIN = 0.6

-- Paint path (or with opt.many, paths) as a band, opt.w times the band's
-- width. opt.core names the role down its middle ("core", the default, or
-- "accent"); opt.core = false paints a solid band, opt.w times ink.width.
function K.band(pt, path, ink, opt)
  opt = opt or {}
  local o = opt.many and { many = true } or nil
  local k = opt.w or 1
  if ink.bands == "line" then
    pt:stroke(path, ink.band, (ink.linew or 0.6) * math.sqrt(k), 1, o)
    return
  end
  local W = ink.width * k
  if opt.core == false then
    pt:stroke(path, ink.band, W, 1, o)
    return
  end
  local core = W * (ink.corefrac or 0.45)
  local c = (W - core) / 2
  if c < K.CONTOUR_MIN then core = W - 2 * K.CONTOUR_MIN end
  pt:stroke(path, ink.band, W, 1, o)
  if core >= K.CORE_MIN then pt:stroke(path, ink[opt.core or "core"], core, 1, o) end
end

-- Fill path with rgb (opt as pt:fill's, with many and evenodd), or under
-- the lines finish nothing at all, or with opt.outline its outline as a
-- line.
function K.fill(pt, path, rgb, ink, opt)
  if ink.lines then
    if opt and opt.outline then pt:stroke(path, ink.band, ink.linew or 0.6, 1, opt.many and { many = true } or nil) end
    return
  end
  pt:fill(path, rgb, 1, opt)
end

-- A circle about (x, y) turning clockwise, for clips that leave it out.
function K.circle_cw(x, y, r)
  local c = { { "m", x + r, y } }
  for _, s in ipairs(K.arc(x, y, r, 0, -2 * pi)) do c[#c + 1] = s end
  c[#c + 1] = { "z" }
  return c
end

return K
