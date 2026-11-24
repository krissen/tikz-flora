-- Whether anything a pattern paints lies on a protected area: the page's
-- text, its reservations and its lines, within the field's gap of them.
-- Unlike tests/pattern_reach.lua, which measures how far each painted
-- point lies from them, this measures overlap: a filled shape that holds a
-- protected area inside it, with every point far outside, still fails.
-- The paint is taken as drawn (Bezier control polygons, circles, strokes
-- with half their width), from the pattern's cells, their construction
-- lines, the ground (its pieces, its panel and the plates between cells)
-- and the hero.
--
--   M.overlaps(spec) -> pt, list of { kind, rect, paint }
--   M.sweep(filter, opts) -> cells, failures   (the forms x plan x edges
--                                              x layouts x backdrops sweep)
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Progression = require("flora.progression")
local Settings = require("flora.settings")
local Patterns = require("flora.patterns")
local Pattern = require("flora.pattern")

local M = {}
local KINDS = { pattern = true, pattern_line = true, pattern_ground = true, pattern_hero = true, pattern_hero_line = true }

-- A path as its subpaths: each a list of points (control points
-- included) and its circles.
local function shapes(cmds, out)
  out = out or { polys = {}, discs = {} }
  local cur
  for _, c in ipairs(cmds) do
    if type(c[1]) == "table" then shapes(c, out)
    elseif c[1] == "o" then out.discs[#out.discs + 1] = { c[2], c[3], c[4] }
    elseif c[1] == "m" then cur = { { c[2], c[3] } }; out.polys[#out.polys + 1] = cur
    elseif c[1] == "z" then cur = nil
    else
      if not cur then cur = {}; out.polys[#out.polys + 1] = cur end
      for i = 2, #c, 2 do cur[#cur + 1] = { c[i], c[i + 1] } end
    end
  end
  return out
end

local function rect_dist(x, y, r)
  local dx = math.max(r[1] - x, 0, x - r[3])
  local dy = math.max(r[2] - y, 0, y - r[4])
  return math.sqrt(dx * dx + dy * dy)
end
-- One of Liang-Barsky's clips: the range t0..t1 the edge with p and q
-- leaves, or nil when the segment misses it.
local function clip(p, q, t0, t1)
  if p == 0 then
    if q < 0 then return nil end
  else
    local t = q / p
    if p < 0 then t0 = math.max(t0, t) else t1 = math.min(t1, t) end
    if t0 > t1 then return nil end
  end
  return t0, t1
end
local function seg_rect_dist(a, b, r)
  -- 0 when the segment meets the rectangle, else the least distance of
  -- the segment's ends and the rectangle's corners to the other.
  local ax, ay = a[1], a[2]
  local dx, dy = b[1] - ax, b[2] - ay
  local t0, t1 = clip(-dx, ax - r[1], 0, 1)
  if t0 then t0, t1 = clip(dx, r[3] - ax, t0, t1) end
  if t0 then t0, t1 = clip(-dy, ay - r[2], t0, t1) end
  if t0 then t0 = clip(dy, r[4] - ay, t0, t1) end
  if t0 then return 0 end
  local L2 = dx * dx + dy * dy
  local function sp(x, y)
    local t = L2 > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / L2)) or 0
    local px, py = ax + t * dx, ay + t * dy
    return math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
  end
  return math.min(rect_dist(ax, ay, r), rect_dist(b[1], b[2], r),
    sp(r[1], r[2]), sp(r[3], r[2]), sp(r[3], r[4]), sp(r[1], r[4]))
end
-- How far a polygon's box lies from rect r: no point of it lies nearer.
local function box_dist(P, r)
  local b = P.box
  if not b then
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, q in ipairs(P) do
      x0, y0, x1, y1 = math.min(x0, q[1]), math.min(y0, q[2]), math.max(x1, q[1]), math.max(y1, q[2])
    end
    b = { x0, y0, x1, y1 }
    P.box = b
  end
  local dx = math.max(r[1] - b[3], 0, b[1] - r[3])
  local dy = math.max(r[2] - b[4], 0, b[2] - r[4])
  return math.sqrt(dx * dx + dy * dy)
end
local function in_poly(x, y, P)
  local inside, j = false, #P
  for i = 1, #P do
    local a, b = P[i], P[j]
    if (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then inside = not inside end
    j = i
  end
  return inside
end

-- Whether paint `sh` (fill, or a stroke of width w) comes within g of
-- rect r: the rect grown by g with rounded corners, as the field measures
-- its gap. A fill that holds the rect's middle inside it overlaps however
-- far its outline lies.
local function overlaps(sh, fill, w, r, g)
  local lim = g + (fill and 0 or w / 2)
  local mx, my = (r[1] + r[3]) / 2, (r[2] + r[4]) / 2
  for _, d in ipairs(sh.discs) do
    local near = rect_dist(d[1], d[2], r)
    if fill then
      if near < d[3] + lim then return true end
    else
      -- A ring: within lim of its circle, from inside or out.
      local far = 0
      for _, q in ipairs({ { r[1], r[2] }, { r[3], r[2] }, { r[3], r[4] }, { r[1], r[4] } }) do
        far = math.max(far, math.sqrt((q[1] - d[1]) ^ 2 + (q[2] - d[2]) ^ 2))
      end
      if near < d[3] + lim and far > d[3] - lim then return true end
    end
  end
  for _, P in ipairs(sh.polys) do
    local n = #P
    -- A polygon whose box lies farther than lim from r comes nowhere
    -- near it, nor holds its middle (a negative lim, for a gap of 0, is
    -- as far as 0: a box that touches r may still enclose its middle).
    if n > 0 and box_dist(P, r) > math.max(lim, 0) + 1e-9 then goto next end
    if fill and n >= 3 and in_poly(mx, my, P) then return true end
    for i = 1, n - 1 do
      if seg_rect_dist(P[i], P[i + 1], r) < lim then return true end
    end
    if fill and n >= 3 and seg_rect_dist(P[n], P[1], r) < lim then return true end
    if n == 1 and rect_dist(P[1][1], P[1][2], r) < lim then return true end
    ::next::
  end
  return false
end

-- Paint a page, recording the pattern's paint, and list what comes within
-- the field's gap (less a hair) of its protected areas (pt.pattern.avoid).
function M.overlaps(spec)
  local rec, kind = {}, nil
  local fill, stroke, part = Paint.fill, Paint.stroke, Progression.part
  Paint.fill = function(self, cmds, rgb, op, o)
    if self.group and self.group.tag == "pattern" and KINDS[kind] then
      rec[#rec + 1] = { kind = kind, sh = shapes(o and o.many and cmds or { cmds }), fill = true, cmds = cmds, o = o }
    end
    return fill(self, cmds, rgb, op, o)
  end
  Paint.stroke = function(self, cmds, rgb, w, op, o)
    if self.group and self.group.tag == "pattern" and KINDS[kind] then
      rec[#rec + 1] = { kind = kind, sh = shapes(o and o.many and cmds or { cmds }), w = w or 0 }
    end
    return stroke(self, cmds, rgb, w, op, o)
  end
  Progression.part = function(pt, k, a, b, d, fn, ...)
    return part(pt, k, a, b, d, function()
      local u = kind
      kind = k
      local ok, r = pcall(fn)
      kind = u
      if not ok then error(r, 0) end
      return r
    end, ...)
  end
  Paint.reset_resources()
  local ok, pt = pcall(Compose.page, spec)
  Paint.fill, Paint.stroke, Progression.part = fill, stroke, part
  if not ok then error(pt, 0) end
  local out = {}
  local info = pt.pattern
  if not info or not info.avoid then return pt, out end
  local g = (info.gap or 0) - 1e-6
  for _, a in ipairs(info.avoid) do
    for _, q in ipairs(rec) do
      if overlaps(q.sh, q.fill, q.w or 0, a, g) then out[#out + 1] = { kind = q.kind, rect = a, paint = q } end
    end
  end
  return pt, out
end
-- The sweep. For each pattern and each form it paints (a cell; a plate
-- between cells; a piece of ground under ground=cells; the ground's panel
-- under ground=panel; celtic_knot's field panel; each hero), the page is painted
-- once to find a kept example of the form, then again with a reservation
-- of 8 x 8 pt at its middle: nothing painted may then overlap the
-- reservation (or the text, the lines or other reservations) by the gap.
-- Over M.PLAN's pages and scales (1, 2 and 4), edge=cell and dissolve,
-- the four layouts and both backdrops. Returns cells { form, pattern,
-- where, found, overlaps, unfit }, failures.
-- Two pages: the usual 360 x 270 pt, and the same page at twice its size,
-- where a scale-4 field has room for whole stars round a plate. The plan
-- is the pages and scales swept, { page, scale }: by default each page at
-- each scale.
M.PLAN = { { 1, 1 }, { 1, 2 }, { 1, 4 }, { 2, 1 }, { 2, 2 }, { 2, 4 } }
local function lines(f)
  local out = {}
  for k = 0, 9 do out[#out + 1] = { x0 = 120 * f, x1 = (330 - (k % 3) * 40) * f, y0 = (210 - k * 17) * f, y1 = (220 - k * 17) * f } end
  return out
end
M.EDGES = { "cell", "dissolve" }
M.LAYOUTS = { "left", "right", "centered", "surround" }
M.BACKDROPS = { "light", "dark" }

local function centroid(cmds)
  local sh = shapes(cmds)
  local x, y, n = 0, 0, 0
  for _, P in ipairs(sh.polys) do for _, q in ipairs(P) do x, y, n = x + q[1], y + q[2], n + 1 end end
  for _, d in ipairs(sh.discs) do x, y, n = x + d[1], y + d[2], n + 1 end
  if n == 0 then return nil end
  return x / n, y / n
end

-- The forms pattern p paints, each with its settings and a finder that
-- picks a point inside a kept example from a page's pattern info.
local function forms(p, f)
  local out = {}
  local function on_page(c) return c.x > 8 and c.x < 360 * f - 8 and c.y > 8 and c.y < 270 * f - 8 end
  local function a_cell(info)
    local best, bd
    for _, k in ipairs(info.kept) do
      local c = k.cell
      if on_page(c) then
        local d = (c.x - 60 * f) ^ 2 + (c.y - 135 * f) ^ 2
        if not bd or d < bd then best, bd = c, d end
      end
    end
    if best then return best.x, best.y end
  end
  out[#out + 1] = { form = "cell", setup = "", find = a_cell }
  local has_plates = p.name == "khatam" or p.name == "hexagram_lattice"
  if has_plates then
    out[#out + 1] = { form = "plate between cells", setup = "", find = function(info)
      local at = {}
      for _, k in ipairs(info.kept) do at[Pattern.cell_key(k.cell)] = true end
      local best, bd
      for _, k in ipairs(info.kept) do
        for _, pl in ipairs(k.cell.plates or {}) do
          local all = pl.between ~= nil
          for _, q in ipairs(pl.between or {}) do if not at[Pattern.cell_key({ x = q[1], y = q[2] })] then all = false end end
          if all then
            local x, y = centroid(pl[1])
            if x and x > 8 and x < 360 * f - 8 and y > 8 and y < 270 * f - 8 then
              local d = (x - 60 * f) ^ 2 + (y - 135 * f) ^ 2
              if not bd or d < bd then best, bd = { x, y }, d end
            end
          end
        end
      end
      if best then return best[1], best[2] end
    end }
  end
  local ground = false
  for _, r in ipairs(p.roles) do if r == "ground" then ground = p.ground ~= nil end end
  if ground then
    -- A point of the cell's piece of ground, off toward one of its
    -- corners, where the cell's own outline need not reach.
    out[#out + 1] = { form = "ground piece", setup = ", ground=cells", find = function(info)
      for _, k in ipairs(info.kept) do
        local c = k.cell
        local under = c.under or (c.tile and { { "m", c.tile[1][1], c.tile[1][2] } })
        if on_page(c) and under and c.x < 110 * f then
          local sh = shapes(under)
          local P = sh.polys[1]
          if P and P[1] then return c.x + 0.7 * (P[1][1] - c.x), c.y + 0.7 * (P[1][2] - c.y) end
        end
      end
    end }
    out[#out + 1] = { form = "ground panel", setup = ", ground=panel", find = a_cell }
  end
  if p.field_panel then out[#out + 1] = { form = "field panel", setup = ", ends=closed", find = a_cell } end
  -- The heroes, each on one pattern (the hero is placed and painted the
  -- same whatever the pattern): a reservation at the hero's middle.
  if p.name == "stars_8_4" then
    for _, h in ipairs(require("flora.pattern_hero").names()) do
      if h ~= "none" then
        out[#out + 1] = { form = "hero " .. h, setup = ", hero=" .. h, find = function(info)
          if info.hero then return info.hero[1], info.hero[2] end
        end }
      end
    end
  end
  return out
end

-- opts may narrow the sweep: plan, edges, layouts, backdrops (lists,
-- else M's), and heroes = false to leave the heroes out.
function M.sweep(filter, opts)
  opts = opts or {}
  local cells, failures = {}, {}
  for _, p in ipairs(Patterns.list) do
   for _, ps in ipairs(opts.plan or M.PLAN) do
    local pf, scale = ps[1], ps[2]
    for _, f in ipairs(forms(p, pf)) do
      if (not filter or filter(p.name, f.form)) and not (opts.heroes == false and f.form:find("^hero")) then
        do
          for _, edge in ipairs(opts.edges or M.EDGES) do
            for _, layout in ipairs(opts.layouts or M.LAYOUTS) do
              for _, bd in ipairs(opts.backdrops or M.BACKDROPS) do
                local function spec(reserve)
                  local sp = { width = 360 * pf, height = 270 * pf, text = { x0 = 120 * pf, y0 = 40 * pf, x1 = 330 * pf, y1 = 230 * pf },
                    seed = 7, layout = layout, lines = layout == "surround" and lines(pf) or nil, reserve = reserve }
                  Settings.to_spec(Settings.parse("pattern=" .. p.name .. ", colourway=tsuki-mi, edge=" .. edge .. ", scale=" .. scale
                    .. ", backdrop=" .. bd .. f.setup), sp)
                  -- Density 10 (after the settings, which set the mix):
                  -- the field runs right up to its gap.
                  sp.mix = { density = 10 }
                  return sp
                end
                local where = string.format("%s %s page=x%d scale=%s edge=%s %s %s", p.name, f.form, pf, scale, edge, layout, bd)
                local pt0 = M.overlaps(spec(nil))
                local x, y = f.find(pt0.pattern or { kept = {} })
                local c = { form = f.form, pattern = p.name, where = where, overlaps = 0, found = x ~= nil }
                if x then
                  -- 8 pt square at the cells' size this sweep was measured
                  -- at (the pattern's own times the plan's scale), in step
                  -- with the cells as the field makes them larger or
                  -- smaller.
                  local size = pt0.pattern and pt0.pattern.size
                  local h = 4 * (size and size / (p.scale * scale) or 1)
                  local pt1, o = M.overlaps(spec({ { x - h, y - h, x + h, y + h } }))
                  c.overlaps = #o
                  c.unfit = (pt0.pattern and pt0.pattern.unfit or 0) + (pt1.pattern and pt1.pattern.unfit or 0)
                  if c.unfit > 0 then failures[#failures + 1] = where .. ": kept cells left out at painting: " .. c.unfit end
                  if #o > 0 then
                    local kinds = {}
                    for _, q in ipairs(o) do kinds[q.kind] = (kinds[q.kind] or 0) + 1 end
                    local list = {}
                    for k, n in pairs(kinds) do list[#list + 1] = k .. " " .. n end
                    table.sort(list)
                    failures[#failures + 1] = string.format("%s at %.1f,%.1f: protect: %s", where, x, y, table.concat(list, ", "))
                  end
                end
                cells[#cells + 1] = c
              end
            end
          end
        end
      end
    end
   end
  end
  return cells, failures
end

M.shape_overlaps = overlaps
return M
