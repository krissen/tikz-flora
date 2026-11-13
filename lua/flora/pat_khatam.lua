-- Khatam: eight-pointed stars, each of two squares turned 45 degrees to
-- one another, on a square lattice. An emblem pattern: opt-in
-- (patterns.lua), picked only by its own name or by the group `symbol`.
-- The stars are light, on the paper's colour, with a dot of the second
-- field at their hearts, and the gaps between them are the first field:
-- each star's cell fills its square of the lattice and lays the star over
-- it, its tips short of its neighbours'.

local K = require("flora.pat_kit")
local cos, sin, rad = math.cos, math.sin, math.rad
local STAR = 0.78

-- The field round the stars is the cell's plate (pattern.lua paints the
-- plates with the ground, so neighbouring squares leave no seam).
local function paint_star(pt, c, ink)
  K.fill(pt, c.star, ink.core, ink)
  K.band(pt, c.star, ink, { core = false })
  K.fill(pt, c.dot, ink.fill[2], ink)
  K.band(pt, c.dot, ink, { core = false, w = 0.5 })
end

local function construct_star(pt, c, ink)
  pt:stroke(c.square, ink.line, 0.4, 1)
  pt:stroke(c.diamond, ink.line, 0.4, 1)
end

local function square(x, y, r, a0)
  local P = {}
  for k = 0, 3 do
    local a = rad(a0 + 90 * k)
    P[#P + 1] = { x + r * cos(a), y + r * sin(a) }
  end
  return P
end

-- Stars and crosses (pattern_opts.khatam, a study, ORDER #12): the same
-- star at full size, its tips meeting its neighbours', so the stars tile
-- the plane with crosses that have pointed arms between them, as y-03
-- does. The star is the cell; a cross lies between four stars and is
-- laid only when all four are kept, so the field ends along the stars'
-- own outline. Thin dark lines throughout.
--   two       the star's square on its point in the first field and the
--             other square's four corners in the second; the cross light
--             (the paper's colour); as y-03
--   one       the whole star in the first field, the cross in the second
--   paper     the whole star in the first field, the cross the paper
--   dot       as one, with a dot of the accent at the cross's heart
-- For two equal squares of circumradius r, a corner of the one stands out
-- past the other's side as a right isosceles triangle of height
-- r (1 - 1/sqrt 2); the cross's arms are a (2 - sqrt 2) / 4 wide on each
-- side of its axis, a the lattice's period.
local DOT = 0.06 -- the cross's dot's radius, in periods (measured on y-03)
local TILED = { two = true, one = true, paper = true, dot = true }

local function paint_tiled(pt, c, ink)
  if c.form == "two" then
    K.fill(pt, c.diamond, ink.fill[1], ink)
    K.fill(pt, c.corners, ink.fill[2], ink, { many = true })
    K.band(pt, c.corners, ink, { core = false, many = true, w = 0.6 })
  else
    K.fill(pt, c.star, ink.fill[1], ink)
  end
  K.band(pt, c.star, ink, { core = false, w = 0.6 })
end

local function construct_tiled(pt, c, ink)
  pt:stroke(c.star, ink.line, 0.4, 1)
end

-- The cross whose centre is (X, Y), between four stars a apart.
local function cross(X, Y, a)
  local h, w = a / 2, a * (2 - math.sqrt(2)) / 4
  local P = {}
  for k = 0, 3 do
    local ca, sa = cos(rad(90 * k)), sin(rad(90 * k))
    local function at(u, v) return { X + u * ca - v * sa, Y + u * sa + v * ca } end
    P[#P + 1] = at(h, 0)
    P[#P + 1] = at(h - w, w)
    P[#P + 1] = at(w, w)
    P[#P + 1] = at(w, h - w)
  end
  return P
end

local function tiled_cell(x, y, a, outline, form)
  local r = a / 2
  local q = r / math.sqrt(2)
  local corners = {}
  for _, s in ipairs({ { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }) do
    local sx, sy = s[1], s[2]
    corners[#corners + 1] = K.path({ { x + sx * q, y + sy * q }, { x + sx * q, y + sy * (r - q) }, { x + sx * (r - q), y + sy * q } })
  end
  local X, Y = x + r, y + r
  local around = { { x, y }, { x + a, y }, { x, y + a }, { x + a, y + a } }
  local plates = {}
  if form == "one" or form == "dot" then plates[#plates + 1] = { K.path(cross(X, Y, a)), "b", between = around } end
  if form == "dot" then plates[#plates + 1] = { { { "o", X, Y, a * DOT } }, "accent", between = around } end
  return { x = x, y = y, verts = outline, pad = a * 0.02, plates = plates, under = K.path(outline),
    star = K.path(outline), diamond = K.path(square(x, y, r, 0)), corners = corners, form = form,
    paint = paint_tiled, construct = construct_tiled }
end


return {
  name = "khatam",
  title = "Khatam, eight-pointed stars of two squares on a square lattice, light on a coloured ground",
  tags = { "symbol", "khatam", "star", "square" },
  roles = { "band", "core", "a", "b" },
  surface = true,
  opt_in = true,
  scale = 28,
  width = 1.2, bands = "strap",
  cells = function(env)
    local a = env.size
    local out = {}
    -- The star's tips, short of the square's edge so the field shows
    -- between neighbours.
    local r = a * 0.5 * STAR
    for i = math.floor(env.x0 / a) - 1, math.ceil(env.x1 / a) + 1 do
      for j = math.floor(env.y0 / a) - 1, math.ceil(env.y1 / a) + 1 do
        local x, y = i * a, j * a
        local form = env.opts and TILED[env.opts.khatam] and env.opts.khatam
        local R = form and a / 2 or r
        local Rin = R * math.cos(rad(45)) / math.cos(rad(22.5))
        local outline = {}
        for k = 0, 7 do
          local t, u = rad(45 * k), rad(45 * k + 22.5)
          outline[#outline + 1] = { x + R * cos(t), y + R * sin(t) }
          outline[#outline + 1] = { x + Rin * cos(u), y + Rin * sin(u) }
        end
        if form then
          out[#out + 1] = tiled_cell(x, y, a, outline, form)
          goto next
        end
        local sq = { { x - a / 2, y - a / 2 }, { x + a / 2, y - a / 2 }, { x + a / 2, y + a / 2 }, { x - a / 2, y + a / 2 } }
        out[#out + 1] = { x = x, y = y, verts = sq, pad = a * 0.02, plates = { { K.path(sq), "a" } }, under = K.path(sq), star = K.path(outline),
          -- At the field's edge (pattern.lua's shape edge) the field ends
          -- along the star's outline, a little out from it.
          shape = K.path(K.scaled(outline, x, y, 1.14)),
          dot = { { "o", x, y, a * 0.08 } },
          square = K.path(square(x, y, r, 45)), diamond = K.path(square(x, y, r, 0)),
          paint = paint_star, construct = construct_star }
        ::next::
      end
    end
    return out
  end,
}
