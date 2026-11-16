-- Hexagrams (two triangles, one turned half a turn) on a triangular
-- lattice, each tip touching the tip of a neighbour. An emblem pattern: it
-- is opt-in (patterns.lua), picked only by its own name or by the group
-- `symbol`.

local K = require("flora.pat_kit")
local sqrt, cos, sin, rad = math.sqrt, math.cos, math.sin, math.rad

-- The whole star is one figure in one colour, its six tips and its middle
-- alike, outlined in a thin dark line (ORDER #13). The rhombs between the
-- stars (each two triangles, one from each star's hexagon) lie between two
-- stars and are laid only when both are kept (pattern.lua's plates,
-- `between`), so the field ends along the stars' outline. The gaps and
-- alternate keys (Settings.PATTERN) choose the colours:
--   gaps=field (the default)   the rhombs in the second field
--   gaps=paper                 the rhombs the paper
--   alternate=off (the default) every star in the first field
--   alternate=rows             the first field and the second, row by row
--                              (two colours cannot keep every pair of
--                              touching stars apart on this lattice: a
--                              row's stars touch)
--   alternate=three            the first field, the second and the accent,
--                              no two touching stars alike
-- Under rows and three the rhombs are the paper, as a star in the second
-- field would run into rhombs of its own colour.
local function paint(pt, c, ink)
  local tones = { ink.fill[1], ink.fill[2], ink.accent }
  K.fill(pt, c.star, tones[c.tone], ink)
  K.band(pt, c.star, ink, { core = false, w = 0.6 })
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
  title = "Hexagrams on a triangular lattice, tips touching, each star one colour",
  tags = { "symbol", "hexagram", "triangular", "star" },
  roles = { "band", "a", "b", "accent" },
  surface = true,
  opt_in = true,
  scale = 30,
  width = 1.2, bands = "strap",
  gaps = "field", alternate = "off",
  cells = function(env)
    local d = env.size
    local h = d * sqrt(3) / 2
    local R = d / sqrt(3)
    local style = env.style or {}
    local alt = style.alternate or "off"
    local rhombs = style.gaps ~= "paper" and alt == "off"
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
        -- The rhombs on three of the hexagon's sides (the other three are
        -- the neighbours'): the gap between this star and its hexagon on
        -- that side and the neighbour's gap across it.
        local plates = {}
        if rhombs then
          for k = 0, 2 do
            local v1, v2 = hex[k % 6 + 1], hex[(k + 1) % 6 + 1]
            local m = rad(60 + 60 * k)
            local inner = { x + R / sqrt(3) * cos(m), y + R / sqrt(3) * sin(m) }
            local mx, my = (v1[1] + v2[1]) / 2, (v1[2] + v2[2]) / 2
            local other = { 2 * mx - inner[1], 2 * my - inner[2] }
            plates[#plates + 1] = { K.path({ v1, inner, v2, other }), "b",
              between = { { x, y }, { 2 * mx - x, 2 * my - y } } }
          end
        end
        local tone = 1
        if alt == "rows" then tone = j % 2 + 1
        elseif alt == "three" then
          -- The star's axial coordinates' difference, modulo 3.
          tone = ((i - (j - j % 2) / 2) - j) % 3 + 1
        end
        out[#out + 1] = { x = x, y = y, verts = star, pad = d * 0.02, under = K.path(hex), plates = plates,
          up = K.path(triangle(x, y, R, 90)), down = K.path(triangle(x, y, R, 270)),
          star = K.path(star), tone = tone, paint = paint, construct = construct }
      end
    end
    return out
  end,
}
