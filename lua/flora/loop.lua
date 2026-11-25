-- A rounded rectangle as a plant's frame (frames.lua), as oval.lua's oval
-- is one: the line a vine follows round the page. A frame point (x, y)
-- lies at arclength s0 + dir k y along the line and k (x - xc) along its
-- inward normal, so the frame's left margin runs round the outside of the
-- line and its text block lies inside it; k scales the frame down to the
-- page, and dir -1 walks the line the other way, which mirrors the plant.
--
-- The line is walked clockwise from its foot's centre: along the foot to
-- the left, round the foot-left corner, up the left side, and so on. Each
-- corner is a quarter circle of radius rc. Every map is a closed form; the
-- inverse takes the nearest point on the line, so it holds within the
-- radius of the corners' arcs either side of the line.

local M = {}
local L = {}
L.__index = L
local pi = math.pi
local cos, sin, atan = math.cos, math.sin, math.atan

-- The line round the box x0, y0, x1, y1 with corners of radius rc (rc > 0,
-- at most half the box's smaller side).
function M.new(x0, y0, x1, y1, rc)
  local o = setmetatable({ x0 = x0, y0 = y0, x1 = x1, y1 = y1, rc = rc }, L)
  local cx0, cy0, cx1, cy1 = x0 + rc, y0 + rc, x1 - rc, y1 - rc
  local mx = (x0 + x1) / 2
  local q = rc * pi / 2
  -- Segments in walking order: a straight one from (ax, ay) along unit
  -- (tx, ty), or an arc about (cx, cy) from angle a0, turning clockwise.
  local segs = {
    { len = mx - cx0, ax = mx, ay = y0, tx = -1, ty = 0 },
    { len = q, cx = cx0, cy = cy0, a0 = -pi / 2 },
    { len = cy1 - cy0, ax = x0, ay = cy0, tx = 0, ty = 1 },
    { len = q, cx = cx0, cy = cy1, a0 = pi },
    { len = cx1 - cx0, ax = cx0, ay = y1, tx = 1, ty = 0 },
    { len = q, cx = cx1, cy = cy1, a0 = pi / 2 },
    { len = cy1 - cy0, ax = x1, ay = cy1, tx = 0, ty = -1 },
    { len = q, cx = cx1, cy = cy0, a0 = 0 },
    { len = cx1 - mx, ax = cx1, ay = y0, tx = -1, ty = 0 },
  }
  local s = 0
  for _, g in ipairs(segs) do
    g.s0 = s
    s = s + g.len
  end
  o.segs, o.len = segs, s
  return o
end

-- The point at arclength u along segment g, and the inward unit normal.
local function seg_at(g, u, rc)
  if g.cx then
    local a = g.a0 - u / rc
    local c, s = cos(a), sin(a)
    return g.cx + rc * c, g.cy + rc * s, -c, -s
  end
  -- Walking clockwise, inward is to the right of travel.
  return g.ax + g.tx * u, g.ay + g.ty * u, g.ty, -g.tx
end

-- The point and inward unit normal at arclength s (any real s). A frame's
-- points come in runs along the line, so the segment of the last call is
-- tried first.
local function at(self, s)
  local len = self.len
  s = s % len
  local segs = self.segs
  local g = segs[self.hint or 1]
  if s < g.s0 or s > g.s0 + g.len then
    for i = 1, #segs do
      g = segs[i]
      if s <= g.s0 + g.len then
        self.hint = i
        break
      end
    end
  end
  return seg_at(g, s - g.s0, self.rc)
end
L.at = at

-- The arclength of the line's point nearest (px, py), in [0, len), and the
-- signed distance from that point to (px, py) along the inward normal.
function L:nearest(px, py)
  local best, bs, bd = math.huge, 0, 0
  local rc = self.rc
  for _, g in ipairs(self.segs) do
    local u
    if g.cx then
      -- The angle turned from the arc's start, clamped to the arc.
      local du = (g.a0 - atan(py - g.cy, px - g.cx)) % (2 * pi)
      if du > pi * 1.25 then du = du - 2 * pi end
      u = math.max(0, math.min(g.len, du * rc))
    else
      u = math.max(0, math.min(g.len, (px - g.ax) * g.tx + (py - g.ay) * g.ty))
    end
    local x, y, nx, ny = seg_at(g, u, rc)
    local d2 = (px - x) ^ 2 + (py - y) ^ 2
    if d2 < best then best, bs, bd = d2, g.s0 + u, (px - x) * nx + (py - y) * ny end
  end
  return bs % self.len, bd
end

-- The arclength of the middle of corner c: 1 foot-left, 2 top-left,
-- 3 top-right, 4 foot-right.
function L:corner(c)
  local g = self.segs[2 * c]
  return g.s0 + g.len / 2
end

-- The maps between a frame laid along the line and the page (see the top
-- of this file). The inverse returns frame y in (-len/4, 3 len/4] / k, so
-- a point behind the frame's foot comes back below it.
function L:maps(s0, xc, k, dir)
  local len = self.len
  local function fn(x, y)
    local px, py, nx, ny = at(self, s0 + dir * k * y)
    local d = k * (x - xc)
    return px + nx * d, py + ny * d
  end
  local function inv(px, py)
    local s, d = self:nearest(px, py)
    local ds = (dir * (s - s0)) % len
    if ds > len * 0.75 then ds = ds - len end
    return xc + d / k, ds / k
  end
  return fn, inv
end

return M
