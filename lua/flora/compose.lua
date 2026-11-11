-- Composes one page of flora, in the order the plant grows: the stems
-- (layout.lua, plant.lua), then leaves at their nodes, blooms and sprays
-- on branches grown to the largest holes, and small details (grow.lua),
-- then ornaments. Painting runs back to front in fixed layers.

local G = require("flora.geom")
local Rng = require("flora.rng")
local Paint = require("flora.paint")
local Layout = require("flora.layout")
local Fill = require("flora.fill")
local Grow = require("flora.grow")
local F = require("flora.flower")
local L = require("flora.leaf")
local S = require("flora.sprig")
local O = require("flora.ornament")
local Orn = require("flora.ornaments")
local Title = require("flora.orn_title")
local Tune = require("flora.tune")
local Plant = require("flora.plant")
local Brush = require("flora.brush")
local Frames = require("flora.frames")
local Mix = require("flora.mix")
local Visitor = require("flora.visitor")
local Clock = require("flora.clock")
local Progression = require("flora.progression")
local Color = require("flora.color")
local pal = Paint.palette

local C = {}
local pi = math.pi
local HERO_TOP = 8
-- The running-head mark: its full size, and its clearances from the paper's
-- edge, from the running head or a clip, and from ink. The smallest size
-- worth drawing is gesture.mark_min (tune.lua). A plant's foot run less than
-- MARK_STEM pt above or below the rule runs beside it: there the stem
-- underlines the head, so the rule stops MARK_STEM_GAP pt short of it, and is
-- left out when less than MARK_RULE_MIN pt of it would remain.
local MARK_SIZE, MARK_EDGE, MARK_HEAD, MARK_INK = 26, 6, 2, 2
local MARK_STEM, MARK_STEM_GAP, MARK_RULE_MIN = 26, 6, 52
-- min is the default minimum; header_mark reads the tuned one.
C.MARK = { size = MARK_SIZE, min = Tune.gesture.mark_min, edge = MARK_EDGE, head = MARK_HEAD,
  ink = MARK_INK, stem = MARK_STEM, stem_gap = MARK_STEM_GAP, rule_min = MARK_RULE_MIN }

-- The mark's lowest ceiling, the span of its rule, x0 to x1, and the
-- mark's centre x.
local function mark_bounds(spec, inset, clip_y)
  local H = spec.height
  local hx = spec.text.x0 - 6
  local x0, x1 = hx - MARK_SIZE / 2, spec.text.x1
  local ceil
  if spec.running_head == nil then
    ceil = math.min(H, spec.header_y - 3 + MARK_SIZE / 2)
  elseif spec.running_head then
    ceil = math.min(H - MARK_EDGE, spec.header_y - MARK_HEAD)
  else
    ceil = H - MARK_EDGE
  end
  if inset and inset > 0 then ceil = math.min(ceil, H - inset - MARK_HEAD) end
  if clip_y then ceil = math.min(ceil, clip_y - MARK_HEAD) end
  if spec.header == "body" and spec.body_top then ceil = math.min(ceil, spec.body_top - MARK_HEAD) end
  return ceil, x0, x1, hx
end

-- How far any header kind may paint past its box, as a share of its size
-- (ornaments.lua: reach). Placement keeps this much clear of obstacles
-- whatever the kind, so a mark's place does not depend on its kind: an
-- adapter that draws another kind over a shared drawing places it alike.
local function mark_reach()
  local r = 0
  for _, k in ipairs(Orn.of("header")) do r = math.max(r, k.reach or 0) end
  return r
end

-- What a plant spec's mark must keep clear of besides its band: the
-- reserved boxes, which clip the page (C.frames), and the forbidden corner
-- of a frame's notch clip (clip_x1, clip_y1), as {x0, y0, x1, y1} in the
-- frame's coordinates.
local function mark_obstacles(spec)
  local out = {}
  for _, r in ipairs(spec.reserve or {}) do out[#out + 1] = { r[1], r[2], r[3], r[4] } end
  if spec.clip_x1 then
    out[#out + 1] = { spec.clip_x1, 0, spec.width, spec.clip_y1 or spec.height }
  end
  return out
end

-- The mark's size and box top inside its band [lo, ceil], clear of the
-- obstacles. A mark of size s whose box top is t paints over its box
-- widened by e = reach * s + MARK_HEAD on every side, centred on hx:
--   x in [hx - s/2 - e, hx + s/2 + e], y in [t - s - e, t + e].
-- That must touch no obstacle, wherever the obstacle lies (beside the mark,
-- under the band's floor, over its ceiling), and stay MARK_HEAD inside the
-- paper's left edge; the box itself stays inside the band. The largest such
-- mark, up to MARK_SIZE, is taken, at the highest box top it fits at; nil
-- when none of at least `min` fits. With no obstacle in the way this is the
-- band itself: min(MARK_SIZE, ceil - lo), at ceil.
--
-- A smaller mark fits wherever a larger one does (the same centre, its
-- painted extent inside the larger one's), so the sizes that fit run from
-- `min` up to a largest one. At that size some limit is just met: the band
-- (s = ceil - lo), the paper's edge, an obstacle's side (beyond that size
-- it starts to overlap the mark sideways), or a stretch between two
-- vertical limits (the band's floor or an obstacle's top below, the
-- ceiling or an obstacle's bottom above) closing to one box top. Those
-- sizes are tried from the largest down; the first that fits is it.
local EXACT = 1e-9

local function clear_place(ceil, lo, hx, min, reach, obstacles)
  local g = MARK_HEAD
  local cap = math.min(MARK_SIZE, ceil - lo)
  -- The paper's left edge.
  if hx - (0.5 + reach) * cap < g then cap = (hx - g) / (0.5 + reach) end
  if cap < min then return nil end
  -- The obstacles a mark of size s may meet: those that overlap it sideways.
  local function across(o, s)
    local half = (0.5 + reach) * s + g
    return o[3] > hx - half + EXACT and o[1] < hx + half - EXACT
  end
  -- The highest box top for size s, or nil: the ceiling, or just under an
  -- obstacle, whichever is highest and clear.
  local function top_for(s)
    local e = reach * s + g
    local tops = { ceil }
    for _, o in ipairs(obstacles) do
      if across(o, s) and o[2] - e < ceil then tops[#tops + 1] = o[2] - e end
    end
    table.sort(tops, function(a, b) return a > b end)
    for _, t in ipairs(tops) do
      if t - s < lo - EXACT then return nil end
      local clear = true
      for _, o in ipairs(obstacles) do
        if across(o, s) and o[4] > t - s - e + EXACT and o[2] < t + e - EXACT then clear = false; break end
      end
      if clear then return t end
    end
  end
  local t = top_for(cap)
  if t then return cap, t end
  -- The sizes at which a limit is just met (see above).
  local r1, r2 = 1 + reach, 1 + 2 * reach
  local sizes = {}
  local function try(s) if s >= min and s < cap then sizes[#sizes + 1] = s end end
  for _, o in ipairs(obstacles) do
    try((hx - g - o[3]) / (0.5 + reach))
    try((o[1] - hx - g) / (0.5 + reach))
    try((o[2] - g - lo) / r1)
    try((ceil - o[4] - g) / r1)
    for _, p in ipairs(obstacles) do try((p[2] - o[4] - 2 * g) / r2) end
  end
  try(min)
  table.sort(sizes, function(a, b) return a > b end)
  for _, s in ipairs(sizes) do
    t = top_for(s)
    if t then return s, t end
  end
  return nil
end

-- C.header_mark once its bounds, the smallest mark `min`, the mark's reach
-- and its obstacles are known.
local function mark_at(lines, stem_runs, ceil, x0, x1, hx, min, reach, obstacles)
  local floor = 0
  for _, l in ipairs(lines or {}) do
    if l.x1 > x0 and l.x0 < x1 and l.y0 < ceil then
      if l.y1 > ceil then return nil end
      floor = math.max(floor, l.y1)
    end
  end
  local band = ceil - (floor + MARK_INK)
  if band < min then return nil, band end
  local size, top = clear_place(ceil, floor + MARK_INK, hx, min, reach or 0, obstacles or {})
  if not size then return nil, band end
  local y = top - size / 2
  -- The rule runs right from the mark until a foot run beside it begins,
  -- or an obstacle across its line; one that covers its start leaves it out.
  local rx0, rx1 = hx + 4 * size / MARK_SIZE, x1
  local stem
  for _, r in ipairs(stem_runs or {}) do
    if r[3] > rx0 and r[1] < x1 then
      local d = math.max(r[2] - y, y - r[4], 0)
      if not stem or d < stem then stem = d end
      if d < MARK_STEM then rx1 = math.min(rx1, r[1] - MARK_STEM_GAP) end
    end
  end
  for _, o in ipairs(obstacles or {}) do
    if o[2] < y + MARK_HEAD and o[4] > y - MARK_HEAD and o[3] > rx0 and o[1] < rx1 then
      rx1 = o[1] <= rx0 and rx0 or math.min(rx1, o[1] - MARK_HEAD)
    end
  end
  local rule = rx1 - rx0 >= MARK_RULE_MIN and { rx0, rx1 } or nil
  return { y = y, size = size, rule = rule, stem = stem, band = band }
end

-- Where the running-head mark and its rule go: at the top of the free band
-- between the lowest ceiling (paper edge, running head, page inset, header
-- clip when given, body top) and the highest measured ink under it across the
-- rule's span. A mark painted outside the header clip (C.frames holds it
-- back until the clip ends) is placed without clip_y. Returns nil and the
-- band (nil when ink crosses the ceiling) when the band cannot hold the mark
-- whole, else
-- { y = centre, size = edge length, rule = { x0, x1 } or nil when it is left
--   out, stem = vertical distance to the nearest foot run over the rule's
--   span, or nil when none overlaps it }.
-- An adapter that knows whether the page shows its running head sets
-- spec.running_head (true: keep below header_y; false: no head on this
-- page). Unset, the mark may reach as high as it always did (centre 3 pt
-- below header_y, kept on the paper), so callers that do not know keep
-- their placement.
-- spec.stem_runs ({x0, y0, x1, y1} boxes in this frame's coordinates) are
-- where the page's plants run their main stems along a foot (C.frames).
-- The mark is also kept whole clear of the page's reserved boxes and a
-- frame's notch clip (mark_obstacles): moved down its band, made smaller,
-- or left out; its rule stops short of them.
function C.header_mark(spec, inset, clip_y)
  local ceil, x0, x1, hx = mark_bounds(spec, inset, clip_y)
  return mark_at(spec.lines, spec.stem_runs, ceil, x0, x1, hx, Tune.gesture.mark_min,
    mark_reach(), mark_obstacles(spec))
end

-- The margin-mode header clip's line (gesture.header_clip) for a plant
-- spec, or nil.
local function header_clip_y(spec)
  if (Tune.gesture.header_clip or 0) > 0 and spec.frametitle and spec.header_y then
    return spec.header_y - (Tune.gesture.header_gap or 0)
  end
end

-- Where a plant spec's mark goes (C.header_mark), or nil: against the page
-- inset and, unless the mark is `held` until a margin-mode header clip
-- ends, against that clip.
local function mark_place(spec, held)
  if not spec.header_y then return nil end
  local inset = spec.top_inset or Tune.gesture.top_inset or 0
  return C.header_mark(spec, inset, not held and header_clip_y(spec) or nil)
end

-- The mark at `place` for a plant spec, as a function of a painter: its
-- rule, then an ornament of the header slot, its kind and drawing taken
-- from the plant's stream `rng`.
local function mark_painter(spec, rng, place)
  local hx, hy, r = spec.text.x0 - 6, place.y, place.size / 2
  local mark = Orn.pick(rng:fork("choose header"), "header", spec.ornaments)
  return function(pt)
    if place.rule then
      pt:stroke(G.polyline({ { place.rule[1], hy }, { place.rule[2], hy } }), pal.ink, 0.4, 0.9)
    end
    if mark then Orn.draw(mark, pt, rng:fork("header"), { hx - r, hy - r, hx + r, hy + r }) end
  end
end

-- The page's foot runs (plant.foot_run), as boxes in each frame's own
-- coordinates: the band the main stem's guide sways in, widened by half
-- the root's width. A frame without a matrix (a curved band) has no foot.
function C.stem_runs(frames, spec)
  local page = {}
  for _, f in ipairs(frames) do
    local s = f.spec
    if not s.bare and (f.map or s == spec) then
      local run = Tune._with(s ~= spec and s.tune or nil, function()
        local r = Plant.foot_run(Layout.margins(s), s.width)
        r.w = (Tune.plant.root_width or 0) / 2
        return r
      end)
      local w = run.sway + run.w
      local m = f.map or { 1, 0, 0, 1, 0, 0 }
      local xs, ys = {}, {}
      for _, q in ipairs({ { run.x0, run.y - w }, { run.x1, run.y + w } }) do
        local x, y = Frames.apply(m, q[1], q[2]); xs[#xs + 1], ys[#ys + 1] = x, y
      end
      page[#page + 1] = { math.min(xs[1], xs[2]), math.min(ys[1], ys[2]), math.max(xs[1], xs[2]), math.max(ys[1], ys[2]) }
    end
  end
  for _, f in ipairs(frames) do
    local inv = f.map and Frames.invert(f.map) or { 1, 0, 0, 1, 0, 0 }
    local own = {}
    for _, r in ipairs(page) do
      local ax, ay = Frames.apply(inv, r[1], r[2])
      local bx, by = Frames.apply(inv, r[3], r[4])
      own[#own + 1] = { math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by) }
    end
    f.spec.stem_runs = own
  end
end

-- Progress through a page (C.page's spec.progress): a span [lo, hi] of the
-- whole page maps its own 0..1 into it. A value is sent once it passes the
-- last one sent by at least STEP, and 1 always is, so a page sends a
-- short, rising list ending in 1. Without a hook every call does nothing.
local STEP = 0.01
local Progress = {}
Progress.__index = Progress

local function progress(fn)
  return setmetatable({ fn = fn, lo = 0, hi = 1, sent = { last = -1 } }, Progress)
end

-- The part of this span from a to b (0..1 of it).
function Progress:part(a, b)
  local w = self.hi - self.lo
  return setmetatable({ fn = self.fn, lo = self.lo + w * a, hi = self.lo + w * b, sent = self.sent }, Progress)
end

function Progress:at(f)
  if not self.fn then return end
  local v = self.lo + (self.hi - self.lo) * f
  local s = self.sent
  if v > s.last and (v >= 1 or v >= s.last + STEP) then
    s.last = v
    self.fn(v)
  end
end

-- A plant's share of its progress: the grow to these points, then the
-- painting, item by item, each item one unit and a bloom BLOOM units; the
-- batches painted at once (stems, sprays, leaflets, the hero) count as
-- the units given.
local GROWN = { laid = 0.02, nodes = 0.06, holes = 0.16, details = 0.25 }
-- A title page's share of its progress taken by its title furniture.
local TITLE_SHARE = 0.08
local BLOOM, BATCH = 3, { stems = 4, sprays = 8, leaflets = 3, hero = 4, finish = 2 }

-- Plan and paint one plant in its frame's left margin (frames.lua), onto
-- `pt` when given, else onto a new painter, telling `prog` (Progress, when
-- given) how far it has got.
local function plant(spec, pt, prog)
  prog = prog or progress(nil)
  local rng = Rng.new(spec.seed or 1)
  local W = spec.width
  local edge = spec.edge or 16
  local g, m = Layout.region(spec)
  local mw = m.x1 - m.x0
  local top = (spec.header == "body" and spec.body_top) or spec.header_y or spec.text.y1
  local inset = spec.top_inset or Tune.gesture.top_inset or 0
  if inset > 0 then top = math.min(top, spec.height - inset) end

  local cfg = Mix.budget(Mix.cfg(Tune.compose, spec.mix), spec.budget)
  local R = G.clamp(mw * cfg.hero, cfg.hero_min or 28, cfg.hero_max or 80)
  -- With a header mode set (a presentation's narrow margin), the hero may
  -- use the whole margin up to the text block, not just the inset growing
  -- region: on a 1 cm margin that is a visible bloom, not a clipped sliver.
  local hw = math.max(1, spec.text.x0 - 2)
  if spec.header then R = math.min(R, math.max(1, (hw - 4) * 0.45)) end
  -- As in the reference, the hero's heart sits just below the running-head
  -- rule, so the bloom fills the top corner of the page up to the paper's
  -- edge (its projected top kept HERO_TOP pt inside it).
  local _, rh = F.tilt(0, 0, R, Tune.hero.tilt)
  local clip_y
  if (Tune.gesture.header_clip or 0) > 0 and spec.frametitle and spec.header_y then
    clip_y = spec.header_y - (Tune.gesture.header_gap or 0)
  end
  local hy
  if spec.header == "body" and spec.body_top then
    -- The whole bloom sits below the measured title, not across it.
    hy = math.min(spec.body_top - rh - 2 - (cfg.hero_shift or 0), spec.height - HERO_TOP - rh)
    if inset > 0 then hy = math.min(hy, spec.height - inset - rh - 2) end
  else
    hy = math.min(top - R * 0.32 - (cfg.hero_shift or 0), spec.height - HERO_TOP - rh)
    if clip_y then hy = math.min(hy, clip_y - rh - 2) end
  end
  local cx = spec.header and math.max(math.min(m.x0 + mw * 0.5, hw - R - 2), R + 2)
    or G.clamp(m.x0 + mw * 0.5, m.x0 + R * 0.75, m.x1 - R * 0.95)
  local hero = { cx, hy, R }
  -- The clearance field sees the text and the region's edges from here on.
  g:field()
  -- The hero leans back, so its petals cover a flattened oval; it is
  -- recorded as three discs across that oval, counted at 0.85 of their
  -- radius so foliage may tuck under the rim of its petals.
  do
    local _, rh = F.tilt(hero[1], hero[2], R, Tune.hero.tilt)
    g:disc(hero[1], hero[2], rh, 0.85)
    for _, sx in ipairs({ -1, 1 }) do g:disc(hero[1] + sx * R * 0.45, hero[2], R * 0.55, 0.85) end
  end

  local gest = Layout.gesture(rng:fork("gesture"), m, hero)
  local dens = Mix.density(gest.density, spec.mix)
  -- The cartouche's place, at the reference's size, is kept clear before
  -- the plant grows, so the stems bend around it as the reference's do.
  local ylo, span = m.y0, hero[2] - m.y0
  local py = gest.quiet[1] or ylo + span * 0.5
  local pw, ph = Layout.cartouche_size(mw)
  local strands, root = Layout.strands(rng:fork("strands"), m, hero, W, gest,
    { m.x0, py - ph / 2 - 3, m.x0 + pw + 5, py + ph / 2 + 3 })
  local excursion = not spec.frame_only and Layout.excursion(rng:fork("excursion"), spec, root)
  if excursion then
    excursion.growth_parent,excursion.growth_t=strands[1],G.nearest_fraction(strands[1].pts,excursion.pts[1])
    strands[#strands + 1] = excursion
  end
  -- A bare frame (a curved one: frames.lua) has no outer corner, so no
  -- corner runner, star panel or foot compass.
  local runners = spec.bare and {} or Layout.runners(rng:fork("runners"), m, strands[1].pts[1], W, edge, g)
  for _,runner in ipairs(runners) do runner.growth_parent,runner.growth_t=strands[1],0 end
  Plant.fork(strands[1], 0.005, 0.8)
  local stems = {}
  local stem_batch, spray_batch = S.batch(), S.batch()
  for _, list in ipairs({ strands, runners }) do
    for _, s in ipairs(list) do
      g:reserve_line(s.pts, 2, 4)
      stems[#stems + 1] = s
    end
  end

  local orn, panel = {}, nil
  -- Each slot's kind is drawn by weight (ornaments.lua) from a stream of
  -- its own; a slot whose kinds all weigh 0 is left empty.
  local cartouche = not spec.bare and Orn.pick(rng:fork("choose cartouche"), "cartouche", spec.ornaments)
  if cartouche then
    -- The star cartouche sits in a quiet stretch, where the stems hug the
    -- outer edge and bend around it.
    -- The panel sits against the outer edge, so its own rectangle (with a
    -- small pad) is tested rather than a disk around its centre. It is
    -- tried at the reference's size first, then smaller.
    for _, k in ipairs({ 1.0, 0.82, 0.66 }) do
      local w, h = Layout.cartouche_size(mw, k)
      local cx = m.x0 + w / 2 + 2
      local fits = true
      for x = cx - w / 2 - 1, cx + w / 2 + 3, 2 do
        for y = py - h / 2 - 3, py + h / 2 + 3, 2 do
          if not g:free(x, y) then fits = false end
        end
      end
      if fits then
        g:box(cx - w / 2, py - h / 2, cx + w / 2, py + h / 2)
        local r = rng:fork("panel")
        orn[#orn + 1] = function(pt) Orn.draw(cartouche, pt, r, { cx - w / 2, py - h / 2, cx + w / 2, py + h / 2 }) end
        panel = { cx, py, w, h }
        break
      end
    end
  end
  local back, blooms, leaves, leaflet_items = {}, {}, {}, {}
  local ghost
  local ctx = {
    cfg = cfg, mix = spec.mix, progression = spec._progression, pos = (spec.grow or spec._progression) and setmetatable({}, { __mode = "k" }), mw = mw, dens = dens, ylo = ylo, span = span, strands = strands, stems = stems,
    support = spec._progression and {},
    stem_batch = stem_batch, sprays = spray_batch, blooms = blooms, back = back,
    leaves = leaves, leaflets = leaflet_items,
  }
  -- As in the reference, a large ghost bloom usually sits low in the outer
  -- margin, just above the foot, behind the stems that cross it. It is
  -- recorded at 0.8 of its radius, so leaves and sprays may overlap only
  -- its petals' rims, and it takes the hole loop's one ghost.
  ctx.counts = {}
  do
    local gr = rng:fork("ghost")
    local gw = Mix.weight(spec.mix, "ghost")
    if gw > 0 and gr:chance(0.85 * math.min(1, gw)) then
      for _ = 1, 8 do
        local r = mw * gr:range(0.23, 0.28)
        local x = m.x0 + mw * gr:range(0.35, 0.5)
        local y = m.foot + gr:range(35, 75)
        local ok = true
        for k = 0, 11 do
          local q = G.polar({ x, y }, k * pi / 6, r * 0.9)
          local in_panel = panel and math.abs(q[1] - panel[1]) < panel[3] / 2 + 2
            and math.abs(q[2] - panel[2]) < panel[4] / 2 + 2
          if not g:open_at(q[1], q[2]) or in_panel then ok = false end
        end
        if ok then
          g:disc(x, y, r, 0.8)
          local fr = gr:fork("bloom")
          back[#back + 1] = function(pt) F.bloom(pt, fr, x, y, r, { kind = "ghost", look = "ghost", width = 0.55 }) end
          if ctx.pos then ctx.pos[back[#back]] = { x, y } end
          ctx.counts.ghost = 1
          ghost = { x, y, r }
          break
        end
      end
    end
  end
  local grow_rng = rng:fork("grow")
  prog:at(GROWN.laid)
  Grow.node_leaves(g, grow_rng:fork("nodes"), strands, ctx)
  Grow.tips(g, grow_rng:fork("tips"), strands, ctx)
  -- Visitors claim their space before the holes fill (visitor.lua).
  Visitor.place(g, rng:fork("visitors"), ctx, strands)
  prog:at(GROWN.nodes)

  -- Gilt ornaments claim their space before the sprays fill in.
  -- The mark and its rule are drawn whole inside the free band, or not at all.
  -- Beside a foot run the stem is the head's underline; the rule gives way to it.
  -- Under the margin-mode header clip the mark is held back and painted after
  -- the clip ends (C.frames), so that clip does not bound it.
  local held = pt and pt.held_marks
  local place = mark_place(spec, held)
  local mark_fn
  if place then
    mark_fn = mark_painter(spec, rng, place)
    orn[#orn + 1] = mark_fn
  end
  -- A pendant knot hangs in the foot's corner on a cord from the foliage
  -- above, at the lowest place with room for it; its size and place vary
  -- with the seed.
  local pendant = Orn.pick(rng:fork("choose pendant"), "pendant", spec.ornaments)
  if pendant then
    local r = rng:fork("pendant")
    local w = G.clamp(mw * r:range(0.15, 0.19), 14, 30)
    local h = w * r:range(1.3, 1.5)
    local x = m.x0 + w / 2 + r:range(3, 10)
    for y = m.y0 + h / 2 + 1, m.y0 + 90, 3 do
      local clear = g:room(x, y) >= w * 0.3
      for _, q in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
        if not g:open_at(x + q[1] * w / 2, y + q[2] * h / 2) then clear = false end
      end
      if clear then
        g:box(x - w / 2, y - h / 2, x + w / 2, y + h / 2)
        local cord = 0
        while cord < 40 and g:free(x, y + h / 2 + cord + 2) do cord = cord + 2 end
        if cord >= 6 then g:box(x - 1, y + h / 2, x + 1, y + h / 2 + cord) else cord = 0 end
        orn[#orn + 1] = function(pt) Orn.draw(pendant, pt, r, { x - w / 2, y - h / 2, x + w / 2, y + h / 2 }, { cord = cord }) end
        break
      end
    end
  end

  -- A dotted gilt chain runs down the outer edge wherever the foliage
  -- leaves it clear, from below the hero to the foot. A gathered plant's
  -- outer edge is its bouquet's middle, where no chain belongs.
  local px = m.x0 + 2.5
  local runs, run = {}, nil
  local _, hero_rh = F.tilt(0, 0, R, Tune.hero.tilt)
  for y = hero[2] - hero_rh - 6, spec.gather and math.huge or m.y0 + 6, -2 do
    if g:free(px, y) and g:free(px - 1.5, y) and g:free(px + 1.5, y) then
      if run then run[2] = y else run = { y, y } end
    else
      if run and run[1] - run[2] >= 28 then runs[#runs + 1] = run end
      run = nil
    end
  end
  if run and run[1] - run[2] >= 28 then runs[#runs + 1] = run end
  for k, rn in ipairs(runs) do
    for y = rn[1], rn[2], -5 do g:reserve(px, y, 5) end
    local r = rng:fork("chain" .. k)
    -- A run stopped by the cartouche's top hangs a knot over it.
    local foot = panel and math.abs(px - panel[1]) < panel[3] / 2
      and rn[2] - (panel[2] + panel[4] / 2) < 8 and rn[2] > panel[2] and "knot" or nil
    orn[#orn + 1] = function(pt) O.chain(pt, r, px, rn[1], rn[2], foot) end
  end

  -- Blooms and sprays on branches to the largest holes, then details.
  Grow.holes(g, grow_rng:fork("holes"), ctx)
  prog:at(GROWN.holes)
  Grow.details(g, grow_rng:fork("details"), ctx)
  prog:at(GROWN.details)
  for _, s in ipairs(cfg.no_leaflets and {} or strands) do
    for _, it in ipairs(S.leaflet_items(rng, s.pts, cfg.leaflet_spacing, cfg.leaflet_size)) do
      if g:room(it[1], it[2]) >= it[4] * 0.3 and rng:next() < dens(it[1], it[2]) then
        it.support={parent=s,t=it.stem_t}
        leaflet_items[#leaflet_items + 1] = it
      end
    end
  end
  local sparkles = Fill.sparkles(rng:fork("sparkles"), g, 40, spec.ornaments)
  local midfoot = { W * 0.66, m.y0 + 10 }

  -- The plant's stems are drawn once every fork is known, so each narrows
  -- where its shoots leave.
  -- The plant's own stems are brushed washes (brush.stem); the corner
  -- sprig and the excursion stay pen work.
  local painted = {}
  for _, s in ipairs(strands) do
    if s.cum then painted[#painted + 1] = s else stem_batch:stem_by(s.pts, s.width, s) end
  end
  local rf = Tune.compose.runners or 1
  for _,s in ipairs(runners) do s.growth_omitted = rf <= 0 end
  if rf > 0 then
    for _, s in ipairs(runners) do
      local w = s.width
      stem_batch:stem_by(s.pts, function(t) return w(t) * rf end, s)
    end
  end

  -- Paint back to front.
  if not pt then
    pt = Paint.new({ backend = os.getenv("FLORA_BACKEND"), gilt = spec.gilt, backdrop = Color.backdrop(spec.backdrop) })
    pt.probe = spec.probe
    pt.gilt_dpi, pt.gilt_env, pt.gilt_look = spec.gilt_dpi, spec.gilt_env, spec.gilt_look
  end
  local function layer(tag, fn)
    pt:begin_group(tag)
    fn()
    pt:end_group()
  end
  -- The painting's units (GROWN, BLOOM), and a tally of those painted.
  local units = #back + #painted + #leaves + BLOOM * #blooms + #(ctx.visitors or {}) + #orn
    + BATCH.stems + BATCH.sprays + BATCH.leaflets + BATCH.hero + BATCH.finish
  local painting, done = prog:part(GROWN.details, 1), 0
  local function paid(n)
    done = done + n
    painting:at(done / units)
  end
  -- A "watch it grow" frame (spec.grow below 1) paints only what the growth
  -- front has reached (clock.lua); otherwise every element paints in full.
  local clock = spec.grow and spec.grow < 1 and Clock.new(g, stems, spec.grow) or nil
  pt.clock = clock
  local growth = spec._progression and Clock.new(g, stems, 1)
  pt.growth_clock = growth
  local function birth(at)
    return at and growth:birth(at[1], at[2]) / growth.reach * 0.7 or 0.82
  end
  local function draw(f, dur, delay)
    if clock then clock:draw(pt, f, ctx.pos[f], dur, delay)
    elseif growth then Progression.part(pt, pt.group and pt.group.tag, ctx.pos[f], birth(ctx.pos[f]), dur,
      function() f(pt) end, nil, ctx.support[f])
    else
      f(pt)
      if pt.gilt_pending then require("flora.orn_raster").flush(pt) end
    end
  end
  layer("back", function()
    for _, f in ipairs(back) do draw(f, 0.1); paid(1) end
  end)
  -- Bottom to top, as in the reference: stems and sprays, then leaflets,
  -- then leaves, then blooms. Each leaf knocks out what lies under it.
  layer("stems", function()
    local sr = rng:fork("stem paint")
    for _, s in ipairs(painted) do
      if clock then
        clock:stem(pt, s, Tune.plant.root_width, function(p) Brush.stem(p, sr, s.pts, s.width, Tune.plant) end)
      elseif growth then
        local off = growth.offset[s] / growth.reach * 0.7
        local dur = G.length(s.pts) / growth.reach * 0.7
        Progression.part(pt, "stem", s.pts[1], off, dur,
          function() Brush.stem(pt, sr, s.pts, s.width, Tune.plant) end, s.pts,
          {token=s,parent=s.growth_parent,t=s.growth_t})
      else
        Brush.stem(pt, sr, s.pts, s.width, Tune.plant)
      end
      paid(1)
    end
    stem_batch:paint(pt)
    paid(BATCH.stems)
  end)
  -- Fine sprays are pen work in a diluted ink, lighter than the stems.
  layer("sprays", function() spray_batch:paint(pt, Paint.mix(pal.ink, pal.sky, 0.4)) end)
  paid(BATCH.sprays)
  layer("leaflets", function()
    if clock then
      clock:leaflets(pt, rng:fork("leaflets"), leaflet_items, L.leaflets)
    elseif growth then
      local lr = rng:fork("leaflets")
      for _,it in ipairs(leaflet_items) do
        Progression.part(pt, "leaflet", it, birth(it), 0.05,
          function() L.leaflets(pt, lr, {it}) end, nil, it.support)
      end
    else
      L.leaflets(pt, rng:fork("leaflets"), leaflet_items)
    end
  end)
  paid(BATCH.leaflets)
  layer("leaves", function()
    for _, f in ipairs(leaves) do draw(f, 0.06); paid(1) end
  end)
  local hero_draw = function(p) F.hero(p, rng:fork("hero"), hero) end
  local function paint_hero()
    if clock then clock:draw(pt, hero_draw, hero, 0.15)
    elseif growth then
      local cap = strands[1].pts[#strands[1].pts]
      Progression.part(pt, "hero", cap, birth(cap), 0.15, function() hero_draw(pt) end, nil,
        {parent=strands[1],t=1})
    else hero_draw(pt) end
    paid(BATCH.hero)
  end
  layer("blooms", function()
    for _, f in ipairs(blooms) do draw(f, 0.1, 10); paid(BLOOM) end
    if not spec.header then paint_hero() end
  end)
  if ctx.visitors then
    layer("visitors", function()
      for _, f in ipairs(ctx.visitors) do draw(f, 0.08, clock and clock.reach * 0.25); paid(1) end
    end)
  end
  layer("ornaments", function()
    for _, f in ipairs(orn) do
      if f == mark_fn and held then
        -- The same draw, later: in this frame's map and tune, growing as
        -- the other ornaments do.
        local fn, tune = pt.frame_fn, spec.tune
        held[#held + 1] = function()
          pt:frame(fn)
          Tune._with(tune, function() draw(f, 0.15) end)
        end
      else
        draw(f, 0.15)
      end
      paid(1)
    end
    if growth then
      pt.progression:alternate(pt, function()
        for _,it in ipairs(sparkles) do
          Progression.part(pt, "sparkle", it, 0.84, 0.15, function() O.sparkles(pt, {it}) end)
        end
      end, function()
        O.sparkles(pt, sparkles)
        if pt.gilt_pending then require("flora.orn_raster").flush(pt) end
      end)
    else
      O.sparkles(pt, clock and clock:sparkles(sparkles) or sparkles)
      if pt.gilt_pending then require("flora.orn_raster").flush(pt) end
    end
    if not spec.bare then draw(function(p) O.compass(p, midfoot[1], midfoot[2], 7, { hair = 0.9, ring = 0 }) end, 0.15) end
  end)
  -- With a header mode set, the hero stays above the ornaments around it.
  if spec.header then layer("hero", paint_hero) end
  paid(BATCH.finish)
  pt.clock = nil
  pt.growth_clock = nil
  pt.coverage = g:coverage()
  pt.panel = panel
  pt.ghost = ghost
  -- Motifs placed by kind (grow.lua), and the large leaves, for tests.
  pt.counts = ctx.counts
  pt.counts.leaves = #leaves
  pt.sparkles = sparkles
  return pt
end

-- Plan and paint a page. spec: width, height, text = {x0, y0, x1, y1},
-- optional lines, header_y, seed, edge, layout (frames.lua) with page and
-- title, and probe(x, y, r), which sees every painted point in page
-- coordinates (tests use it to check nothing lands on text); on_frame(f),
-- when given, is told each frame before its plant is painted; progress(f),
-- when given, is told how much of the page is done (0 to 1, rising, by
-- about 0.01 at a time and ending in 1).
function C.page(spec)
  local palette = Mix.resolve(spec.palette, spec.seed, spec.spin)
  return Mix.with_palette(palette, function()
    return Tune._with(spec.tune, function() return Mix.with_mix(spec.mix, function() return C.frames(spec) end) end)
  end)
end

-- Clip plants at the header boundary: the measured body top in body mode,
-- or the running head's bottom when gesture.header_clip is set. Title
-- furniture stays outside the margin-mode clip.
local function header_clip(pt, spec)
  local y, through
  if spec.header == "body" and spec.body_top then
    y, through = spec.body_top, true
  elseif (Tune.gesture.header_clip or 0) > 0 and spec.header_y and spec.frametitle then
    y, through = spec.header_y - (Tune.gesture.header_gap or 0), false
  end
  if not y then return nil end
  local w = spec.width
  pt:clip_begin({ { "m", 0, 0 }, { "l", w, 0 }, { "l", w, y }, { "l", 0, y }, { "z" } })
  pt.header_clip = y
  -- Running-head marks the plants hold back until this clip ends.
  if not through then pt.held_marks = {} end
  return { through = through }
end

-- Ends the margin-mode header clip, then paints the running-head marks the
-- plants held back under it: above every plant, still inside the page inset
-- and the reserved boxes, in the ornaments layer of the page.
local function end_header_clip(pt)
  pt:clip_end()
  local held = pt.held_marks
  pt.held_marks = nil
  if not held or #held == 0 then return end
  local fn = pt.frame_fn
  pt:begin_group("ornaments")
  for _, paint in ipairs(held) do paint() end
  pt:end_group()
  pt:frame(fn)
end

-- The page's frames (frames.lua), after its top inset is applied to its
-- text block, each told the page's foot runs; and that inset. C.frames and
-- C.header_marks lay a page out alike.
local function page_frames(spec)
  -- The wreath frames the text below the running head, not the head itself.
  if spec.header == "body" and spec.body_top then
    spec.top_inset = math.max(spec.height - spec.body_top, Tune.gesture.top_inset or 0)
    spec.text.y1 = math.min(spec.text.y1, spec.body_top)
  end
  local inset = spec.top_inset or Tune.gesture.top_inset or 0
  if inset > 0 and spec.text then
    spec.text.y1 = math.min(spec.text.y1, spec.height - inset)
  end
  local frames = Frames.of(spec)
  C.stem_runs(frames, spec)
  return frames, inset
end

-- Whether a page's marks wait for its margin-mode header clip to end
-- (header_clip): its plants place them without that clip.
local function marks_held(spec)
  if spec.header == "body" and spec.body_top then return false end
  return (Tune.gesture.header_clip or 0) > 0 and spec.header_y ~= nil and spec.frametitle and true or false
end

local function deep_copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = deep_copy(v) end
  return out
end

-- The running-head marks of a page, placed without growing it, for any
-- measured lines: C.mark_layout(spec) lays the page out once (its frames,
-- foot runs, ceilings and tune, as C.page would), and its :place(lines)
-- returns
--   a list of { frame = k, y, size, rule } (C.header_mark), one for each of
--   the page's frames that holds a mark, in frame order, for a page whose
--   measured lines are `lines` (page coordinates; spec.lines is not read);
--   and `lines` cut to those that decide the marks: each line that may
--   bound a mark from below or crosses its ceiling, whatever its frame.
--   Lines cut to these place the same marks with the same layout.
-- The spec is not changed. In most layouts the frames depend on the text
-- block, not on the lines, so the layout depends on everything in the spec
-- but its lines, and pages that differ only in their lines can share one.
-- Where the frames follow the lines (Frames.follows_lines: flank's column,
-- the bouquet's and the crowns' title block), the layout is built from
-- spec.lines, as the page's frames are: `lines` then set only the marks'
-- floors, and a layout is shared only by pages whose spec.lines are alike.
--
-- C.page paints only the marks, and nothing else of the page, for a spec
-- whose marks_only holds such a list: the same rule and ornament, in the
-- same clips, as on the full page. An adapter that shows one drawing on
-- several pages can so paint each page's own marks over it, placed by that
-- page's own geometry.
local MarkLayout = {}
MarkLayout.__index = MarkLayout

function C.mark_layout(spec)
  local s = deep_copy(spec)
  if not Frames.follows_lines(s) then s.lines = nil end
  local frames = {}
  Tune._with(s.tune, function()
    local held = marks_held(s)
    for k, f in ipairs(page_frames(s)) do
      local fs = f.spec
      if fs.header_y then
        local function bounds()
          local inset = fs.top_inset or Tune.gesture.top_inset or 0
          local ceil, x0, x1, hx = mark_bounds(fs, inset, not held and header_clip_y(fs) or nil)
          frames[#frames + 1] = { frame = k, inv = f.map and Frames.invert(f.map), w = fs.width, h = fs.height,
            ceil = ceil, x0 = x0, x1 = x1, hx = hx, runs = fs.stem_runs, min = Tune.gesture.mark_min,
            reach = math.max(MARK_SIZE, Tune.gesture.mark_min) + MARK_INK,
            kind_reach = mark_reach(), obstacles = mark_obstacles(fs) }
        end
        if fs.tune then Tune._with(fs.tune, bounds) else bounds() end
      end
    end
  end)
  return setmetatable({ frames = frames }, MarkLayout)
end

function MarkLayout:place(lines)
  lines = lines or {}
  local marks, keep = {}, {}
  for _, f in ipairs(self.frames) do
    -- The lines as the frame carries them (frames.lua), for the mark.
    local own = f.inv and Frames.carry_lines(lines, f.inv, f.w, f.h) or lines
    local place = mark_at(own, f.runs, f.ceil, f.x0, f.x1, f.hx, f.min, f.kind_reach, f.obstacles)
    if place then marks[#marks + 1] = { frame = f.frame, y = place.y, size = place.size, rule = place.rule } end
    -- Each page line in this frame's coordinates, not cut to the frame: a
    -- line the frame keeps lies inside it, so none the mark needs is lost.
    -- With an obstacle the mark may move down its band, so the line that
    -- sets its floor is kept wherever it lies.
    local top, top_i
    for i, l in ipairs(lines) do
      local b = l
      if f.inv then
        local ax, ay = Frames.apply(f.inv, l.x0, l.y0)
        local bx, by = Frames.apply(f.inv, l.x1, l.y1)
        b = { x0 = math.min(ax, bx), y0 = math.min(ay, by), x1 = math.max(ax, bx), y1 = math.max(ay, by) }
      end
      if b.x1 > f.x0 and b.x0 < f.x1 and b.y0 < f.ceil then
        if b.y1 > f.ceil - f.reach then keep[i] = true end
        if not top or b.y1 > top then top, top_i = b.y1, i end
      end
    end
    if top_i and #f.obstacles > 0 then keep[top_i] = true end
  end
  local cut = {}
  for i, l in ipairs(lines) do
    if keep[i] then cut[#cut + 1] = deep_copy(l) end
  end
  return marks, cut
end

-- C.mark_layout(spec):place(spec.lines), in one call.
function C.header_marks(spec)
  return C.mark_layout(spec):place(spec.lines)
end

-- Paints the marks of spec.marks_only (C.header_marks) where the page's
-- plants would: after a margin-mode header clip ends, or inside a body-mode
-- clip and the frame's own clip, each in its frame's map and tune.
local function paint_marks(pt, spec, frames, clip)
  local held = clip and not clip.through
  if held then
    pt:clip_end()
    pt.held_marks = nil
  end
  pt:begin_group("ornaments")
  for _, m in ipairs(spec.marks_only) do
    local f = assert(frames[m.frame], "marks_only: the page has no frame " .. tostring(m.frame))
    assert(type(m.y) == "number" and type(m.size) == "number" and m.size > 0, "marks_only: a mark needs y and size")
    local fs = f.spec
    pt:frame(f.fn)
    local cl = not held and f.fn and fs.clip_x1
    if spec.probe or spec.keep_bounds then cl = nil end
    if cl then
      local ch, w, h = fs.clip_y1 or fs.height, fs.width, fs.height
      pt:clip_begin({
        { "m", 0, 0 }, { "l", cl, 0 }, { "l", cl, ch },
        { "l", w, ch }, { "l", w, h }, { "l", 0, h }, { "z" },
      })
    end
    local paint = mark_painter(fs, Rng.new(fs.seed or 1), m)
    if fs.tune then Tune._with(fs.tune, function() paint(pt) end) else paint(pt) end
    if pt.gilt_pending then require("flora.orn_raster").flush(pt) end
    if cl then pt:clip_end() end
  end
  pt:end_group()
  pt:frame(nil)
  if clip and clip.through then pt:clip_end() end
end

-- C.page, after the page's palette is in place.
function C.frames(spec)
  local frames, inset = page_frames(spec)
  local prog = progress(spec.progress)
  local pt = Paint.new({ backend = spec.backend or os.getenv("FLORA_BACKEND"), gilt = spec.gilt, backdrop = Color.backdrop(spec.backdrop) })
  pt.probe = spec.probe
  pt.gilt_dpi, pt.gilt_env, pt.gilt_look = spec.gilt_dpi, spec.gilt_env, spec.gilt_look
  Progression.attach(pt, spec)
  -- Keep page clearance outside the header clip: margin-mode title
  -- furniture may cross that header boundary, but never the page inset.
  local page_clip = inset > 0 and not (spec.probe or spec.keep_bounds)
  if page_clip then
    local w, y = spec.width, spec.height - inset
    pt:clip_begin({ { "m", 0, 0 }, { "l", w, 0 }, { "l", w, y }, { "l", 0, y }, { "z" } })
  end
  -- Exclusions belong to the page, outside every plant's frame map.
  -- Reverse each inner contour so the nonzero clip subtracts its box.
  for _, r in ipairs(spec.reserve or {}) do
    local w, h = spec.width, spec.height
    pt:clip_begin({
      { "m", 0, 0 }, { "l", w, 0 }, { "l", w, h }, { "l", 0, h }, { "z" },
      { "m", r[1], r[2] }, { "l", r[1], r[4] }, { "l", r[3], r[4] }, { "l", r[3], r[2] }, { "z" },
    })
  end
  local clip = header_clip(pt, spec)
  if spec.marks_only then
    paint_marks(pt, spec, frames, clip)
    for _ in ipairs(spec.reserve or {}) do pt:clip_end() end
    if page_clip then pt:clip_end() end
    prog:at(1)
    return pt
  end
  -- A page given a pattern is filled with it instead of flora.
  if spec.pattern and require("flora.pattern").paint(spec, pt) then
    if clip and not clip.through then end_header_clip(pt) elseif clip then pt:clip_end() end
    for _ in ipairs(spec.reserve or {}) do pt:clip_end() end
    if page_clip then pt:clip_end() end
    prog:at(1)
    return pt
  end
  if #frames == 1 and not frames[1].fn then
    plant(spec, pt, prog)
    if clip and not clip.through then end_header_clip(pt) elseif clip then pt:clip_end() end
    for _ in ipairs(spec.reserve or {}) do pt:clip_end() end
    if page_clip then pt:clip_end() end
    prog:at(1)
    return pt
  end
  local cover = 0
  -- What a layout paints under its plants (the scrollwork's band).
  if frames.before then
    pt:begin_group("under")
    Progression.part(pt, "under", {spec.width/2, spec.height/2}, 0, 0.8, function() frames.before(pt) end)
    pt:end_group()
  end
  -- The plants share the page's progress equally; title furniture, when
  -- painted, takes TITLE_SHARE of it after them.
  local titled = frames.title and (spec.grow or 1) >= 0.9
  local plants = titled and 1 - TITLE_SHARE or 1
  for k, f in ipairs(frames) do
    if spec.on_frame then spec.on_frame(f) end
    pt:frame(f.fn)
    local cl = f.spec.clip_x1
    if spec.probe or spec.keep_bounds then cl = nil end
    if cl then
      -- Frame minus the forbidden top-left notch, so the lower margin and
      -- the turned hero survive below the title band.
      local ch, w, h = f.spec.clip_y1 or f.spec.height, f.spec.width, f.spec.height
      pt:clip_begin({
        { "m", 0, 0 }, { "l", cl, 0 }, { "l", cl, ch },
        { "l", w, ch }, { "l", w, h }, { "l", 0, h }, { "z" },
      })
    end
    if f.spec.tune then
      Tune._with(f.spec.tune, function() plant(f.spec, pt, prog:part(plants * (k - 1) / #frames, plants * k / #frames)) end)
    else
      plant(f.spec, pt, prog:part(plants * (k - 1) / #frames, plants * k / #frames))
    end
    if cl then pt:clip_end() end
    cover = cover + pt.coverage / #frames
  end
  pt:frame(nil)
  if clip and not clip.through then end_header_clip(pt) end
  -- Title furniture paints over the finished crowns, in page coordinates;
  -- while the page grows it waits for the plants. It stays inside the body
  -- clip in body mode, so the crest cannot sit in the header.
  if titled then
    pt:begin_group("title")
    Progression.part(pt, "title", {spec.width / 2, spec.height}, 0.82, 0.18,
      function() Title.paint(pt, spec, frames.title) end)
    pt:end_group()
  end
  -- What a layout paints over its plants (the bouquet's ribbons, the
  -- scrollwork's head and foot).
  if frames.after then
    pt:begin_group("over")
    Progression.part(pt, "over", {spec.width/2, spec.height/2}, 0.82, 0.18, function() frames.after(pt) end)
    pt:end_group()
  end
  prog:at(1)
  if clip and clip.through then pt:clip_end() end
  for _ in ipairs(spec.reserve or {}) do pt:clip_end() end
  if page_clip then pt:clip_end() end
  pt.title = frames.title
  pt.coverage = cover
  pt.frames = frames
  return pt
end

return C
