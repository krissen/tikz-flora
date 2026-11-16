-- What a pattern's cells paint, measured from the paint itself: every
-- fill and stroke a cell lays (its piece of the ground, its plates, its
-- construction lines and its bands), not the outline the field placed it
-- by. tests/test_pattern_reach.lua runs it over every pattern x ground x
-- edge x layout x outer and hero, and proves that it fails when a cell's
-- paint is left out of its clearance.
--
--   M.page(opts) -> pt, points   paint a page; points are { x, y, r, kind }
--                                for every Bezier point (control points
--                                included, so the paint lies within them) of
--                                the cells' paint, r half the stroke width
--   M.check(pt, points, outer, top) -> list of failures, each naming what
--                                the paint came too near
--
-- The hero's rings and the border round the text are the field's own
-- frame, not a cell's, and pattern_hero.lua and tests/test_pattern.lua
-- bound them; they are not recorded here.

local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Progression = require("flora.progression")

local M = {}

-- The progression parts that paint a cell.
M.CELL = { pattern_ground = true, pattern_line = true, pattern = true }

-- The field's own distances (pattern.lua): the gap kept from the hero and
-- the margin kept from the paper's edge under outer=margin.
local HERO_GAP, OUTER_MARGIN = 6, 4

local function each_point(cmds, w, f)
  for _, c in ipairs(cmds) do
    if type(c[1]) == "table" then each_point(c, w, f)
    elseif c[1] == "o" then f(c[2], c[3], c[4] + w / 2)
    elseif c[1] ~= "z" then for i = 2, #c, 2 do f(c[i], c[i + 1], w / 2) end
    end
  end
end

-- A clip lets through only what lies inside it: a point painted under one
-- is held to the clip's box, so a cell clipped to its tile is measured by
-- what shows.
local function clip_box(cmds)
  local b = { math.huge, math.huge, -math.huge, -math.huge }
  each_point(cmds, 0, function(x, y, r)
    b[1], b[2] = math.min(b[1], x - r), math.min(b[2], y - r)
    b[3], b[4] = math.max(b[3], x + r), math.max(b[4], y + r)
  end)
  return b
end

function M.page(opts)
  local sp = { width = 360, height = 270, text = { x0 = 120, y0 = 40, x1 = 330, y1 = 230 }, seed = 7, layout = "left" }
  for k, v in pairs(opts or {}) do sp[k] = v end
  local points, kind, clips = {}, nil, {}
  local function record(self, cmds, w, many)
    if not (self.group and self.group.tag == "pattern" and M.CELL[kind]) then return end
    local box = clips[#clips]
    each_point(many and cmds or { cmds }, w or 0, function(x, y, r)
      if box then
        -- The paint shows only inside the clip.
        x = math.max(box[1], math.min(box[3], x))
        y = math.max(box[2], math.min(box[4], y))
        r = 0
      end
      points[#points + 1] = { x, y, r, kind }
    end)
  end
  local fill, stroke, part = Paint.fill, Paint.stroke, Progression.part
  local clip_begin, clip_end = Paint.clip_begin, Paint.clip_end
  Paint.fill = function(self, cmds, rgb, opacity, o)
    record(self, cmds, 0, o and o.many)
    return fill(self, cmds, rgb, opacity, o)
  end
  Paint.stroke = function(self, cmds, rgb, w, opacity, o)
    record(self, cmds, w, o and o.many)
    return stroke(self, cmds, rgb, w, opacity, o)
  end
  Paint.clip_begin = function(self, cmds, ...)
    local b = clip_box(cmds)
    local up = clips[#clips]
    if up then b = { math.max(b[1], up[1]), math.max(b[2], up[2]), math.min(b[3], up[3]), math.min(b[4], up[4]) } end
    clips[#clips + 1] = b
    return clip_begin(self, cmds, ...)
  end
  Paint.clip_end = function(self, ...)
    clips[#clips] = nil
    return clip_end(self, ...)
  end
  Progression.part = function(pt, k, anchor, birth, duration, fn, ...)
    return part(pt, k, anchor, birth, duration, function()
      local up = kind
      kind = k
      local ok, r = pcall(fn)
      kind = up
      if not ok then error(r, 0) end
      return r
    end, ...)
  end
  Paint.reset_resources()
  local ok, pt = pcall(Compose.page, sp)
  Paint.fill, Paint.stroke, Progression.part = fill, stroke, part
  Paint.clip_begin, Paint.clip_end = clip_begin, clip_end
  if not ok then error(pt, 0) end
  return pt, points, sp
end

local function rdist(x, y, r)
  local dx, dy = math.max(r[1] - x, 0, x - r[3]), math.max(r[2] - y, 0, y - r[4])
  return math.sqrt(dx * dx + dy * dy)
end

-- Every recorded point against the text (pt.pattern.avoid, by the field's
-- gap), the hero's disc and, under outer=margin, the page's margin below
-- `top`. Returns the failures, each "what: kind at x,y by d".
function M.check(pt, points, outer, W, top)
  local info, out = pt.pattern, {}
  local eps = 1e-6
  local function bad(what, q, d)
    out[#out + 1] = string.format("%s: %s at %.2f,%.2f short by %.3f", what, q[4], q[1], q[2], d)
  end
  for _, q in ipairs(points) do
    local x, y, r = q[1], q[2], q[3]
    for _, rc in ipairs(info.avoid) do
      local d = rdist(x, y, rc) - r
      if d < info.gap - eps then bad("text", q, info.gap - d) end
    end
    local h = info.hero
    if h then
      local d = math.sqrt((x - h[1]) ^ 2 + (y - h[2]) ^ 2) - h[3] - r
      if d < HERO_GAP - eps then bad("hero", q, HERO_GAP - d) end
    end
    if outer == "margin" then
      local d = math.min(x - r, y - r, W - (x + r), top - (y + r))
      if d < OUTER_MARGIN - eps then bad("margin", q, OUTER_MARGIN - d) end
    end
  end
  return out
end

-- The sweep: every pattern x ground (off, on) x edge x layout (left,
-- surround) x { bleed, margin, bleed with a hero } x scale (1, 3), at
-- density 10, where the field comes nearest the text. `filter(name)`
-- limits it to some patterns. Returns cells, failures; a cell is
-- { where, points, kept }.
local LINES = {}
for k = 0, 9 do LINES[#LINES + 1] = { x0 = 120, x1 = 330 - (k % 3) * 40, y0 = 210 - k * 17, y1 = 220 - k * 17 } end
M.VARIANTS = { { outer = "bleed" }, { outer = "margin" }, { outer = "bleed", hero = "rose" } }
M.EDGES = { "dissolve", "cell", "fade", "border", "guilloche" }

function M.run(filter)
  local Patterns = require("flora.patterns")
  local cells, failures = {}, {}
  for _, p in ipairs(Patterns.list) do
    if not filter or filter(p.name) then
      for _, ground in ipairs({ "off", "on" }) do
        for _, edge in ipairs(M.EDGES) do
          for _, layout in ipairs({ "left", "surround" }) do
            for _, v in ipairs(M.VARIANTS) do
              for _, scale in ipairs({ 1, 3 }) do
                local pt, points = M.page({ pattern = { [p.name] = 1 }, pattern_ground = ground, pattern_edge = edge,
                  layout = layout, lines = layout == "surround" and LINES or nil, pattern_outer = v.outer,
                  pattern_hero = v.hero, pattern_scale = scale, mix = { density = 10 } })
                local where = string.format("%s ground=%s edge=%s %s outer=%s hero=%s scale=%s", p.name, ground, edge,
                  layout, v.outer, v.hero or "none", scale)
                cells[#cells + 1] = { where = where, points = #points, kept = pt.pattern.cells }
                local fs = M.check(pt, points, v.outer, 360, 270)
                if #fs > 0 then failures[#failures + 1] = where .. ": " .. #fs .. " points, first " .. fs[1] end
              end
            end
          end
        end
      end
    end
  end
  return cells, failures
end

return M
