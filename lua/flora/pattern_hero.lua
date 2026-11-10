-- A pattern page's hero (pattern.lua): one large radial motif centred on
-- a top corner of the page, which the field of cells gives way to, as
-- flora gives way to its hero bloom (compose.lua). And the guilloche band
-- that edge=guilloche draws round the text in place of the ruled frame.
--
-- A motif is a list of rings, from the centre outward: { r = its outer
-- radius, paint = fn(pt), construct = fn(pt) }. Every point a motif
-- paints, strokes included, lies within the radius it was made for, so
-- the disc it is placed in is all the field and the text need to keep
-- clear of. Rings grow in turn from the centre, each its construction
-- lines first and then its colour.

local K = require("flora.pat_kit")
local Paint = require("flora.paint")
local sin, cos, pi, sqrt = math.sin, math.cos, math.pi, math.sqrt

local M = {}

-- The hero's radius at most, as a part of the page's smaller side, and
-- at least, in pt: a corner with less room than that gets none.
local MAX_FRAC, MIN_R = 0.5, 24

local function circle(x, y, r) return { { "o", x, y, r } } end

-- A petal from radius r0 to r1 along angle a about (cx, cy), dl radians
-- wide either side at its middle; it stays inside radius r1.
local function petal(cx, cy, r0, r1, a, dl)
  local rm = (r0 + r1) / 2
  local function at(r, b) return cx + r * cos(b), cy + r * sin(b) end
  local x0, y0 = at(r0, a)
  local x1, y1 = at(r1, a)
  local p1x, p1y = at(rm, a + dl)
  local q1x, q1y = at(rm * 1.08, a + dl)
  local p2x, p2y = at(rm, a - dl)
  local q2x, q2y = at(rm * 1.08, a - dl)
  return { { "m", x0, y0 }, { "c", p1x, p1y, q1x, q1y, x1, y1 }, { "c", q2x, q2y, p2x, p2y, x0, y0 }, { "z" } }
end

-- Rings of petals, each ring twice the petals of the one inside it from
-- the second on, a ring of dots, and a gold centre.
local function rosette(x, y, R, ink)
  local u = R / 80
  local specs = {
    { 0.07, 0.30, 8, 0, ink.fill[1] },
    { 0.26, 0.52, 16, 0.5, ink.fill[2] },
    { 0.47, 0.74, 16, 0, ink.accent },
    { 0.70, 0.90, 32, 0.5, ink.fill[1] },
  }
  local rings = {}
  for i, s in ipairs(specs) do
    local r0, r1, n, off, fill = s[1] * R, s[2] * R, s[3], s[4], s[5]
    local petals, spokes = {}, {}
    for k = 0, n - 1 do
      local a = 2 * pi * (k + off) / n
      petals[#petals + 1] = petal(x, y, r0, r1, a, 0.8 * pi / n)
      spokes[#spokes + 1] = K.seg({ x + r0 * cos(a), y + r0 * sin(a) }, { x + r1 * cos(a), y + r1 * sin(a) })
    end
    local rim = r1 + 0.02 * R
    rings[#rings + 1] = { r = rim + u,
      construct = function(pt)
        pt:stroke(spokes, ink.line, 0.4, 1, { many = true })
        pt:stroke(circle(x, y, rim), ink.line, 0.4, 1)
      end,
      paint = function(pt)
        pt:fill(petals, fill, 1, { many = true })
        pt:stroke(petals, ink.band, 0.5 * u, 1, { many = true })
        pt:stroke(circle(x, y, rim), ink.band, 0.7 * u, 1)
        if i == 1 then
          pt:fill(circle(x, y, 0.07 * R), ink.accent, 1)
          pt:stroke(circle(x, y, 0.07 * R), ink.band, 0.6 * u, 1)
        end
      end }
  end
  local dots = {}
  for k = 0, 47 do
    local a = 2 * pi * k / 48
    dots[#dots + 1] = circle(x + 0.96 * R * cos(a), y + 0.96 * R * sin(a), 0.012 * R)
  end
  rings[#rings + 1] = { r = 0.972 * R,
    construct = function(pt) pt:stroke(circle(x, y, 0.96 * R), ink.line, 0.4, 1) end,
    paint = function(pt) pt:fill(dots, ink.accent, 1, { many = true }) end }
  return rings
end

-- Seeds set as a sunflower sets them: the k-th at radius c sqrt(k) and
-- k golden angles round, larger outward, in bands of colour from the gold
-- centre to the blooms' ink.
local function phyllotaxis(x, y, R, ink)
  local N, BANDS = 420, 6
  -- The outermost seed, its outline and its construction line within R.
  local c = (R - 0.5) / (sqrt(N) + 0.6)
  local ga = pi * (3 - sqrt(5))
  local bands = {}
  for b = 1, BANDS do bands[b] = {} end
  for k = 1, N do
    local t = k / N
    local b = math.min(BANDS, math.floor(sqrt(t) * BANDS) + 1)
    local r, a = c * sqrt(k), k * ga
    table.insert(bands[b], circle(x + r * cos(a), y + r * sin(a), c * (0.25 + 0.3 * t)))
  end
  local rings = {}
  for b = 1, BANDS do
    local t = (b - 1) / (BANDS - 1)
    local fill = Paint.mix(ink.accent, ink.fill[1], t)
    local rim = c * sqrt(N * (b / BANDS) ^ 2)
    rings[b] = { r = math.min(R, rim + 0.6 * c + 0.3),
      construct = function(pt) pt:stroke(bands[b], ink.line, 0.4, 1, { many = true }) end,
      paint = function(pt)
        pt:fill(bands[b], fill, 1, { many = true })
        pt:stroke(bands[b], ink.band, 0.06 * c, 1, { many = true })
      end }
  end
  return rings
end

-- A rose window: a ring of glass roundels, each with four foils of
-- tracery, round a smaller rose of six, on a dark ground with spokes
-- between the roundels, inside a heavy rim.
local function rose(x, y, R, ink)
  local u = R / 80
  local Rr = R - 2 * u
  local n, m = 12, 6
  local s = sin(pi / n)
  local r = Rr * s / (1 + s)
  local ri = (Rr - 2 * r) * 0.62
  local sm = sin(pi / m)
  local rr = ri * sm / (1 + sm)
  local light = ink.core
  local rings = {}
  -- The inner rose.
  local foils = {}
  for k = 0, m - 1 do
    local a = pi / 2 + 2 * pi * k / m
    foils[#foils + 1] = { x + (ri - rr) * cos(a), y + (ri - rr) * sin(a) }
  end
  rings[1] = { r = ri + math.max(0.6 * u, 0.2),
    construct = function(pt)
      pt:stroke(circle(x, y, ri), ink.line, 0.4, 1)
      for _, f in ipairs(foils) do pt:stroke(circle(f[1], f[2], rr), ink.line, 0.4, 1) end
    end,
    paint = function(pt)
      pt:fill(circle(x, y, ri), ink.band, 1)
      local glass = {}
      for _, f in ipairs(foils) do glass[#glass + 1] = circle(f[1], f[2], rr * 0.9) end
      pt:fill(glass, ink.fill[2], 1, { many = true })
      pt:stroke(glass, light, 0.8 * u, 1, { many = true })
      pt:fill(circle(x, y, 0.28 * ri), ink.accent, 1)
      pt:stroke(circle(x, y, 0.28 * ri), light, 0.8 * u, 1)
      pt:stroke(circle(x, y, ri), light, 1.2 * u, 1)
    end }
  -- The dark ground between the roses, and its spokes.
  local spokes, centres = {}, {}
  for k = 0, n - 1 do
    local a = pi / 2 + 2 * pi * k / n
    centres[#centres + 1] = { x + (Rr - r) * cos(a), y + (Rr - r) * sin(a), a }
    local b = a + pi / n
    spokes[#spokes + 1] = K.seg({ x + ri * cos(b), y + ri * sin(b) }, { x + (Rr - r) * cos(b), y + (Rr - r) * sin(b) })
  end
  local ground = { { "o", x, y, Rr }, { "o", x, y, ri } }
  rings[2] = { r = Rr,
    construct = function(pt) pt:stroke(spokes, ink.line, 0.4, 1, { many = true }) end,
    paint = function(pt)
      pt:fill(ground, ink.band, 1, { evenodd = true })
      pt:stroke(spokes, light, 0.9 * u, 1, { many = true })
    end }
  -- The roundels with their foils.
  rings[3] = { r = Rr,
    construct = function(pt)
      for _, q in ipairs(centres) do pt:stroke(circle(q[1], q[2], r * 0.92), ink.line, 0.4, 1) end
    end,
    paint = function(pt)
      for i, q in ipairs(centres) do
        local cx, cy, a = q[1], q[2], q[3]
        pt:fill(circle(cx, cy, r * 0.92), i % 2 == 1 and ink.fill[1] or ink.fill[2], 1)
        local r2, tracery = r * 0.42, {}
        for j = 0, 3 do
          local b = a + pi / 4 + j * pi / 2
          tracery[#tracery + 1] = circle(cx + r2 * 0.95 * cos(b), cy + r2 * 0.95 * sin(b), r2)
        end
        pt:stroke(tracery, light, 0.7 * u, 1, { many = true })
        pt:stroke(circle(cx, cy, r * 0.92), light, 1.1 * u, 1)
      end
    end }
  -- The rim.
  rings[4] = { r = R,
    construct = function(pt) pt:stroke(circle(x, y, R - u), ink.line, 0.4, 1) end,
    paint = function(pt)
      pt:stroke(circle(x, y, R - u), ink.band, 2 * u, 1)
      pt:stroke(circle(x, y, R - u), ink.accent, 0.6 * u, 1)
    end }
  return rings
end

-- A hypotrochoid about (x, y): the point at radius d on a circle rolling
-- round inside another, `lobes` + 1 lobes between radius rho - d and
-- rho + d, turned by `phase`. As a closed smooth curve.
local function trochoid(x, y, rho, d, lobes, phase)
  local pts, n = {}, (lobes + 1) * 6
  for i = 0, n - 1 do
    local t = 2 * pi * i / n
    pts[#pts + 1] = { x + rho * cos(t) + d * cos(lobes * t + phase), y + rho * sin(t) - d * sin(lobes * t + phase) }
  end
  return K.smooth(pts)
end

-- Guilloche rings: three families of hypotrochoids, each of ten fine
-- curves turned a little apart, as an engraver's rose engine cuts them,
-- in alternate inks inside a ruled rim.
local function guilloche(x, y, R, ink)
  local u = R / 80
  local rings = {}
  local fams = { { 0.27, 0.15, 0.16 }, { 0.6, 0.13, 0.11 }, { 0.84, 0.07, 0.07 } }
  for i, f in ipairs(fams) do
    local rho, d = f[1] * R, f[2] * R
    local lobes = math.max(5, math.floor(2 * pi * rho / (f[3] * R) + 0.5))
    local curves = {}
    for j = 0, 9 do curves[#curves + 1] = trochoid(x, y, rho, d, lobes, pi * j / 10) end
    rings[i] = { r = rho + d + u,
      construct = function(pt)
        pt:stroke(circle(x, y, rho - d), ink.line, 0.4, 1)
        pt:stroke(circle(x, y, rho + d), ink.line, 0.4, 1)
      end,
      paint = function(pt)
        for j, cv in ipairs(curves) do
          pt:stroke(cv, j % 2 == 1 and ink.band or ink.fill[1], 0.22 * u, 1)
        end
        if i == 1 then
          pt:fill(circle(x, y, 0.06 * R), ink.accent, 1)
          pt:stroke(circle(x, y, 0.06 * R), ink.band, 0.5 * u, 1)
        end
      end }
  end
  rings[#rings + 1] = { r = R,
    construct = function(pt) pt:stroke(circle(x, y, 0.96 * R), ink.line, 0.4, 1) end,
    paint = function(pt)
      pt:stroke(circle(x, y, 0.96 * R), ink.band, 0.9 * u, 1)
      pt:stroke(circle(x, y, 0.96 * R - 2 * u), ink.accent, 0.5 * u, 1)
    end }
  return rings
end

M.motifs = { rosette = rosette, phyllotaxis = phyllotaxis, rose = rose, guilloche = guilloche }

-- The names hero= accepts, sorted, then none.
function M.names()
  local out = {}
  for k in pairs(M.motifs) do out[#out + 1] = k end
  table.sort(out)
  out[#out + 1] = "none"
  return out
end

-- Where the hero goes, as a disc {x, y, r, name}, or nil. It sits on the
-- top corner of the field's side (`side`, as pattern.lua's sides gives
-- it: the top right for right, the top left for left), or the top right
-- where the field takes both sides or the whole page; `top` is the page's
-- painted top. With `margin` (outer=margin) it lies wholly on the page,
-- `margin` in from its edges; else it is centred on the corner and runs
-- off it. Its radius is half the page's smaller side, or less where it
-- would come nearer than `gap` to any of the rectangles `keep`.
function M.place(name, spec, side, top, keep, gap, margin)
  if not M.motifs[name] then return nil end
  local left = side and side.left and not side.right
  local function centre(R)
    if not margin then return left and 0 or spec.width, top end
    return left and margin + R or spec.width - margin - R, top - margin - R
  end
  local function fits(R)
    local x, y = centre(R)
    for _, r in ipairs(keep) do
      local dx = math.max(r[1] - x, 0, x - r[3])
      local dy = math.max(r[2] - y, 0, y - r[4])
      if sqrt(dx * dx + dy * dy) - R < gap then return false end
    end
    return true
  end
  local R = MAX_FRAC * math.min(spec.width, spec.height)
  if margin then R = math.min(R, (math.min(spec.width, top) - 2 * margin) / 2) end
  if not margin then
    -- On the corner the centre stays put: the radius is the nearest
    -- rectangle's distance less the gap.
    local x, y = centre(R)
    for _, r in ipairs(keep) do
      local dx = math.max(r[1] - x, 0, x - r[3])
      local dy = math.max(r[2] - y, 0, y - r[4])
      R = math.min(R, sqrt(dx * dx + dy * dy) - gap)
    end
  elseif not fits(R) then
    -- Inside the margin the centre moves in as the disc grows, and its
    -- clearance falls, so the largest radius that fits is found by halving.
    local lo, hi = 0, R
    for _ = 1, 40 do
      local mid = (lo + hi) / 2
      if fits(mid) then lo = mid else hi = mid end
    end
    R = lo
  end
  if R < MIN_R then return nil end
  local x, y = centre(R)
  return { x, y, R, name = name }
end

-- The hero's rings for disc `d`, painted in `ink` (pattern.lua's inks).
function M.rings(d, ink)
  return M.motifs[d.name](d[1], d[2], d[3], ink)
end

-- When ring i of n is born, as the field's cells are (pattern.lua): from
-- the centre outward, early, as the hero is at the page's outer edge.
function M.birth(i, n)
  return 0.02 + 0.5 * (i - 1) / n
end

-- The guilloche band round text block t: two strands winding about the
-- line `o` out from the text, `a` to either side of it, crossing over and
-- under in turn, with a dot in each eye between them and a fine rule
-- inside and out. All of it lies between o - a - 1.5 - w/2 and
-- o + a + 1.5 + w/2 from the text, w the strands' width.
--
-- Each strand is one closed path, so no stroke ends, and no round cap
-- shows, anywhere along the band. The strand painted second lies on top
-- at every crossing; where the first should, its piece across that
-- crossing is painted again through a disc of radius `clip` round it, the
-- piece's ends lying outside the disc. Returns the strands (by side, 1
-- and -1), the crossings {x, y, over = side, piece, clip}, the dots and
-- the rules, as polylines.
function M.band(t, o, a, w)
  local x0, y0, x1, y1 = t.x0, t.y0, t.x1, t.y1
  local sw, sh, q = x1 - x0, y1 - y0, pi * o / 2
  -- The line o out from the text: four sides and four quarter turns,
  -- from the bottom left; at(s) is the point of the text the line's
  -- point s along is o out from, and the outward normal there.
  local legs = {
    { sw, function(u) return x0 + u, y0, 0, -1 end },
    { q, function(u) local b = -pi / 2 + u / o; return x1, y0, cos(b), sin(b) end },
    { sh, function(u) return x1, y0 + u, 1, 0 end },
    { q, function(u) local b = u / o; return x1, y1, cos(b), sin(b) end },
    { sw, function(u) return x1 - u, y1, 0, 1 end },
    { q, function(u) local b = pi / 2 + u / o; return x0, y1, cos(b), sin(b) end },
    { sh, function(u) return x0, y1 - u, -1, 0 end },
    { q, function(u) local b = pi + u / o; return x0, y0, cos(b), sin(b) end },
  }
  local L = 2 * (sw + sh) + 4 * q
  local function at(s)
    s = s % L
    for _, g in ipairs(legs) do
      if s <= g[1] then return g[2](s) end
      s = s - g[1]
    end
    return legs[#legs][2](legs[#legs][1])
  end
  local function point(s, off)
    local px, py, nx, ny = at(s)
    return { px + nx * (o + off), py + ny * (o + off) }
  end
  -- An even number of crossings, about three strand widths apart.
  local nz = 2 * math.max(2, math.floor(L / (6 * a) + 0.5))
  local Z = L / nz
  -- A strand's points from s0 to s1, n of them; a closed strand starts
  -- at an eye, where the two strands lie apart.
  local function strand(sign, s0, s1, n, closed)
    local pts = {}
    for i = 0, closed and n - 1 or n do
      local s = s0 + (s1 - s0) * i / n
      local p = point(s, sign * a * sin(pi * s / Z))
      pts[#pts + 1] = (i == 0) and { "m", p[1], p[2] } or { "l", p[1], p[2] }
    end
    if closed then pts[#pts + 1] = { "z" } end
    return pts
  end
  local strands = { [1] = strand(1, Z / 2, Z / 2 + L, nz * 12, true), [-1] = strand(-1, Z / 2, Z / 2 + L, nz * 12, true) }
  local crossings, dots = {}, {}
  for k = 0, nz - 1 do
    local c = point(k * Z, 0)
    local over = k % 2 == 0 and 1 or -1
    local piece = strand(over, (k - 0.5) * Z, (k + 0.5) * Z, 12)
    -- The clip disc: a + w round the crossing, less where a tight corner
    -- brings the piece's ends nearer, so they and their caps stay outside.
    local r = a + w
    for _, e in ipairs({ piece[1], piece[#piece] }) do
      r = math.min(r, sqrt((e[2] - c[1]) ^ 2 + (e[3] - c[2]) ^ 2) - w / 2 - 0.25)
    end
    crossings[#crossings + 1] = { x = c[1], y = c[2], over = over, piece = piece, clip = r }
    local e = point((k + 0.5) * Z, 0)
    dots[#dots + 1] = circle(e[1], e[2], 0.38 * a)
  end
  local function rule(off)
    local pts, n = {}, math.ceil(L)
    for i = 0, n - 1 do
      local p = point(L * i / n, off)
      pts[#pts + 1] = (i == 0) and { "m", p[1], p[2] } or { "l", p[1], p[2] }
    end
    pts[#pts + 1] = { "z" }
    return pts
  end
  return { strands = strands, crossings = crossings, dots = dots,
    rules = { rule(-(a + 1.5)), rule(a + 1.5) }, w = w }
end

-- Paint the guilloche band round text block t, in `ink`.
function M.paint_band(pt, t, o, a, ink)
  local w = math.min(ink.width, 1.6)
  local b = M.band(t, o, a, w)
  local colour = { [1] = ink.fill[1], [-1] = ink.fill[2] }
  pt:stroke(b.rules, ink.band, 0.5, 1, { many = true })
  -- Side -1 first, so side 1 lies on top wherever it is not painted again.
  for _, side in ipairs({ -1, 1 }) do
    pt:stroke(b.strands[side], ink.band, w, 1)
    pt:stroke(b.strands[side], colour[side], w * 0.55, 1)
  end
  for _, c in ipairs(b.crossings) do
    if c.over == -1 then
      pt:clip_begin(circle(c.x, c.y, c.clip))
      pt:stroke(c.piece, ink.band, w, 1)
      pt:stroke(c.piece, colour[-1], w * 0.55, 1)
      pt:clip_end()
    end
  end
  pt:fill(b.dots, ink.accent, 1, { many = true })
  pt:stroke(b.dots, ink.band, 0.35, 1, { many = true })
  return b
end

return M
