-- What a pattern paints off its ground's panel (tests/pattern_matrix.lua's
-- onpanel): paint a page, keep the ground's panel (the first fill of the
-- pattern_ground part) and every point the cells paint (Bezier control
-- points included, with half their stroke's width), and measure how far
-- each cell's paint lies outside the panel's rectangles, on the paper.
--
--   M.check_page(spec) -> pt, { cells, worst, examples }
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Progression = require("flora.progression")
local M = {}
local function each_point(cmds, w, f)
  for _, c in ipairs(cmds) do
    if type(c[1]) == "table" then each_point(c, w, f)
    elseif c[1] == "o" then
      for k = 0, 7 do local a = k * math.pi / 4; f(c[2] + c[4] * math.cos(a), c[3] + c[4] * math.sin(a), w / 2) end
    elseif c[1] ~= "z" then for i = 2, #c, 2 do f(c[i], c[i + 1], w / 2) end
    end
  end
end
-- The panel's rectangles (its subpaths of moves and lines).
local function rects(cmds)
  local out, cur = {}, nil
  for _, c in ipairs(cmds) do
    if c[1] == "m" then cur = { c[2], c[3], c[2], c[3] }; out[#out + 1] = cur
    elseif c[1] == "l" then
      cur[1], cur[2] = math.min(cur[1], c[2]), math.min(cur[2], c[3])
      cur[3], cur[4] = math.max(cur[3], c[2]), math.max(cur[4], c[3])
    end
  end
  return out
end
-- How far point (x, y), radius r, lies outside the union of rects: 0 when
-- every one of nine samples of it lies in some rect.
local function outside(R, x, y, r)
  local worst = 0
  for k = 0, 8 do
    local px, py = x, y
    if k > 0 then local a = (k - 1) * math.pi / 4; px, py = x + r * math.cos(a), y + r * math.sin(a) end
    local best = math.huge
    for _, q in ipairs(R) do
      local dx = math.max(q[1] - px, 0, px - q[3])
      local dy = math.max(q[2] - py, 0, py - q[4])
      best = math.min(best, math.sqrt(dx * dx + dy * dy))
    end
    worst = math.max(worst, best)
  end
  return worst
end
function M.check_page(spec)
  local panel, points, kind, owner = nil, {}, nil, nil
  local fill, stroke, part = Paint.fill, Paint.stroke, Progression.part
  Paint.fill = function(self, cmds, rgb, op, o)
    if self.group and self.group.tag == "pattern" then
      if kind == "pattern_ground" then panel = panel or cmds
      elseif kind == "pattern" or kind == "pattern_line" then
        each_point(o and o.many and cmds or { cmds }, 0, function(x, y, r) points[#points + 1] = { x, y, r, owner } end)
      end
    end
    return fill(self, cmds, rgb, op, o)
  end
  Paint.stroke = function(self, cmds, rgb, w, op, o)
    if self.group and self.group.tag == "pattern" and (kind == "pattern" or kind == "pattern_line") then
      each_point(o and o.many and cmds or { cmds }, w or 0, function(x, y, r) points[#points + 1] = { x, y, r, owner } end)
    end
    return stroke(self, cmds, rgb, w, op, o)
  end
  Progression.part = function(pt, k, anchor, birth, dur, fn, ...)
    return part(pt, k, anchor, birth, dur, function()
      local up, uo = kind, owner
      kind, owner = k, anchor
      local ok, r = pcall(fn)
      kind, owner = up, uo
      if not ok then error(r, 0) end
      return r
    end, ...)
  end
  Paint.reset_resources()
  local ok, pt = pcall(Compose.page, spec)
  Paint.fill, Paint.stroke, Progression.part = fill, stroke, part
  if not ok then error(pt, 0) end
  local res = { cells = 0, worst = 0, examples = {} }
  if not panel then return pt, res end
  local R = rects(panel)
  local per = {}
  local W, H = spec.width, spec.height
  for _, q in ipairs(points) do
    -- What lies off the paper is not seen; a point straddling its edge
    -- counts where it meets the paper.
    local x, y, r = q[1], q[2], q[3]
    local off = x + r < 0 or x - r > W or y + r < 0 or y - r > H
    if not off and (x - r < 0 or x + r > W or y - r < 0 or y + r > H) then
      x, y, r = math.max(0, math.min(W, x)), math.max(0, math.min(H, y)), 0
    end
    local d = off and 0 or outside(R, x, y, r)
    if d > 1e-6 then
      local key = q[4] and string.format("%.1f,%.1f", q[4][1], q[4][2]) or "?"
      per[key] = math.max(per[key] or 0, d)
    end
  end
  for key, d in pairs(per) do
    res.cells = res.cells + 1
    res.worst = math.max(res.worst, d)
    res.examples[#res.examples + 1] = string.format("cell at %s reaches %.2f pt outside the panel", key, d)
  end
  table.sort(res.examples)
  res.panel = R
  return pt, res
end
return M
