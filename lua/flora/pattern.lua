-- A page filled with a geometric pattern (patterns.lua) in place of flora.
-- The pattern is a field of cells laid over the page; the layout says
-- where the field may be, as it says where flora grows, and each cell is
-- kept, faded or dropped by its distance from the text:
--
--   density  how full: how close to the text the field comes, and how
--            sharply it thins there (mix.density, 0 to 10)
--   edge     how the field meets the text: dissolve (cells fall away,
--            more of them the nearer the text), cell (whole cells to a
--            hard edge), fade (cells pale into the paper), border (whole
--            cells and a ruled frame round the text)
--   outer    how it meets the paper's edge: bleed (it runs off the page)
--            or margin (whole cells only, inside a small margin)
--   scale    the cell size, as a factor of the pattern's own
--
-- Fading mixes each colour with the paper rather than painting it
-- translucent, so no cell needs a transparency group of its own.
-- While a page grows (progression.lua) each cell appears by its distance
-- from the page's outer edge: its construction lines first, then the
-- cell painted over them. A cell with a compass point draws its lines as
-- a compass turns about it, and is painted once the turn is done. The
-- lines are painted on a page that does not grow too, under the bands,
-- so its last frame and the page are the same.

local Rng = require("flora.rng")
local Paint = require("flora.paint")
local Color = require("flora.color")
local Mix = require("flora.mix")
local Patterns = require("flora.patterns")
local Progression = require("flora.progression")

local M = {}

M.edges = { dissolve = true, cell = true, fade = true, border = true }
M.outers = { bleed = true, margin = true }

-- Distances in pt.
local GAP, BORDER_GAP, OUTER_MARGIN = 6, 12, 4

local function rect_dist(x, y, r)
  local dx = math.max(r[1] - x, 0, x - r[3])
  local dy = math.max(r[2] - y, 0, y - r[4])
  return math.sqrt(dx * dx + dy * dy)
end

local function seg_point(px, py, a, b)
  local dx, dy = b[1] - a[1], b[2] - a[2]
  local l2 = dx * dx + dy * dy
  local t = l2 > 0 and math.max(0, math.min(1, ((px - a[1]) * dx + (py - a[2]) * dy) / l2)) or 0
  local x, y = a[1] + dx * t - px, a[2] + dy * t - py
  return math.sqrt(x * x + y * y)
end

-- Whether segment a-b meets rectangle r (Liang-Barsky).
local function seg_hits_rect(a, b, r)
  local t0, t1 = 0, 1
  local dx, dy = b[1] - a[1], b[2] - a[2]
  for _, e in ipairs({ { -dx, a[1] - r[1] }, { dx, r[3] - a[1] }, { -dy, a[2] - r[2] }, { dy, r[4] - a[2] } }) do
    local p, q = e[1], e[2]
    if p == 0 then
      if q < 0 then return false end
    else
      local t = q / p
      if p < 0 then t0 = math.max(t0, t) else t1 = math.min(t1, t) end
      if t0 > t1 then return false end
    end
  end
  return true
end

local function in_poly(x, y, P)
  local inside, j = false, #P
  for i = 1, #P do
    local a, b = P[i], P[j]
    if (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then
      inside = not inside
    end
    j = i
  end
  return inside
end

-- How far cell `c`'s outline (its polygon `verts`, or its `circle`) lies
-- from rectangle r: 0 when they meet or one holds the other. Every edge
-- is measured, not just the corners, so a large cell whose corners clear
-- a line of text cannot have an edge across it.
function M.clearance(c, r)
  if c.circle then
    return math.max(0, rect_dist(c.circle[1], c.circle[2], r) - c.circle[3])
  end
  local P = c.verts
  for _, q in ipairs({ { r[1], r[2] }, { r[3], r[2] }, { r[3], r[4] }, { r[1], r[4] } }) do
    if in_poly(q[1], q[2], P) then return 0 end
  end
  local d, j = math.huge, #P
  for i = 1, #P do
    local a, b = P[j], P[i]
    if seg_hits_rect(a, b, r) then return 0 end
    d = math.min(d, rect_dist(a[1], a[2], r), rect_dist(b[1], b[2], r),
      seg_point(r[1], r[2], a, b), seg_point(r[3], r[2], a, b),
      seg_point(r[3], r[4], a, b), seg_point(r[1], r[4], a, b))
    j = i
  end
  return d
end

-- Whether cell `c` lies wholly inside rectangle r, shrunk by m.
local function within(c, r, m)
  if c.circle then
    local x, y, R = c.circle[1], c.circle[2], c.circle[3] + m
    return x - R >= r[1] and x + R <= r[3] and y - R >= r[2] and y + R <= r[4]
  end
  for _, q in ipairs(c.verts) do
    if q[1] - m < r[1] or q[1] + m > r[3] or q[2] - m < r[2] or q[2] + m > r[4] then return false end
  end
  return true
end

-- How long a cell's construction lines take to draw, as growth time.
local LINES = 0.07

-- A wedge about compass point w that covers all of cell c's lines: its
-- outline, half a band and its pad beyond.
local function sweep_reach(c, w, width)
  local r = 0
  for _, q in ipairs(c.verts) do r = math.max(r, math.sqrt((q[1] - w[1]) ^ 2 + (q[2] - w[2]) ^ 2)) end
  if c.circle then
    r = math.max(r, math.sqrt((c.circle[1] - w[1]) ^ 2 + (c.circle[2] - w[2]) ^ 2) + c.circle[3])
  end
  return r + width + (c.pad or 0) + 2
end

local function smooth(t)
  t = math.max(0, math.min(1, t))
  return t * t * (3 - 2 * t)
end

-- Which sides of the text the field takes for `layout`: "left", "right",
-- both, or nil for the whole page. A split layout takes the outer margin:
-- right on odd pages, left on even ones (frames.lua).
local function sides(spec)
  local layout = spec.layout or "left"
  if layout == "left" then return { left = true } end
  if layout == "right" then return { right = true } end
  if layout == "centered" then return { left = true, right = true } end
  if layout == "split" then
    return ((spec.page or 1) % 2 == 1) and { right = true } or { left = true }
  end
  return nil
end

-- What the field keeps clear of: the text block for a margin layout or
-- a border, the measured lines for a whole-page one, and every
-- reservation.
local function avoid(spec, side, edge)
  local out = {}
  local t = spec.text
  -- A border frames the text block, so the field keeps clear of all of it.
  if side or edge == "border" or not spec.lines or #spec.lines == 0 then out[#out + 1] = { t.x0, t.y0, t.x1, t.y1 } end
  for _, l in ipairs(spec.lines or {}) do out[#out + 1] = { l.x0, l.y0, l.x1, l.y1 } end
  for _, r in ipairs(spec.reserve or {}) do out[#out + 1] = { r[1], r[2], r[3], r[4] } end
  return out
end

-- The page's colours, one ink per role from the palette (as flora's
-- parts are painted): the bands take the leaves' ink, the two fills the
-- blooms' and the sprays'. "look" keeps flora's own navy, gold and sky.
-- An ink group gives one of its inks for the whole page, so a flat field
-- does not turn patchy. Gold stays gold.
local function base_inks(rng)
  local pal, tp = Paint.palette, require("flora.tune").color.palette
  local function role(part, L, fallback)
    local ink = Color.ink_for(rng:fork("ink " .. part), tp[part])
    if not ink then return fallback end
    return Color.ink_rgb(ink, L, 1)
  end
  return {
    band = role("leaves", 0.22, pal.ink),
    fill1 = role("blooms", 0.74, pal.gold),
    fill2 = role("sprays", 0.66, pal.sky),
  }
end

-- A cell's colours, mixed toward the paper by 1 - a.
local function inks(base, a)
  local pal = Paint.palette
  local function f(c) return a >= 1 and c or Paint.mix(pal.paper, c, a) end
  return {
    band = f(base.band), core = f(pal.paper), accent = f(pal.gold),
    line = f(Paint.mix(base.band, pal.paper, 0.45)),
    fill = { f(base.fill1), f(base.fill2) },
  }
end

-- The weights pattern={...} gave, as a table (a bare name weighs 1).
local function weights(v)
  if type(v) == "string" then return { [v] = 1 } end
  return v or {}
end

-- Lay out and paint the page's pattern onto `pt`. Returns false when the
-- pattern weights leave nothing to pick, so the caller grows flora.
function M.paint(spec, pt)
  local rng = Rng.new(spec.seed or 1)
  local p = Patterns.pick(rng:fork("choose pattern"), weights(spec.pattern))
  if not p then return false end
  local W, H, text = spec.width, spec.height, spec.text
  local side = sides(spec)
  local edge = spec.pattern_edge or "dissolve"
  local outer = spec.pattern_outer or "bleed"
  local size = p.scale * (spec.pattern_scale or 1)
  local width = (p.width or size / 6) * (spec.pattern_scale or 1)
  local dens = Mix.weight(spec.mix, "density")
  local gap = edge == "border" and BORDER_GAP or GAP
  -- The room the field has beside the text sets how far it takes to thin.
  local room = side and math.max(side.left and text.x0 or 0, side.right and W - text.x1 or 0) or 120
  local ramp = math.max(size, 0.6 * math.min(room, 120)) / math.max(dens, 1e-6)
  local keep_rects = avoid(spec, side, edge)
  -- The page's top as painted: below a top inset, and below the header
  -- clip compose.lua set (header=body), so margin cells stay whole.
  local inset = spec.top_inset or require("flora.tune").gesture.top_inset or 0
  local top = math.min(H, inset > 0 and H - inset or H, pt.header_clip or H)
  local base = base_inks(rng:fork("pattern inks"))

  local cells = p.cells({ x0 = 0, y0 = 0, x1 = W, y1 = H, size = size, rng = rng:fork("cells") })
  local fall = rng:fork("dissolve")
  local stagger = rng:fork("growth")
  local kept, offered = {}, 0
  for _, c in ipairs(cells) do
    local r, jitter = fall:next(), stagger:next()
    local in_side = not side or (side.left and c.x < text.x0) or (side.right and c.x > text.x1)
    -- Paint reaches half a band and the cell's own pad beyond its outline.
    local reach = width / 2 + (c.pad or 0)
    local page = { 0, 0, W, top }
    local placed = in_side
    if outer == "margin" then
      placed = placed and within(c, page, OUTER_MARGIN + reach)
    else
      placed = placed and M.clearance(c, page) <= reach
    end
    if placed then
      offered = offered + 1
      local d = math.huge
      for _, rc in ipairs(keep_rects) do d = math.min(d, M.clearance(c, rc) - reach) end
      local a = 0
      if dens > 0 and d >= gap then
        local t = (d - gap) / ramp
        if edge == "dissolve" then a = r < smooth(t) and 1 or 0
        elseif edge == "fade" then a = smooth(t); if a < 0.04 then a = 0 end
        else a = t >= 0.35 and 1 or 0
        end
      end
      if a > 0 then
        kept[#kept + 1] = { cell = c, a = a, jitter = jitter }
      end
    end
  end

  -- Growth starts at the page's outer edge, away from the text.
  local function root(c)
    if side and side.left and c.x < text.x0 then return c.x end
    if side and side.right and c.x > text.x1 then return W - c.x end
    return math.min(c.x, c.y, W - c.x, H - c.y)
  end
  local far = 1e-6
  for _, k in ipairs(kept) do far = math.max(far, root(k.cell)) end

  local grow = spec.grow and spec.grow < 1 and math.max(0, spec.grow) or nil
  pt:begin_group("pattern")
  for _, k in ipairs(kept) do
    local c, ink = k.cell, inks(base, k.a)
    ink.width = width
    -- The construction lines lie under the finished cell's bands, so a
    -- page painted at once and the last frame of its growth are the same.
    local birth = 0.78 * root(c) / far + 0.1 * k.jitter
    -- A cell with a compass point (c.sweep) draws its lines as the
    -- compass turns, and is painted once the turn is done.
    local painted = birth + (c.sweep and LINES or 0.05)
    if grow then
      -- A "watch it grow" frame (spec.grow, tools/grow-frame.sh) shows a
      -- cell's lines once it is born, swept as far as they have grown, and
      -- the cell halfway through its painting, on the times the
      -- progression parts below use.
      local f = (grow - birth) / LINES
      if c.sweep and f > 0 and f < 1 then
        local w = c.sweep
        pt:clip_begin(Progression.wedge(w[1], w[2], sweep_reach(c, w, width), w[3] or 0, f, w[4]))
        c.construct(pt, c, ink)
        pt:clip_end()
      elseif grow >= birth and (f >= 1 or not c.sweep) then
        c.construct(pt, c, ink)
      end
      if grow >= painted + 0.04 then c.paint(pt, c, ink) end
    else
      Progression.part(pt, "pattern_line", { c.x, c.y }, birth, LINES,
        function() c.construct(pt, c, ink) end, nil, { no_area = true, sweep = c.sweep })
      Progression.part(pt, "pattern", { c.x, c.y }, painted, 0.08,
        function() c.paint(pt, c, ink) end)
    end
  end
  if edge == "border" and (not grow or grow >= 0.1) then
    local ink = inks(base, 1)
    local o = gap / 2
    local frame = { { "m", text.x0 - o, text.y0 - o }, { "l", text.x1 + o, text.y0 - o },
      { "l", text.x1 + o, text.y1 + o }, { "l", text.x0 - o, text.y1 + o }, { "z" } }
    Progression.part(pt, "pattern_border", { text.x0, text.y0 }, 0, 0.2, function()
      pt:stroke(frame, ink.band, width * 1.2, 1)
      pt:stroke(frame, ink.accent, width * 0.45, 1)
    end)
  end
  pt:end_group()
  pt.coverage = offered > 0 and #kept / offered or 0
  pt.pattern = { name = p.name, cells = #kept, offered = offered, kept = kept, avoid = keep_rects, reach = width / 2, gap = gap }
  return true
end

return M
