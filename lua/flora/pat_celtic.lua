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

-- Under the line band character each strand is one line, and the halo
-- that parts it from the strand it crosses keeps a gap of 0.8 pt either
-- side of it.
local function paint(pt, c, ink)
  local line = ink.bands == "line"
  local w = line and (ink.linew or 0.6) or ink.width
  local core = not line and w * (ink.corefrac or 0.4) or 0
  if core > 0 and (w - core) / 2 < K.CONTOUR_MIN then core = w - 2 * K.CONTOUR_MIN end
  if core < K.CORE_MIN then core = 0 end
  local hw = line and w + 1.6 or w * HALO
  if #c.under > 0 then
    pt:stroke(c.under, ink.band, w, 1, { many = true })
    if core > 0 then pt:stroke(c.under_core, ink.accent, core, 1, { many = true }) end
  end
  if #c.over > 0 then
    -- The halo is the page's own colour: the paper, or on a dark backdrop
    -- the ground itself. P:ink would repaint the paper as the ground's
    -- lightness with the paper's warm tint, a visible patch, so the ground
    -- is painted as it is (a nonzero pt.metal keeps a colour unrepainted).
    if pt.backdrop then
      pt.metal = pt.metal + 1
      pt:stroke(c.halo, pt.backdrop, hw, 1, { many = true })
      pt.metal = pt.metal - 1
    else
      pt:stroke(c.halo, Paint.palette.paper, hw, 1, { many = true })
    end
    pt:stroke(c.over, ink.band, w, 1, { many = true })
    if core > 0 then pt:stroke(c.over_core, ink.accent, core, 1, { many = true }) end
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
  local inner, alive, group
  if make_inner then inner, alive, group = make_inner(gx, gy, nx, ny, env.rng) end
  -- Under a second drawing (pattern.lua's reweave) every crossing the
  -- field dropped is a mirror, so the strands turn back at the field's
  -- edge instead of ending there.
  local blocked = env.blocked and function(X, Y) return env.blocked((gx + X / 2) * a, (gy + Y / 2) * a) end
  local walls = inner
  if blocked then walls = function(X, Y) return blocked(X, Y) or (inner and inner(X, Y)) or false end end
  local loops = M.trace(nx, ny, walls)
  if blocked then
    -- A strand wholly among dropped crossings is dropped with them.
    local live = {}
    for _, pts in ipairs(loops) do
      for _, q in ipairs(pts) do
        if not blocked(q.X, q.Y) then live[#live + 1] = pts; break end
      end
    end
    loops = live
  end
  if alive then
    -- A layout's own panels (M.panels): a strand with no crossing inside a
    -- panel lies wholly in the space between them and is not drawn.
    local live = {}
    for _, pts in ipairs(loops) do
      for _, q in ipairs(pts) do
        if alive(q.X, q.Y) then live[#live + 1] = pts; break end
      end
    end
    loops = live
  end
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
        if group then c.group, c.fixed = group(p.X, p.Y), true end
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

-- ------------------------------------------------------------ Panels
-- Closed knot panels laid out in the field's own room (pattern_opts.knot,
-- a study, ORDER #12, after the sketches y-06 and y-08): each panel a
-- rectangle of whole grid units whose border is all mirrors, so its
-- strands close into a finished edge all round, and a plain plait inside.
--   one       one panel per side the field takes, as large as the room
--             beside the text allows
--   several   square panels of n units (opts.knot_n, default 7, as the
--             sketches measure) side by side, a unit of paper between
--             them, as many as fit
--   bleed     (ORDER #13) the whole field one panel, out to the paper's
--             edges where the field reaches them: the plait runs off the
--             paper there and turns back only at the text, the hero and
--             whatever else the field keeps clear of
--   inset     the same, but turning back half a unit inside the paper's
--             edges too, a finished panel filling the field
-- The panels' cells keep clear of the text without thinning toward it and
-- fall away a panel at a time (the field's panel, under bleed and inset,
-- is never cut).
function M.panel_rects(env, mode, n)
  local a, room = env.size, env.room
  if not room then return {} end
  local t, gap, side = room.text, room.gap, room.side
  -- The loops' turns stand out about a quarter unit past the border, plus
  -- the band's reach; half a unit of paper is kept from the page's edge.
  local over = 0.25 + (room.reach + 1) / a
  local strips = {}
  local y0 = math.ceil(0.5 + over)
  local y1 = math.floor(room.top / a - 0.5 - over)
  if not side or side.left then strips[#strips + 1] = { math.ceil(0.5 + over), math.floor((t.x0 - gap) / a - over) } end
  if not side or side.right then strips[#strips + 1] = { math.ceil((t.x1 + gap) / a + over), math.floor(room.W / a - 0.5 - over) } end
  local rects = {}
  for _, st in ipairs(strips) do
    local x0, x1 = st[1], st[2]
    if mode == "one" then
      if x1 - x0 >= 2 and y1 - y0 >= 2 then rects[#rects + 1] = { x0, y0, x1, y1 } end
    else
      local cols = math.floor((x1 - x0 + 1) / (n + 1))
      local rows = math.floor((y1 - y0 + 1) / (n + 1))
      if cols >= 1 and rows >= 1 then
        -- Centred in the strip, on whole units.
        local sx = x0 + math.floor(((x1 - x0) - (cols * (n + 1) - 1)) / 2)
        local sy = y0 + math.floor(((y1 - y0) - (rows * (n + 1) - 1)) / 2)
        for i = 0, cols - 1 do
          for j = 0, rows - 1 do
            local px, py = sx + i * (n + 1), sy + j * (n + 1)
            rects[#rects + 1] = { px, py, px + n, py + n }
          end
        end
      end
    end
  end
  return rects
end

function M.panels_inner(env, mode, n)
  local rects = M.panel_rects(env, mode, n)
  return function(gx, gy)
    local function where(X, Y)
      local x, y = gx + X / 2, gy + Y / 2
      for k, r in ipairs(rects) do
        if x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then
          local edge = (X % 2 == 0 and (x == r[1] or x == r[3])) or (Y % 2 == 0 and (y == r[2] or y == r[4]))
          return k, edge
        end
      end
      return nil
    end
    local function inner(X, Y)
      local k, edge = where(X, Y)
      return not k or edge
    end
    local function alive(X, Y)
      local k, edge = where(X, Y)
      return k ~= nil and not edge
    end
    local function group(X, Y)
      local k = where(X, Y)
      return "panel " .. tostring(k)
    end
    return inner, alive, group
  end
end

-- The field as whole grid squares (bleed and inset): a square belongs to
-- it when it lies on the field's side, inside the paper (or a unit past
-- its edges under bleed, half a unit inside them under inset) and far
-- enough from everything the field keeps clear of that a strand turning
-- back at its edge stays clear too.
function M.field_inner(env, mode)
  local a, room = env.size, env.room
  return function(gx, gy)
    local function inside(i, j)
      if not room then return false end
      local x0, y0, x1, y1 = i * a, j * a, (i + 1) * a, (j + 1) * a
      -- A turn stands out a quarter unit past the square's edge, the cell
      -- round it a quarter more, and the band reaches past that.
      local clear = room.gap + room.reach + 0.6 * a + 0.5
      local t, side = room.text, room.side
      if side and side.left and not side.right and x1 > t.x0 - clear then return false end
      if side and side.right and not side.left and x0 < t.x1 + clear then return false end
      if side and side.left and side.right and x1 > t.x0 - clear and x0 < t.x1 + clear then return false end
      local bleed = mode == "bleed" and room.outer ~= "margin"
      local m = bleed and -a or (room.outer == "margin" and 4 or 0) + room.reach + 0.6 * a
      if x0 < m or x1 > room.W - m or y0 < m then return false end
      -- The page's painted top is a content edge (a header) unless it is
      -- the paper's own.
      local mt = (bleed and room.top >= room.H) and -a or room.reach + 0.6 * a + (room.top < room.H and room.gap or 0)
      if y1 > room.top - mt then return false end
      for _, r in ipairs(room.avoid or {}) do
        if x1 > r[1] - clear and x0 < r[3] + clear and y1 > r[2] - clear and y0 < r[4] + clear then return false end
      end
      local h = room.hero
      if h then
        local dx = math.max(x0 - h[1], 0, h[1] - x1)
        local dy = math.max(y0 - h[2], 0, h[2] - y1)
        if math.sqrt(dx * dx + dy * dy) < h[3] + clear then return false end
      end
      return true
    end
    local memo, memo2 = {}, {}
    local function raw(i, j)
      local k = i * 100003 + j
      if memo[k] == nil then memo[k] = inside(i, j) end
      return memo[k]
    end
    -- Only squares in some two-by-two block of the field: a strip one unit
    -- wide (beside a short line of text, say) would be a lone rope, not
    -- plait.
    local function sq(i, j)
      local k = i * 100003 + j
      if memo2[k] == nil then
        local ok = false
        if raw(i, j) then
          for _, d in ipairs({ { 0, 0 }, { -1, 0 }, { 0, -1 }, { -1, -1 } }) do
            local a0, b0 = i + d[1], j + d[2]
            if raw(a0, b0) and raw(a0 + 1, b0) and raw(a0, b0 + 1) and raw(a0 + 1, b0 + 1) then ok = true end
          end
        end
        memo2[k] = ok
      end
      return memo2[k]
    end
    -- Doubled coordinates: an edge midpoint between two squares of the
    -- field is a crossing; every other one is a mirror.
    local function both(X, Y)
      local x, y = gx + X / 2, gy + Y / 2
      if X % 2 == 0 then
        local j = math.floor(y)
        return sq(x - 1, j) and sq(x, j)
      end
      local i = math.floor(x)
      return sq(i, y - 1) and sq(i, y)
    end
    local function inner(X, Y) return not both(X, Y) end
    local function alive(X, Y) return both(X, Y) end
    local function group() return "field" end
    return inner, alive, group
  end
end

function M.cells(env)
  local mode = env.opts and env.opts.knot
  if mode == "bleed" or mode == "inset" then
    return M.cells_with(env, M.field_inner(env, mode))
  end
  if mode == "one" or mode == "several" then
    return M.cells_with(env, M.panels_inner(env, mode, env.opts.knot_n or 7))
  end
  return M.cells_with(env, nil)
end

return {
  name = "celtic_knot",
  title = "Celtic knotwork, mirror curves with alternating over/under crossings",
  tags = { "celtic", "insular", "interlace", "knot" },
  roles = { "band", "accent", "paper" },
  scale = SCALE,
  width = WIDTH, core = 0.4, bands = "strap",
  cells = function(env) return M.cells(env) end,
  -- It can be drawn again with the field's edge as a wall (pattern.lua),
  -- and by default is (the ends key).
  reweave = true, ends = "closed",
  engine = M,
}
