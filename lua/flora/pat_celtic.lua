-- Celtic knotwork, interlace drawn as mirror curves with alternating
-- over and under crossings. A strand runs diagonally through the midpoints
-- of the edges of a square grid and turns back wherever an edge holds a
-- mirror (as in pat_kolam.lua); every edge midpoint that holds no mirror
-- is a crossing of two strands. Of the two strands at a crossing, the one
-- running along the diagonal dx == dy is over when the crossing lies on a
-- horizontal edge, and under when it lies on a vertical one. A strand
-- alternates between the two kinds of edge, so it alternates between over
-- and under along its whole length, with no exception.
--
-- A cell is one edge midpoint: the square, half a grid unit across, round
-- it, with the pieces of the strands through it. The pieces of
-- neighbouring cells meet at the corners of their squares, so a cell the
-- field drops leaves its strands ending in round caps. Over and under is
-- drawn within the cell: the under strand first, then the over strand on
-- a paper-coloured halo that cuts the under strand where they cross.
--
-- This module is the weave: no mirrors inside the field, so the strands
-- run straight and plait over the whole page. pat_celtic_panels.lua uses
-- the same engine with mirrors laid out as knot panels.

local K = require("flora.pat_kit")
local Paint = require("flora.paint")

local floor, ceil = math.floor, math.ceil

local SCALE = 16
local WIDTH = 3.6
local HALO = 1.45 -- the halo's width, as a multiple of the band's
local PAD = 0.1   -- of the grid unit: how far a cell's curves may bulge past its square
local PULL = 0.25 -- how far a strand turned by a mirror is drawn back from it

local M = { scale = SCALE, width = WIDTH }

-- ------------------------------------------------------------ Strands
-- Coordinates here are doubled: a point (X, Y) is the midpoint of an edge,
-- at (X / 2, Y / 2) grid units, on a vertical edge when X is even and on a
-- horizontal one when Y is even. `inner(X, Y)` says whether an inner edge
-- holds a mirror; the border of the 0..nx by 0..ny grid is all mirrors,
-- so every strand closes into a loop.
--
-- Returns the loops. A loop is a list of points
--   { X, Y, vx, vy, cross, over }
-- in order along the strand, where (vx, vy) is the point the strand is
-- drawn through (grid units): the midpoint itself at a crossing, drawn
-- back from the mirror at a turn.
function M.trace(nx, ny, inner)
  local function mirror(X, Y)
    if X <= 0 or Y <= 0 or X >= 2 * nx or Y >= 2 * ny then return true end
    return inner and inner(X, Y) or false
  end
  local W = 2 * ny + 3
  local N = (2 * nx + 3) * W
  local function id(X, Y) return X * W + Y end
  local seen = {}
  local function seg(X, Y, U, V)
    local p, q = id(X, Y), id(U, V)
    if p > q then p, q = q, p end
    return p * N + q
  end
  local starts = {}
  for i = 0, nx do for j = 0, ny - 1 do starts[#starts + 1] = { 2 * i, 2 * j + 1 } end end
  for i = 0, nx - 1 do for j = 0, ny do starts[#starts + 1] = { 2 * i + 1, 2 * j } end end
  local loops = {}
  for _, s0 in ipairs(starts) do
    for _, d0 in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
      local x, y, dx, dy = s0[1], s0[2], d0[1], d0[2]
      local u, v = x + dx, y + dy
      if u >= 0 and v >= 0 and u <= 2 * nx and v <= 2 * ny and not seen[seg(x, y, u, v)] then
        local pts, sx, sy, sdx, sdy = {}, x, y, dx, dy
        repeat
          u, v = x + dx, y + dy
          seen[seg(x, y, u, v)] = true
          x, y = u, v
          local vx, vy, cross = x / 2, y / 2, false
          if mirror(x, y) then
            if x % 2 == 0 then dx = -dx; vx = vx + dx * PULL else dy = -dy; vy = vy + dy * PULL end
          else
            cross = true
          end
          local horizontal = y % 2 == 0
          pts[#pts + 1] = { X = x, Y = y, vx = vx, vy = vy, cross = cross,
            over = cross and ((dx == dy) == horizontal) }
        until (x == sx and y == sy and dx == sdx and dy == sdy) or #pts > 8 * (nx + 1) * (ny + 1)
        loops[#loops + 1] = pts
      end
    end
  end
  return loops
end

-- ------------------------------------------------------------ Cells
local function split(b, t)
  local function l(p, q) return { p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t } end
  local a, c, d = l(b[1], b[2]), l(b[2], b[3]), l(b[3], b[4])
  local e, f = l(a, c), l(c, d)
  local m = l(e, f)
  return { b[1], a, e, m }, { m, f, d, b[4] }
end

local function path(...)
  local out = {}
  for _, b in ipairs({ ... }) do
    if #out == 0 then out[1] = { "m", b[1][1], b[1][2] } end
    out[#out + 1] = { "c", b[2][1], b[2][2], b[3][1], b[3][2], b[4][1], b[4][2] }
  end
  return out
end

local function paint(pt, c, ink)
  local w = ink.width
  if #c.under > 0 then
    pt:stroke(c.under, ink.band, w, 1, { many = true })
    pt:stroke(c.under_core, ink.accent, w * 0.4, 1, { many = true })
  end
  if #c.over > 0 then
    -- The halo is the page's own colour: the paper, or on a dark backdrop
    -- the ground itself. P:ink would repaint the paper as the ground's
    -- lightness with the paper's warm tint, a visible patch, so the ground
    -- is painted as it is (a nonzero pt.metal keeps a colour unrepainted).
    if pt.backdrop then
      pt.metal = pt.metal + 1
      pt:stroke(c.halo, pt.backdrop, w * HALO, 1, { many = true })
      pt.metal = pt.metal - 1
    else
      pt:stroke(c.halo, Paint.palette.paper, w * HALO, 1, { many = true })
    end
    pt:stroke(c.over, ink.band, w, 1, { many = true })
    pt:stroke(c.over_core, ink.accent, w * 0.4, 1, { many = true })
  end
end

local function construct(pt, c, ink)
  pt:stroke(c.lines, ink.line, 0.4, 1, { many = true })
end

-- The cells for env's box. `inner(X, Y)` is as in M.trace, in doubled
-- coordinates counted from the grid's corner (gx, gy), which is given to
-- the factory `make_inner(gx, gy, nx, ny)` so a layout can tie its mirrors
-- to the page's grid rather than to the box.
function M.cells_with(env, make_inner)
  local a = env.size
  local gx, gy = floor(env.x0 / a) - 1, floor(env.y0 / a) - 1
  local nx, ny = ceil(env.x1 / a) + 1 - gx, ceil(env.y1 / a) + 1 - gy
  local loops = M.trace(nx, ny, make_inner and make_inner(gx, gy, nx, ny, env.rng) or nil)
  local halfwidth = WIDTH / SCALE * a * HALO / 2
  local by_point, out = {}, {}
  for _, pts in ipairs(loops) do
    local n = #pts
    local P = {}
    for i, p in ipairs(pts) do P[i] = { (gx + p.vx) * a, (gy + p.vy) * a } end
    local bz = {}
    for i = 1, n do
      local p0, p1, p2, p3 = P[(i - 2) % n + 1], P[i], P[i % n + 1], P[(i + 1) % n + 1]
      bz[i] = { p1, { p1[1] + (p2[1] - p0[1]) / 6, p1[2] + (p2[2] - p0[2]) / 6 },
        { p2[1] - (p3[1] - p1[1]) / 6, p2[2] - (p3[2] - p1[2]) / 6 }, p2 }
    end
    for i = 1, n do
      local p = pts[i]
      local k = p.X * 100003 + p.Y
      local c = by_point[k]
      if not c then
        local x, y = (gx + p.X / 2) * a, (gy + p.Y / 2) * a
        local r = a / 4
        c = { x = x, y = y, pad = PAD * a, under = {}, over = {}, under_core = {}, over_core = {}, halo = {}, lines = {},
          verts = { { x - r, y - r }, { x + r, y - r }, { x + r, y + r }, { x - r, y + r } },
          paint = paint, construct = construct }
        by_point[k] = c
        out[#out + 1] = c
      end
      local _, h1 = split(bz[(i - 2) % n + 1], 0.5)
      local h2 = split(bz[i], 0.5)
      local piece = path(h1, h2)
      -- The core runs past each end of the piece, to the tip of the band's round cap: a neighbour's
      -- band, painted later, would otherwise cut it where the pieces meet.
      local dx, dy = h1[4][1] - h1[1][1], h1[4][2] - h1[1][2]
      local len = math.max(math.sqrt(dx * dx + dy * dy), 1e-6)
      local e = WIDTH / SCALE * a * 0.3 / len
      local _, g1 = split(h1, -e)
      local g2 = split(h2, 1 + e)
      local core = path(g1, g2)
      c.lines[#c.lines + 1] = piece
      if p.over then
        -- The halo covers the middle of the piece only, its round caps
        -- ending at the piece's ends, so it never reaches into a neighbour.
        local s = math.max(0, math.min(0.5, halfwidth / len))
        local _, t1 = split(h1, s)
        local t2 = split(h2, 1 - s)
        c.over[#c.over + 1] = piece
        c.over_core[#c.over_core + 1] = core
        c.halo[#c.halo + 1] = path(t1, t2)
      else
        c.under[#c.under + 1] = piece
        c.under_core[#c.under_core + 1] = core
      end
    end
  end
  return out
end

return {
  name = "celtic_knot",
  title = "Celtic knotwork, mirror curves with alternating over/under crossings",
  tags = { "celtic", "insular", "interlace", "knot" },
  scale = SCALE,
  width = WIDTH,
  cells = function(env) return M.cells_with(env, nil) end,
  engine = M,
}
