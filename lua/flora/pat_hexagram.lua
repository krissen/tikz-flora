-- Hexagrams (two triangles, one turned half a turn) on a triangular
-- lattice, each tip touching the tip of a neighbour. An emblem pattern: it
-- is opt-in (patterns.lua), picked only by its own name or by the group
-- `symbol`.

local K = require("flora.pat_kit")
local sqrt, cos, sin, rad = math.sqrt, math.cos, math.sin, math.rad

-- How the star is built (pattern_opts.hexagram, a study, ORDER #10):
--   (nil)      the up triangle in the first field, the down triangle over
--              it in the second, so the middle and three tips are one
--              colour and the other three tips the other (today's)
--   star       the whole star in the first field, outlined once; the gaps
--              round it (triangles that pair up into rhombs across the
--              lattice) in the second
--   interlace  the two triangles as broad bands woven over and under at
--              their six crossings, the star's area in the first field
--   weave      the same bands alone, nothing filled
--   mock       as the geometry study's sketch (y-02): the whole star in the
--              first field, the rhombs between the stars light, and a small
--              triangle of the accent at each meeting of six tips
--   outline    the whole star in the first field, the gaps the paper
--   measured   as y-02 measures (ORDER #11): the up triangle in the first
--              field, then the down triangle whole over it in the second,
--              each outlined with a thin dark line as it is laid, so the
--              down triangle hides the up one's lines and shows as one
--              figure; the up triangle shows only as three tips, and the
--              rhombs between the stars are light
-- And with the star whole in one colour, tips and middle alike (ORDER #12),
-- thin dark lines:
--   star-thin  the star in the first field, the gaps in the second
--   plain      the star in the first field, the gaps the paper
--   rows       the stars row by row in the first field and the second, the
--              gaps the paper (two colours cannot keep every pair of
--              touching stars apart on this lattice; a row's stars touch)
--   three      the stars in the first field, the second and the accent,
--              so that no two touching stars share one; the gaps the paper
local THIN = { ["star-thin"] = true, plain = true, rows = true, three = true }
local function paint(pt, c, ink)
  if THIN[c.form] then
    local tones = { ink.fill[1], ink.fill[2], ink.accent }
    if c.form == "star-thin" then
      -- Stroked in their own colour too, so the two halves of a rhomb
      -- leave no seam between them.
      K.fill(pt, c.gaps, ink.fill[2], ink, { many = true })
      if not ink.lines then pt:stroke(c.gaps, ink.fill[2], 0.6, 1, { many = true }) end
    end
    local t = 1
    if c.form == "rows" then t = c.row % 2 + 1 elseif c.form == "three" then t = c.three + 1 end
    K.fill(pt, c.star, tones[t], ink)
    K.band(pt, c.star, ink, { core = false, w = 0.6 })
    return
  end
  if c.form == "measured" then
    K.fill(pt, c.gaps, ink.core, ink, { many = true })
    K.fill(pt, c.up, ink.fill[1], ink)
    K.band(pt, c.up, ink, { core = false, w = 0.6 })
    K.fill(pt, c.down, ink.fill[2], ink)
    K.band(pt, c.down, ink, { core = false, w = 0.6 })
    return
  end
  local form = c.form
  if form == "star" or form == "mock" or form == "outline" then
    K.fill(pt, c.star, ink.fill[1], ink)
    if form == "star" then K.fill(pt, c.gaps, ink.fill[2], ink, { many = true }) end
    if form == "mock" then
      K.fill(pt, c.gaps, ink.core, ink, { many = true })
      K.fill(pt, c.tips, ink.accent, ink, { many = true })
      K.band(pt, c.gaps, ink, { core = false, many = true, w = 0.6 })
    end
    K.band(pt, c.star, ink, { core = false })
    return
  end
  if form == "interlace" or form == "weave" then
    if form == "interlace" then K.fill(pt, c.star, ink.fill[1], ink) end
    local w = 2.4
    K.band(pt, c.down, ink, { w = w })
    K.band(pt, c.up, ink, { w = w })
    -- At every other crossing the down triangle passes over: drawn again
    -- there, through a disc about the crossing.
    for i, q in ipairs(c.crossings) do
      if i % 2 == 0 then
        pt:clip_begin({ { "o", q[1], q[2], ink.width * w * 1.3 } })
        K.band(pt, c.down, ink, { w = w })
        pt:clip_end()
      end
    end
    return
  end
  K.fill(pt, c.up, ink.fill[1], ink)
  K.fill(pt, c.down, ink.fill[2], ink)
  K.band(pt, c.up, ink, { core = false })
  K.band(pt, c.down, ink, { core = false })
end

local function construct(pt, c, ink)
  pt:stroke(c.up, ink.line, 0.4, 1)
  pt:stroke(c.down, ink.line, 0.4, 1)
end

local function triangle(x, y, R, a0)
  local P = {}
  for k = 0, 2 do
    local a = rad(a0 + 120 * k)
    P[#P + 1] = { x + R * cos(a), y + R * sin(a) }
  end
  return P
end

return {
  name = "hexagram_lattice",
  title = "Hexagrams on a triangular lattice, tips touching",
  tags = { "symbol", "hexagram", "triangular", "star" },
  roles = { "band", "a", "b", "core", "accent" },
  surface = true,
  opt_in = true,
  scale = 30,
  width = 1.2, bands = "strap",
  cells = function(env)
    local d = env.size
    local h = d * sqrt(3) / 2
    local R = d / sqrt(3)
    local out = {}
    for j = math.floor(env.y0 / h) - 1, math.ceil(env.y1 / h) + 1 do
      for i = math.floor(env.x0 / d) - 2, math.ceil(env.x1 / d) + 2 do
        local x, y = d * (i + (j % 2) / 2), h * j
        local star = {}
        for k = 0, 5 do
          local a = rad(90 + 60 * k)
          star[#star + 1] = { x + R * cos(a), y + R * sin(a) }
          local b = rad(120 + 60 * k)
          star[#star + 1] = { x + R / sqrt(3) * cos(b), y + R / sqrt(3) * sin(b) }
        end
        -- The lattice's hexagon round the star, for a ground under it.
        local hex = {}
        for k = 0, 5 do
          local a = rad(30 + 60 * k)
          hex[#hex + 1] = { x + R * cos(a), y + R * sin(a) }
        end
        -- The gaps between the star and its hexagon, a triangle on each of
        -- the hexagon's sides; the star's six crossings, its inner corners;
        -- and small triangles about its tips, for the mock's form.
        local gaps, crossings, tips = {}, {}, {}
        for k = 0, 5 do
          local v1, v2 = hex[k % 6 + 1], hex[(k + 1) % 6 + 1]
          local m = rad(60 + 60 * k)
          local inner = { x + R / sqrt(3) * cos(m), y + R / sqrt(3) * sin(m) }
          gaps[#gaps + 1] = K.path({ v1, v2, inner })
          crossings[#crossings + 1] = inner
          local t, r = rad(30 + 60 * k), R * 0.16
          local tip = { x + R * cos(t), y + R * sin(t) }
          tips[#tips + 1] = K.path({ tip, { tip[1] - r * cos(t - rad(30)), tip[2] - r * sin(t - rad(30)) },
            { tip[1] - r * cos(t + rad(30)), tip[2] - r * sin(t + rad(30)) } })
        end
        out[#out + 1] = { x = x, y = y, verts = star, pad = d * 0.02, under = K.path(hex),
          up = K.path(triangle(x, y, R, 90)), down = K.path(triangle(x, y, R, 270)),
          star = K.path(star), gaps = gaps, crossings = crossings, tips = tips,
          form = env.opts and env.opts.hexagram, row = j,
          -- A colour of three per star, no two touching stars alike: the
          -- star's axial coordinates' difference, modulo 3.
          three = ((i - (j - j % 2) / 2) - j) % 3,
          paint = paint, construct = construct }
      end
    end
    return out
  end,
}
