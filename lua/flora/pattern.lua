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
--            cells and a ruled frame round the text), guilloche (whole
--            cells and a guilloche band round the text, pattern_hero.lua)
--   outer    how it meets the paper's edge: bleed (it runs off the page)
--            or margin (whole cells only, inside a small margin)
--   scale    the cell size, as a factor of the pattern's own
--
-- Fading mixes each colour with the paper rather than painting it
-- translucent, so no cell needs a transparency group of its own.
-- While a page grows (progression.lua) each cell appears by its distance
-- from the page's outer edge: its construction lines first, then the
-- cell painted over them. A cell with a compass point draws its lines as
-- a compass turns about it, then its bands in a second turn. The
-- lines are painted on a page that does not grow too, under the bands,
-- so its last frame and the page are the same.
--
-- spec.pattern_hero (hero=) adds one large radial motif at a top corner
-- (pattern_hero.lua): the cells keep clear of its disc, as they keep
-- clear of the text, and it grows ring by ring from its centre.

local Rng = require("flora.rng")
local Paint = require("flora.paint")
local Color = require("flora.color")
local Mix = require("flora.mix")
local Patterns = require("flora.patterns")
local Progression = require("flora.progression")

local M = {}

M.edges = { dissolve = true, cell = true, fade = true, border = true, guilloche = true }
M.outers = { bleed = true, margin = true }

-- Distances in pt.
local GAP, BORDER_GAP, OUTER_MARGIN = 6, 12, 4
-- The edges that frame the text, and how far their cells keep from it.
local FRAMED = { border = BORDER_GAP, guilloche = 18 }

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

-- How far cell `c`'s outline lies from disc d = {x, y, r}: 0 when they
-- meet or one holds the other, as M.clearance measures it from a
-- rectangle.
function M.disc_clearance(c, d)
  if c.circle then
    local dx, dy = c.circle[1] - d[1], c.circle[2] - d[2]
    return math.max(0, math.sqrt(dx * dx + dy * dy) - c.circle[3] - d[3])
  end
  local P = c.verts
  if in_poly(d[1], d[2], P) then return 0 end
  local e, j = math.huge, #P
  for i = 1, #P do
    e = math.min(e, seg_point(d[1], d[2], P[j], P[i]))
    j = i
  end
  return math.max(0, e - d[3])
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

-- How long a cell's construction lines and its painting take, as
-- growth time.
local LINES, BAND = 0.07, 0.08
-- When the latest cell is finished, as growth time: the latest birth
-- (0.88) and its lines and painting (0.05 + 0.04 in a spec.grow frame).
local DONE = 0.97

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
  if side or FRAMED[edge] or not spec.lines or #spec.lines == 0 then out[#out + 1] = { t.x0, t.y0, t.x1, t.y1 } end
  for _, l in ipairs(spec.lines or {}) do out[#out + 1] = { l.x0, l.y0, l.x1, l.y1 } end
  for _, r in ipairs(spec.reserve or {}) do out[#out + 1] = { r[1], r[2], r[3], r[4] } end
  return out
end

-- The roles a pattern paints with, and where each takes its colour. A
-- pattern module lists the roles it uses (`roles`, patterns.lua) and
-- paints only with them; it never picks an ink itself.
--
--   ground  a surface under the cells, cell by cell: the cell's `under`
--           path, else its tile. Painted under ground=on for the patterns
--           that list it, at the module's own lightness (its `ground`),
--           unless the palette sets ground=none.
--   band    the strapwork and line work
--   core    the light line down a band's middle
--   a, b    the two fields (ink.fill[1], ink.fill[2])
--   accent  small details: centres, dots, jewels
--   line    construction lines while a cell grows: the band mixed
--           toward the paper (or the ground) by `mix`
--
-- Each role takes its ink from the page's pattern palette
-- (spec.patternpalette, \florasetup's patternpalette or a colourway's
-- own, inks.lua), keyed by the names users see (M.ROLE_KEYS): an ink, an
-- ink group (one of its inks for the whole page, so a flat field does not
-- turn patchy), paper, gold, or for the ground none. An ink or group may
-- carry its lightness and chroma share, ink:L or ink:L:share (an empty L
-- keeps the role's), which a colourway composed for patterns uses. A role the palette
-- leaves out is derived from the flora's palette parts, as M.roles says:
-- { part = palette part, L = lightness, share = chroma kept, sat = chroma
-- kept as a share of the page's saturation, fallback = the Paint.palette
-- colour for a part painted "look", taken at the role's lightness when
-- `relight` }, or { paper = true }, or { gold = true }. The fields and the
-- ground are muted by the page's saturation (the saturation key, default
-- Settings.PATTERN's), whichever ink they take.
--
-- On a dark backdrop every ink is repainted as flora's are, and the
-- pattern's paper follows the page: it turns to the page's own dark. A
-- ground darker than DARK lights the bands on it (Color.on_ground, as a
-- dark backdrop would) and is painted as it is on either backdrop, so it
-- stays darker than its bands on paper and on a dark page alike.
M.roles = {
  ground = { part = "leaves", L = 0.30, sat = 0.4, fallback = "ink", relight = true },
  band = { part = "leaves", L = 0.22, share = 1, fallback = "ink" },
  core = { paper = true },
  a = { part = "blooms", L = 0.70, sat = 1, fallback = "gold" },
  b = { part = "sprays", L = 0.60, sat = 1, fallback = "sky" },
  accent = { gold = true },
  line = { mix = 0.45 },
}
local DARK = 0.5

-- Pattern key `k` of `spec` (Settings.PATTERN's keys), or its default.
local function key(spec, k)
  local Settings = require("flora.settings")
  local v = spec[Settings.SPEC[k]]
  if v == nil then v = Settings.PATTERN[k] end
  return v
end
M.key = key

-- A palette value split into its ink (or group) and the lightness and
-- chroma share it may carry: "ink", "ink:L", "ink:L:share" or "ink::share".
function M.palette_value(v)
  local ink, L, share = tostring(v):match("^([^:]*):?([^:]*):?([^:]*)$")
  return ink, tonumber(L), tonumber(share)
end

-- The palette's keys, as users write them, and the roles they set; in the
-- order the catalog lists them, with each role's label and the flora part
-- it is derived from when the palette leaves it out.
M.ROLE_KEYS = {
  { key = "band", role = "band", label = "Band", part = "leaves", about = "The strapwork and line work." },
  { key = "core", role = "core", label = "Band core", part = nil, about = "The light line down a band's middle; the paper unless set." },
  { key = "fielda", role = "a", label = "Field A", part = "blooms", about = "The first field: stars, tiles, petals." },
  { key = "fieldb", role = "b", label = "Field B", part = "sprays", about = "The second field." },
  { key = "ground", role = "ground", label = "Ground", part = "leaves", about = "The surface under the patterns that have one; none for the paper." },
  { key = "accent", role = "accent", label = "Accent", part = nil, about = "Centres, dots and jewels; gold unless set." },
}
local USER = {}
for _, r in ipairs(M.ROLE_KEYS) do USER[r.role] = r.key end

-- The finishes and band characters a page may ask for.
M.finishes = { filled = true, lines = true }
M.band_kinds = { strap = true, line = true }

-- M.roles with the overrides `over` (role -> table of keys).
function M.role_spec(over)
  local out = {}
  for k, r in pairs(M.roles) do
    local o = over and over[k]
    if o and (o.paper or o.gold) then
      out[k] = o
    else
      local t = {}
      if not (o and o.part and (r.paper or r.gold)) then for kk, v in pairs(r) do t[kk] = v end end
      for kk, v in pairs(o or {}) do t[kk] = v end
      out[k] = t
    end
  end
  return out
end

-- `rgb` with its chroma scaled by `share`.
local function muted(rgb, share)
  if not share or share == 1 then return rgb end
  local L, Ch, h = Color.lch(rgb)
  return Color.oklch(L, Ch * share, h)
end

-- The page's colours for pattern `p` (a patterns.lua module, or a table
-- with its name and roles), one per role (see M.roles), drawn from `rng`,
-- for `spec`'s pattern palette, saturation, finish, backdrop and
-- (internal) role overrides spec.pattern_roles.
function M.role_inks(rng, p, spec)
  spec = spec or {}
  local pal, tp = Paint.palette, require("flora.tune").color.palette
  local R = M.role_spec(spec.pattern_roles)
  local given = spec.patternpalette or {}
  local sat = key(spec, "saturation")
  local function role(name, L)
    local r = R[name]
    local share = r.share or (r.sat and r.sat * sat) or 1
    local v, vL, vs = given[USER[name]], nil, nil
    if v then v, vL, vs = M.palette_value(v) end
    -- A lightness the palette gives holds unless the caller asks for one
    -- (the ground's own, the dark disc's).
    L = L or vL
    share = vs or share
    if v == "paper" or (v == nil and r.paper) then return pal.paper end
    if v == "gold" or (v == nil and r.gold) then return pal.gold end
    if v == "none" then return nil end
    local ink
    if v then
      ink = Color.ink_for(rng:fork("role " .. name), v)
    else
      ink = Color.ink_for(rng:fork("ink " .. r.part), tp[r.part])
    end
    if not ink then
      local c = pal[r.fallback or "ink"]
      if not r.relight then return muted(c, share) end
      local _, Ch, h = Color.lch(c)
      return Color.oklch(L or r.L, Ch * share, h)
    end
    return Color.ink_rgb(ink, L or r.L, share)
  end
  local lines = key(spec, "finish") == "lines"
  local base = { band = role("band"), core = role("core"), fill1 = role("a"), fill2 = role("b"),
    accent = role("accent"), lines = lines }
  base.core = base.core or pal.paper
  base.accent = base.accent or pal.gold
  -- The dark ground a motif with a ground of its own paints (the rose
  -- window), whether or not the pattern has a ground.
  base.dark = role("ground", math.min(R.ground.L, DARK - 0.05)) or role("band", 0.30)
  local has = false
  for _, r in ipairs(p.roles or {}) do if r == "ground" then has = true end end
  if has and not lines and p.ground and key(spec, "ground") == "on" then
    base.ground = role("ground", R.ground.on and R.ground.on[p.name] or p.ground)
    base.lit = base.ground and Color.lightness(base.ground) < DARK
  end
  -- The hero lies on the paper, never on the ground, so it keeps the
  -- bands unlit (band0, line0).
  base.band0 = base.band
  base.line0 = Paint.mix(base.band, pal.paper, R.line.mix)
  base.line = base.line0
  if base.ground and Color.lightness(base.ground) < DARK then
    base.band = Color.on_ground(base.band, base.ground, pal.paper)
    base.line = Paint.mix(base.band, base.ground, R.line.mix)
  end
  return base
end

-- A cell's colours, mixed toward the paper by 1 - a; `hero` for the
-- hero's, which lies on the paper with its bands unlit.
local function inks(base, a, hero)
  local pal = Paint.palette
  local function f(c) return c and (a >= 1 and c or Paint.mix(pal.paper, c, a)) end
  return {
    band = f(hero and base.band0 or base.band), core = f(base.core), accent = f(base.accent),
    line = f(hero and base.line0 or base.line),
    fill = { f(base.fill1), f(base.fill2) },
    ground = f(base.ground), dark = f(base.dark), paper = f(pal.paper),
    lines = base.lines,
  }
end

-- The band character on `ink`: width (the full width), bands, corefrac
-- and linew (the line character's width), for pattern p at scale `k`.
local function band_ink(ink, p, spec, k)
  local f = key(spec, "bandwidth")
  ink.width = (p.width or p.scale / 6) * k * f
  -- Under the lines finish a pattern may read better with another band
  -- character than its filled one (its `lines_bands`).
  local bands = key(spec, "bands")
  if bands == "auto" then bands = (key(spec, "finish") == "lines" and p.lines_bands) or p.bands or "strap" end
  ink.bands = bands
  ink.corefrac = p.core or 0.45
  ink.linew = (p.line or 0.6) * f
  return ink
end
M.band_ink = band_ink

-- The weights pattern={...} gave, as a table (a bare name weighs 1).
local function weights(v)
  if type(v) == "string" then return { [v] = 1 } end
  return v or {}
end

-- The page's hero disc {x, y, r, name} (pattern_hero.lua), or nil when
-- spec.pattern_hero is unset or none, or its corner has no room. Under
-- outer=margin it lies wholly inside the page's margin, as the cells do.
function M.hero(spec, side, top, keep, gap)
  local name = key(spec, "hero")
  if not name or name == "none" then return nil end
  local margin = key(spec, "outer") == "margin" and OUTER_MARGIN or nil
  return require("flora.pattern_hero").place(name, spec, side, top, keep, gap, margin)
end

-- Paint hero disc d's rings, from the centre outward, as the cells are
-- painted: progression parts, or for a spec.grow frame those born by
-- `grow`.
function M.paint_hero(pt, d, ink, grow)
  local Hero = require("flora.pattern_hero")
  local rings = Hero.rings(d, ink)
  for i, ring in ipairs(rings) do
    local birth = Hero.birth(i, #rings)
    if grow then
      if grow >= birth then ring.construct(pt) end
      if grow >= birth + 0.09 then ring.paint(pt) end
    else
      Progression.part(pt, "pattern_hero_line", { d[1], d[2] }, birth, 0.07,
        function() ring.construct(pt) end, nil, { no_area = true })
      Progression.part(pt, "pattern_hero", { d[1], d[2] }, birth + 0.05, 0.08,
        function() ring.paint(pt) end)
    end
  end
end

-- Whether M.paint fills spec's page with a pattern rather than flora: its
-- pattern weights leave one to pick. Draws on a stream of its own, so the
-- page's randomness is not touched.
function M.applies(spec)
  if not spec.pattern then return false end
  return Patterns.pick(Rng.new(spec.seed or 1):fork("choose pattern"), weights(spec.pattern)) ~= nil
end

-- Lay out and paint the page's pattern onto `pt`. Returns false when the
-- pattern weights leave nothing to pick, so the caller grows flora.
function M.paint(spec, pt)
  local rng = Rng.new(spec.seed or 1)
  local p = Patterns.pick(rng:fork("choose pattern"), weights(spec.pattern))
  if not p then return false end
  local W, H, text = spec.width, spec.height, spec.text
  local side = sides(spec)
  local edge = key(spec, "edge")
  local outer = key(spec, "outer")
  local k_scale = key(spec, "scale")
  local size = p.scale * k_scale
  local width = band_ink({}, p, spec, k_scale).width
  local dens = Mix.weight(spec.mix, "density")
  local gap = FRAMED[edge] or GAP
  -- The room the field has beside the text sets how far it takes to thin.
  local room = side and math.max(side.left and text.x0 or 0, side.right and W - text.x1 or 0) or 120
  local ramp = math.max(size, 0.6 * math.min(room, 120)) / math.max(dens, 1e-6)
  local keep_rects = avoid(spec, side, edge)
  -- The page's top as painted: below a top inset, and below the header
  -- clip compose.lua set (header=body), so margin cells stay whole.
  local inset = spec.top_inset or require("flora.tune").gesture.top_inset or 0
  local top = math.min(H, inset > 0 and H - inset or H, pt.header_clip or H)
  local base = M.role_inks(rng:fork("pattern inks"), p, spec)
  local hero = M.hero(spec, side, top, keep_rects, gap)

  local cells = p.cells({ x0 = 0, y0 = 0, x1 = W, y1 = H, size = size, rng = rng:fork("cells") })
  local fall = rng:fork("dissolve")
  local stagger = rng:fork("growth")
  local kept, offered, bare = {}, 0, {}
  for _, c in ipairs(cells) do
    local r, jitter = fall:next(), stagger:next()
    local in_side = not side or (side.left and c.x < text.x0) or (side.right and c.x > text.x1)
    -- Paint reaches half a band and the cell's own pad beyond its outline.
    local reach = width / 2 + (c.pad or 0)
    local page = { 0, 0, W, top }
    local placed = in_side and not (hero and M.disc_clearance(c, hero) - reach < GAP)
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
      elseif dens > 0 and d >= gap and edge == "dissolve" then
        -- A cell dissolved away still lays its piece of the ground, so the
        -- ground runs whole to the field's edge and the cells fall away
        -- over it.
        bare[#bare + 1] = { cell = c, a = 1, jitter = jitter }
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
  -- On a dark ground the pattern is painted as it is on any backdrop
  -- (M.roles).
  local function lit(fn)
    if not base.lit then return fn() end
    pt.metal = pt.metal + 1
    local ok, err = pcall(fn)
    pt.metal = pt.metal - 1
    if not ok then error(err, 0) end
  end
  local grounded = {}
  for _, k in ipairs(kept) do grounded[#grounded + 1] = k end
  for _, k in ipairs(bare) do grounded[#grounded + 1] = k end
  for _, k in ipairs(grounded) do
    -- The construction lines lie under the finished cell's bands, so a
    -- page painted at once and the last frame of its growth are the same.
    local c = k.cell
    k.birth = 0.78 * root(c) / far + 0.1 * k.jitter
    -- A cell with a compass point (c.sweep) draws its lines as the
    -- compass turns, then its bands as a second turn once the first is
    -- done. Its births are drawn closer together so that the last of those
    -- turns, as the last cell's painting, ends by DONE.
    if c.sweep then k.birth = k.birth * (DONE - LINES - BAND) / 0.88 end
    k.painted = k.birth + (c.sweep and LINES or 0.05)
  end
  pt:begin_group("pattern")
  -- The ground, every cell's piece of it before any cell's lines, as the
  -- cell is painted.
  -- Pieces that meet edge to edge (the ground, a cell's plates) are
  -- stroked as well as filled, so neighbours leave no seam between them.
  local function plate(c, k, path, colour)
    local function draw() lit(function() pt:fill(path, colour, 1); pt:stroke(path, colour, 0.6, 1) end) end
    if grow then
      if grow >= k.painted then draw() end
    else
      Progression.part(pt, "pattern_ground", { c.x, c.y }, k.painted, BAND, draw, nil, { no_area = true })
    end
  end
  local holes = 0
  if base.ground then
    local K = require("flora.pat_kit")
    for _, k in ipairs(grounded) do
      local c = k.cell
      local under = c.under or (c.tile and K.path(c.tile))
      if under then plate(c, k, under, inks(base, k.a).ground)
      elseif not c.rests then holes = holes + 1 end
    end
  end
  -- A cell's plates: fields that tile the plane, painted with the ground.
  if not base.lines then
    for _, k in ipairs(kept) do
      for _, pl in ipairs(k.cell.plates or {}) do
        plate(k.cell, k, pl[1], inks(base, k.a).fill[pl[2] == "b" and 2 or 1])
      end
    end
  end
  for _, k in ipairs(kept) do
    local c, ink = k.cell, band_ink(inks(base, k.a), p, spec, k_scale)
    local birth, painted = k.birth, k.painted
    if grow then
      -- A "watch it grow" frame (spec.grow, tools/grow-frame.sh) shows a
      -- cell on the times the progression parts below use: its lines once
      -- it is born and the cell halfway through its painting, or, with a
      -- compass point, each swept as far as it has grown.
      local function swept(f, draw)
        if f >= 1 then draw()
        elseif f > 0 then
          local w = c.sweep
          pt:clip_begin(Progression.wedge(w[1], w[2], sweep_reach(c, w, width), w[3] or 0, f, w[4]))
          draw()
          pt:clip_end()
        end
      end
      if c.sweep then
        swept((grow - birth) / LINES, function() lit(function() c.construct(pt, c, ink) end) end)
        swept((grow - painted) / BAND, function() lit(function() c.paint(pt, c, ink) end) end)
      else
        if grow >= birth then lit(function() c.construct(pt, c, ink) end) end
        if grow >= painted + 0.04 then lit(function() c.paint(pt, c, ink) end) end
      end
    else
      Progression.part(pt, "pattern_line", { c.x, c.y }, birth, LINES,
        function() lit(function() c.construct(pt, c, ink) end) end, nil, { no_area = true, sweep = c.sweep })
      Progression.part(pt, "pattern", { c.x, c.y }, painted, BAND,
        function() lit(function() c.paint(pt, c, ink) end) end, nil, c.sweep and { sweep = c.sweep } or nil)
    end
  end
  if hero then M.paint_hero(pt, hero, band_ink(inks(base, 1, true), p, spec, k_scale), grow) end
  if edge == "guilloche" and (not grow or grow >= 0.1) then
    local ink = band_ink(inks(base, 1, true), p, spec, k_scale)
    Progression.part(pt, "pattern_border", { text.x0, text.y0 }, 0, 0.2, function()
      require("flora.pattern_hero").paint_band(pt, text, gap / 2, 4, ink)
    end)
  end
  if edge == "border" and (not grow or grow >= 0.1) then
    local ink = inks(base, 1, true)
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
  pt.pattern = { name = p.name, cells = #kept, offered = offered, kept = kept, avoid = keep_rects, reach = width / 2, gap = gap, hero = hero, inks = base,
    -- Cells that should lay a piece of the ground and have none.
    holes = holes, grounded = base.ground and #grounded or 0 }
  return true
end

return M
