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

-- The convex hull of points P (Andrew's monotone chain), anticlockwise.
local function hull(P)
  table.sort(P, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
  if #P < 3 then return P end
  local function cross(o, a, b) return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1]) end
  local lo, hi = {}, {}
  for _, q in ipairs(P) do
    while #lo >= 2 and cross(lo[#lo - 1], lo[#lo], q) <= 0 do lo[#lo] = nil end
    lo[#lo + 1] = q
  end
  for i = #P, 1, -1 do
    local q = P[i]
    while #hi >= 2 and cross(hi[#hi - 1], hi[#hi], q) <= 0 do hi[#hi] = nil end
    hi[#hi + 1] = q
  end
  lo[#lo] = nil
  hi[#hi] = nil
  for _, q in ipairs(hi) do lo[#lo + 1] = q end
  return lo
end

-- A painted path as shapes M.clearance measures: its circles as circles,
-- and the hull of every other point (a curve lies within its control
-- points, so the hull holds what the path paints).
local function path_shapes(cmds, out)
  local pts = {}
  local function walk(cs)
    for _, c in ipairs(cs) do
      if type(c[1]) == "table" then walk(c)
      elseif c[1] == "o" then out[#out + 1] = { circle = { c[2], c[3], c[4] } }
      elseif c[1] ~= "z" then for i = 2, #c, 2 do pts[#pts + 1] = { c[i], c[i + 1] } end
      end
    end
  end
  walk(cmds)
  if #pts > 0 then out[#out + 1] = { verts = hull(pts) } end
  return out
end

-- A path as the shapes its subpaths cover, each its own hull (and its
-- circles), so a panel of many rectangles is measured rectangle by
-- rectangle rather than as one hull over them all.
local function subpath_shapes(cmds)
  local out, cur = {}, nil
  local function walk(cs)
    for _, c in ipairs(cs) do
      if type(c[1]) == "table" then walk(c)
      elseif c[1] == "o" then out[#out + 1] = { circle = { c[2], c[3], c[4] } }
      elseif c[1] == "m" then cur = {}; out[#out + 1] = cur; cur[1] = { c[2], c[3] }
      elseif c[1] ~= "z" then
        if not cur then cur = {}; out[#out + 1] = cur end
        for i = 2, #c, 2 do cur[#cur + 1] = { c[i], c[i + 1] } end
      end
    end
  end
  walk(cmds)
  for i, s in ipairs(out) do
    if not s.circle then out[i] = { verts = hull(s) } end
  end
  return out
end

-- Everything cell `c` paints, as shapes the field measures its clearance
-- by: the cell's outline, and the pieces it lays beyond it, its piece of
-- the ground when the page lays the ground cell by cell (`base.ground`, and
-- not as one panel, `base.ground_panel`: its `under` path, else its tile)
-- and its own plates unless the page is painted as lines. A ground square
-- round a small dot reaches far past the dot. A plate that lies between
-- cells (`between`) is not the cell's alone and does not count here: it is
-- laid only when every cell it lies between is kept, and, as every plate
-- and the ground's panel, only when it keeps the gaps itself (M.paint's
-- plate). Its cells keeping theirs is not enough: a reservation may lie
-- inside it, clear of every cell round it.
function M.footprint(c, base)
  local out = { c }
  if base.ground and not base.ground_panel then
    -- The piece as the ground's edge mode lays it (M.edge_pieces): a disc
    -- about the cell under ground=round, the cell's own outline at the
    -- field's edge under ground=motif (which may reach past its piece),
    -- else its piece.
    if base.ground_edge == "discs" then
      out[#out + 1] = { circle = { c.x, c.y, 0.62 * base.ground_nd } }
    else
      if c.under then path_shapes(c.under, out) elseif c.tile then out[#out + 1] = { verts = c.tile } end
      if base.ground_edge == "shape" and c.shape then path_shapes(c.shape, out) end
    end
  end
  if not base.lines then
    for _, pl in ipairs(c.plates or {}) do
      if not pl.between then path_shapes(pl[1], out) end
    end
  end
  return out
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
--   ground  a surface under the cells: cell by cell (the cell's `under`
--           path, else its tile) under ground=cells, or one panel
--           (M.panel_path) under ground=panel, on, and auto on a dark
--           backdrop, for the patterns that list it, at the lightness the palette gives it, else
--           the module's own (its `ground`), unless the palette sets
--           ground=none.
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
-- keeps the role's), which a colourway composed for patterns uses; for a
-- field or the ground the share is the one it takes at the default
-- saturation, and other saturations scale it. A role the palette
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
-- ground darker than DARK lights the bands that lie on it (Color.on_ground,
-- as a dark backdrop would; a surface's bands lie on its fields and keep
-- their lightness) and is painted as it is on either backdrop, so it
-- stays darker than a line pattern's bands on paper and on a dark page
-- alike.
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

-- The ground key as the field reads it. on is panel on every path, the
-- settings' (Settings, which reads it so) and a spec's own pattern_ground
-- alike, so that one value never means two grounds.
function M.ground_mode(spec)
  local g = key(spec, "ground")
  if g == "on" then return "panel" end
  return g
end

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
M.finishes = { filled = true, lines = true, lacquer = true }

-- The finishes pattern `p` takes: filled and lines for every pattern, and
-- any further one the module names itself in `finishes` (lacquer, on
-- sikku_kolam and asanoha).
function M.finishes_of(p)
  local out = { "filled", "lines" }
  for _, f in ipairs(p.finishes or {}) do
    if f ~= "filled" and f ~= "lines" then out[#out + 1] = f end
  end
  return out
end

-- Whether pattern `p` takes finish `f`.
function M.takes(p, f)
  for _, g in ipairs(M.finishes_of(p)) do if g == f then return true end end
  return false
end

-- finish=lacquer, gold line work on a ground, as one value: the ground as
-- a panel, the bands as a line at half their width, and the band in gold,
-- on a pattern that names lacquer among its finishes (M.takes). A key the
-- page sets itself (ground, bands, bandwidth) goes before the value
-- lacquer gives it; the band is gold whatever the colourway gives it. On
-- any other pattern the finish is the usual filled one, byte for byte, and
-- the page says so (`warn`). Returns
-- the spec the page is painted with (`spec` itself unless lacquer applies)
-- and the warning, if any.
function M.finish_spec(spec, p)
  local Settings = require("flora.settings")
  local S = Settings.SPEC
  if spec[S.finish] ~= "lacquer" then return spec end
  local out = {}
  for k, v in pairs(spec) do out[k] = v end
  out[S.finish] = "filled"
  if not M.takes(p, "lacquer") then
    return out, string.format("finish=lacquer: %s does not take it, so it is painted with its usual finish", p.name)
  end
  if out[S.ground] == nil then out[S.ground] = "panel" end
  if out[S.bands] == nil then out[S.bands] = "line" end
  if out[S.bandwidth] == nil then out[S.bandwidth] = 0.5 end
  local pal = {}
  for k, v in pairs(spec.patternpalette or {}) do pal[k] = v end
  pal.band = "gold"
  out.patternpalette = pal
  return out
end
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

-- The chroma share role `r` (M.role_spec's) takes at saturation `sat`,
-- given the share `vs` its palette value carries, if any. A field or the
-- ground follows the page's saturation whatever ink it takes: a share the
-- palette gives is the one it takes at the default saturation, which so
-- leaves it as it was composed, and saturation 0 greys it.
function M.role_share(r, vs, sat)
  if vs then
    return r.sat and math.min(1, vs * sat / require("flora.settings").PATTERN.saturation) or vs
  end
  return r.share or (r.sat and r.sat * sat) or 1
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
  spec = M.finish_spec(spec or {}, p)
  local pal, tp = Paint.palette, require("flora.tune").color.palette
  local R = M.role_spec(spec.pattern_roles)
  local given = spec.patternpalette or {}
  local sat = key(spec, "saturation")
  local lighten = key(spec, "lighten")
  local role0
  -- The fields lightened toward the paper by the lighten key.
  local function role(name, L, default)
    local c = role0(name, L, default)
    if c and lighten > 0 and (name == "a" or name == "b") then
      local cl, ch, h = Color.lch(c)
      c = Color.oklch(cl + (0.95 - cl) * lighten, ch, h)
    end
    return c
  end
  function role0(name, L, default)
    local r = R[name]
    -- false (a colourway's reset, settings.lua) is a role left out.
    local v, vL, vs = given[USER[name]] or nil, nil, nil
    if v then v, vL, vs = M.palette_value(v) end
    -- A lightness the palette gives holds unless the caller asks for one
    -- (the dark disc's), and wins over the caller's `default` (a
    -- pattern's own ground lightness), which holds when the palette gives
    -- none.
    L = L or vL or default
    local share = M.role_share(r, vs, sat)
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
  -- The ground key: auto lays it on a dark backdrop only.
  local gmode = M.ground_mode(spec)
  local bd = spec.backdrop
  if type(bd) ~= "table" then bd = Color.backdrop(bd) end
  local wants = gmode ~= "off" and not (gmode == "auto" and not bd)
  if has and not lines and p.ground and wants then
    base.ground = role("ground", R.ground.on and R.ground.on[p.name], p.ground)
    base.lit = base.ground and Color.lightness(base.ground) < DARK
  end
  -- What a cell fades toward: the paper, which a dark backdrop repaints
  -- as the page, or, on a dark ground painted as it is (base.lit), the
  -- page's own colour, since nothing repaints it there.
  base.fade = base.lit and Color.backdrop(spec.backdrop) or pal.paper
  -- The hero lies on the paper, never on the ground, so it keeps the
  -- bands unlit (band0, line0).
  base.band0 = base.band
  base.line0 = Paint.mix(base.band, pal.paper, R.line.mix)
  base.line = base.line0
  -- A band's lightness is set against the surface it lies on: a dark
  -- ground lights the bands of a line pattern, which lie on it, but not a
  -- surface's (p.surface), whose bands lie on its fields. A gold band
  -- (finish=lacquer, or a palette's band=gold) is painted as the gold ink
  -- itself, so it is gilt as gold is (Paint:stroke), on any ground.
  if base.ground and Color.lightness(base.ground) < DARK and not p.surface then
    if base.band ~= pal.gold then base.band = Color.on_ground(base.band, base.ground, pal.paper) end
    base.line = Paint.mix(base.band, base.ground, R.line.mix)
  end
  return base
end

-- A cell's colours, mixed by 1 - a toward what it fades into
-- (base.fade: the page as it is shown); `hero` for the hero's, which lies
-- on the paper with its bands unlit and is repainted with the page.
function M.cell_inks(base, a, hero)
  local pal = Paint.palette
  local to = (not hero and base.fade) or pal.paper
  local function f(c) return c and (a >= 1 and c or Paint.mix(to, c, a)) end
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

-- A cell's position as a key, for finding it again in a second drawing.
function M.cell_key(c) return string.format("%.1f,%.1f", c.x, c.y) end

-- The grounded cells' neighbours: for each cell (by its record), the share
-- of its neighbours on the page that are grounded too (1 inside the field,
-- less at its edge) and its depth, how many steps it lies from the edge
-- (0 at the edge). Neighbours are the cells nearer than 1.6 times the
-- usual distance to a cell's nearest one.
function M.field_edges(cells, grounded, onpage)
  local set = {}
  for _, k in ipairs(grounded) do set[k.cell] = k end
  -- A grid of buckets, for the nearest cells.
  local function nearest_scale()
    local ds = {}
    local step = math.max(1, math.floor(#cells / 30))
    for i = 1, #cells, step do
      local c, best = cells[i], math.huge
      for j = 1, #cells do
        local o = cells[j]
        if o ~= c then
          local d = (o.x - c.x) ^ 2 + (o.y - c.y) ^ 2
          if d > 1e-6 and d < best then best = d end
        end
      end
      ds[#ds + 1] = math.sqrt(best)
    end
    table.sort(ds)
    return ds[math.max(1, math.floor(#ds / 2))] or 1
  end
  local nd = 1.6 * nearest_scale()
  local grid = {}
  local function gk(x, y) return math.floor(x / nd) .. "," .. math.floor(y / nd) end
  for _, c in ipairs(cells) do
    local key = gk(c.x, c.y)
    grid[key] = grid[key] or {}
    table.insert(grid[key], c)
  end
  local info = { nd = nd, share = {}, depth = {}, isolated = 0, edge = 0 }
  local neighbours = {}
  for _, k in ipairs(grounded) do
    local c, n, g, list = k.cell, 0, 0, {}
    local gx, gy = math.floor(c.x / nd), math.floor(c.y / nd)
    for dx = -1, 1 do for dy = -1, 1 do
      for _, o in ipairs(grid[(gx + dx) .. "," .. (gy + dy)] or {}) do
        if o ~= c and (o.x - c.x) ^ 2 + (o.y - c.y) ^ 2 <= nd * nd and onpage[o] ~= false then
          n = n + 1
          if set[o] then g = g + 1; list[#list + 1] = set[o] end
        end
      end
    end end
    info.share[k] = n > 0 and g / n or 1
    neighbours[k] = list
    if g == 0 then info.isolated = info.isolated + 1 end
    if g < n then info.edge = info.edge + 1 end
  end
  -- Depth from the edge, breadth first.
  local queue = {}
  for _, k in ipairs(grounded) do
    if info.share[k] < 1 then info.depth[k] = 0; queue[#queue + 1] = k end
  end
  local head = 1
  while head <= #queue do
    local k = queue[head]; head = head + 1
    for _, o in ipairs(neighbours[k]) do
      if info.depth[o] == nil then info.depth[o] = info.depth[k] + 1; queue[#queue + 1] = o end
    end
  end
  return info
end

-- The ground as one panel (ground=panel, and auto on a dark backdrop): the
-- field's side of the page, keeping the gaps a cell keeps, as everything a
-- cell paints does (M.footprint): the gap from the text and every other
-- rectangle the field keeps clear of, the gap from the hero, and under
-- outer=margin the margin; the plate's own stroke reaches 0.3 pt past it.
-- Built as rectangles band by band, so that no hole is painted twice
-- however the holes overlap; the hero's disc is cut in bands two degrees
-- of its circle high, each as wide as the disc is at its widest there.
function M.panel_path(f)
  local s = 0.3 + 1e-3
  local margin = f.outer == "margin"
  local lo = margin and OUTER_MARGIN + s or -2
  local hi = margin and f.top - OUTER_MARGIN - s or f.top + 2
  local L, R = lo, margin and f.W - OUTER_MARGIN - s or f.W + 2
  local t, o = f.text, f.gap + s
  local strips = {}
  local left, right = f.side and f.side.left, f.side and f.side.right
  if not f.side then strips[1] = { L, R } end
  if left then strips[#strips + 1] = { L, math.min(R, t.x0 - o) } end
  if right then strips[#strips + 1] = { math.max(L, t.x1 + o), R } end
  local holes = {}
  for _, r in ipairs(f.avoid and #f.avoid > 0 and f.avoid or { { t.x0, t.y0, t.x1, t.y1 } }) do
    holes[#holes + 1] = { r[1] - o, r[2] - o, r[3] + o, r[4] + o }
  end
  local h = f.hero
  local hr = h and h[3] + GAP + s
  local ys = { lo, hi }
  for _, r in ipairs(holes) do ys[#ys + 1] = r[2]; ys[#ys + 1] = r[4] end
  if h then for a = -90, 90, 2 do ys[#ys + 1] = h[2] + hr * math.sin(math.rad(a)) end end
  table.sort(ys)
  local bands = {}
  for _, y in ipairs(ys) do
    if y >= lo and y <= hi and (#bands == 0 or y - bands[#bands] > 1e-6) then bands[#bands + 1] = y end
  end
  local out = {}
  for b = 1, #bands - 1 do
    local y0, y1 = bands[b], bands[b + 1]
    for _, st in ipairs(strips) do
      local iv = { { st[1], st[2] } }
      local function cut(a, z)
        local nv = {}
        for _, q in ipairs(iv) do
          if z <= q[1] or a >= q[2] then nv[#nv + 1] = q
          else
            if a > q[1] then nv[#nv + 1] = { q[1], a } end
            if z < q[2] then nv[#nv + 1] = { z, q[2] } end
          end
        end
        iv = nv
      end
      for _, r in ipairs(holes) do if r[2] < y1 and r[4] > y0 then cut(r[1], r[3]) end end
      if h then
        local dmin = (y0 <= h[2] and h[2] <= y1) and 0 or math.min(math.abs(y0 - h[2]), math.abs(y1 - h[2]))
        if dmin < hr then
          local w = math.sqrt(hr * hr - dmin * dmin)
          cut(h[1] - w, h[1] + w)
        end
      end
      for _, q in ipairs(iv) do
        if q[2] - q[1] > 1e-6 then
          out[#out + 1] = { "m", q[1], y0 }; out[#out + 1] = { "l", q[2], y0 }
          out[#out + 1] = { "l", q[2], y1 }; out[#out + 1] = { "l", q[1], y1 }; out[#out + 1] = { "z" }
        end
      end
    end
  end
  return out
end

-- The rectangles of a panel M.panel_path built (its subpaths).
function M.path_rects(cmds)
  local out, cur = {}, nil
  for _, c in ipairs(cmds) do
    if c[1] == "m" then cur = { c[2], c[3], c[2], c[3] }; out[#out + 1] = cur
    elseif c[1] == "l" and cur then
      cur[1], cur[2] = math.min(cur[1], c[2]), math.min(cur[2], c[3])
      cur[3], cur[4] = math.max(cur[3], c[2]), math.max(cur[4], c[3])
    end
  end
  return out
end

-- Whether the disc about (x, y) of radius r lies on the union of the
-- rectangles R: its centre and eight points round it each in one of them.
local function on_rects(R, x, y, r)
  for k = 0, 8 do
    local px, py = x, y
    if k > 0 then local a = (k - 1) * math.pi / 4; px, py = x + r * math.cos(a), y + r * math.sin(a) end
    local hit = false
    for _, q in ipairs(R) do
      if px >= q[1] - 1e-6 and px <= q[3] + 1e-6 and py >= q[2] - 1e-6 and py <= q[4] + 1e-6 then hit = true; break end
    end
    if not hit then return false end
  end
  return true
end

-- Whether shape `s` (a cell, or one of its footprint's shapes), reached
-- `reach` past, lies on the panel's rectangles R wherever it lies on the
-- paper (0..W, 0..top); what lies off the paper is not seen.
function M.on_panel(s, R, reach, W, top)
  local function ok(x, y, r)
    if x + r < 0 or x - r > W or y + r < 0 or y - r > top then return true end
    if x - r < 0 or x + r > W or y - r < 0 or y + r > top then
      -- Straddling the paper's edge: the part on it must lie on the panel.
      local cx, cy = math.max(0, math.min(W, x)), math.max(0, math.min(top, y))
      return on_rects(R, cx, cy, 0)
    end
    return on_rects(R, x, y, r)
  end
  if s.circle then
    local c = s.circle
    for k = 0, 7 do
      local a = k * math.pi / 4
      if not ok(c[1] + c[3] * math.cos(a), c[2] + c[3] * math.sin(a), reach) then return false end
    end
    return true
  end
  for _, v in ipairs(s.verts or {}) do
    if not ok(v[1], v[2], reach) then return false end
  end
  return true
end

-- How the ground and the fields end where the pattern ends (pattern_opts'
-- ground_edge): cells (each cell's tile, today's), dark (the same, but no
-- ground on paper), panel (one panel with a straight edge toward the
-- text), shape (inside the field each cell's tile, at its edge the cell's
-- own unit, c.shape, or nothing), inner (only the pieces whose every
-- neighbour is in the field), fade (the edge's pieces paled toward
-- the paper over the two outermost rings) and discs (a disc round every
-- cell, so the edge is rounded). Returns { panel = path } or
-- { piece = fn(k, path, colour) -> path, colour }.
function M.edge_pieces(mode, f, info)
  local pal = Paint.palette
  if mode == "panel" then return { panel = M.panel_path(f), drops = true } end
  if mode == "shape" then
    return { drops = true, piece = function(k, path, colour)
      if info.share[k] >= 1 then return path, colour end
      return k.cell.shape, colour
    end }
  end
  if mode == "inner" then
    -- Only the pieces with every neighbour in the field.
    return { drops = true, piece = function(k, path, colour)
      if info.share[k] >= 1 then return path, colour end
      return nil
    end }
  end
  if mode == "fade" then
    return { piece = function(k, path, colour)
      local d = info.depth[k] or 2
      if d >= 2 then return path, colour end
      local t = (d + 1) / 3 * (0.5 + 0.5 * info.share[k])
      return path, Paint.mix(pal.paper, colour, t)
    end }
  end
  if mode == "discs" then
    return { drops = true, piece = function(k, path, colour)
      local c = k.cell
      return { { "o", c.x, c.y, 0.62 * info.nd } }, colour
    end }
  end
  return { piece = function(_, path, colour) return path, colour end }
end

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
-- The one measure of the gaps, for everything the field paints: how far
-- `shapes`, reached `reach` past, lie from what field f keeps clear of
-- (f.keep, less that reach), and whether they keep the hero's gap (f.hero;
-- `is_hero` for the hero itself) and, under outer=margin, lie inside the
-- margin of the page (f.page). Returns that distance and that verdict.
function M.measure(shapes, reach, f, is_hero)
  local d, ok = math.huge, true
  for _, s in ipairs(shapes) do
    for _, rc in ipairs(f.keep) do d = math.min(d, M.clearance(s, rc) - reach) end
    if f.hero and not is_hero and M.disc_clearance(s, f.hero) - reach < GAP then ok = false end
    if f.outer == "margin" and not within(s, f.page, OUTER_MARGIN + reach) then ok = false end
  end
  return d, ok
end

-- The precondition for laying anything on the page: whether `shapes` of
-- the form named (cell, plate, between, piece, panel, hero) keep every gap
-- of field f by M.measure. M.paint asks it at every place it paints.
function M.lays(form, shapes, reach, f)
  local d, ok = M.measure(shapes, reach, f, form == "hero")
  return ok and d >= f.gap
end

function M.paint(spec, pt)
  local rng = Rng.new(spec.seed or 1)
  local p = Patterns.pick(rng:fork("choose pattern"), weights(spec.pattern))
  if not p then return false end
  local warning
  spec, warning = M.finish_spec(spec, p)
  if warning then
    pt.pattern_warnings = pt.pattern_warnings or {}
    table.insert(pt.pattern_warnings, warning)
    if texio and texio.write_nl then texio.write_nl("log", "flora: " .. warning) end
  end
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

  -- Prototype options (spec.pattern_opts, ORDER #9 of the geometry work;
  -- not settings): how the ground and the fields end where the pattern
  -- ends (ground_edge), and whether the cells fall away as the pattern's
  -- own units (units) or the field closes its strands at its edge
  -- (reweave). See M.edge_pieces below.
  local opts = {}
  for k, v in pairs(spec.pattern_opts or {}) do opts[k] = v end
  -- The ends and panels keys (Settings.PATTERN), each pattern's own under
  -- auto: closed lines reweave the field at its edge, whole lines fall
  -- away with their group, and kolam's panels are symmetric.
  local ends = key(spec, "ends")
  if ends == "auto" then ends = p.ends or "cut" end
  -- A pattern laid as one closed panel over its field (p.field_panel,
  -- celtic_knot) is that panel under closed and bleed: closed turns its
  -- lines back inside the paper's edges as at the text, bleed lets them run
  -- off the paper. Any other pattern reads bleed as closed.
  local field_panel
  if p.field_panel and (ends == "closed" or ends == "bleed") then
    field_panel = ends == "bleed" and "bleed" or "inset"
    ends = "panel"
  elseif ends == "bleed" then
    ends = "closed"
  end
  if opts.reweave == nil then opts.reweave = ends == "closed" end
  if opts.units == nil then opts.units = ends == "whole" end
  local panels = key(spec, "panels")
  if panels == "auto" then panels = p.panels or "off" end
  if opts.symmetric == nil then opts.symmetric = panels == "on" end
  local ground_edges = { auto = "panel", panel = "panel", motif = "shape", round = "discs", cells = "cells" }
  if opts.ground_edge == nil then opts.ground_edge = ground_edges[M.ground_mode(spec)] or "cells" end
  -- How the ground's pieces are laid, for M.footprint: the edge mode and
  -- the distance M.edge_pieces sizes a rounded piece by.
  base.ground_edge = opts.ground_edge
  -- Laid as one panel, the ground is no cell's piece (M.footprint), and
  -- everything a cell paints lies on the panel: a cell whose paint would
  -- reach past it does not stand (the panel keeps its straight edge).
  base.ground_panel = opts.ground_edge == "panel" or nil
  local panel_rects
  if base.ground and base.ground_panel and not base.lines then
    panel_rects = M.path_rects(M.panel_path({ text = text, gap = gap, side = side, W = W, top = top,
      avoid = keep_rects, hero = hero, outer = outer }))
  end
  -- The room the field has (for a layout that places its own panels in
  -- it, pat_celtic.lua's knot study): the text block, the gap kept from
  -- it, the sides the field takes, the page and its painted top, the reach
  -- of a band, what the field keeps clear of, the hero and the outer key.
  local field_room = { text = text, gap = gap, side = side, W = W, H = H, top = top, reach = width / 2,
    avoid = keep_rects, hero = hero, outer = outer }
  -- The star patterns' own choices (starfill, gapfill, alternate; Settings.PATTERN),
  -- each pattern's own under auto.
  local style = {}
  for _, k in ipairs({ "starfill", "gapfill", "alternate" }) do
    local v = key(spec, k)
    if v == "auto" then v = p[k] end
    style[k] = v
  end
  local env = { x0 = 0, y0 = 0, x1 = W, y1 = H, size = size, rng = rng:fork("cells"), opts = opts, room = field_room, style = style,
    field_panel = field_panel }
  local cells = p.cells(env)
  if base.ground and opts.ground_edge == "discs" then base.ground_nd = M.field_edges(cells, {}, {}).nd end
  local fall = rng:fork("dissolve")
  local stagger = rng:fork("growth")
  local kept, offered, bare = {}, 0, {}
  local onpage = {}
  local page = { 0, 0, W, top }
  local field = { keep = keep_rects, hero = hero, gap = gap, outer = outer, page = page }
  local function measure(shapes, reach) return M.measure(shapes, reach, field) end
  local function fits(form, shapes, reach) return M.lays(form, shapes, reach, field) end
  -- Whether each cell is placed, and the share it keeps (0 drops it).
  local function judge(c, r)
    local in_side = not side or (side.left and c.x < text.x0) or (side.right and c.x > text.x1)
    -- Paint reaches half a band and the cell's own pad beyond its outline.
    local reach = width / 2 + (c.pad or 0)
    onpage[c] = M.clearance(c, page) <= reach
    -- The gaps hold for everything the cell paints, not its outline alone.
    local shapes = M.footprint(c, base)
    local d, ok = measure(shapes, reach)
    local on_panel = true
    if panel_rects then
      for _, s in ipairs(shapes) do
        if not M.on_panel(s, panel_rects, reach, W, top) then on_panel = false end
      end
    end
    local placed = in_side and ok and on_panel
    if outer ~= "margin" then placed = placed and M.clearance(c, page) <= reach end
    -- The last value: clear of the text and the hero, on the page, on
    -- whichever side (a reweave's turns, below).
    -- The share a cell clear of the text takes where the edge mode's own
    -- choice does not decide it (a reweave's turn, below): edge=fade's
    -- paling by its distance, without the cut-off that drops the palest;
    -- every other mode paints its cells whole.
    local share = 1
    if edge == "fade" and d >= gap then share = smooth((d - gap) / ramp) end
    if not placed then
      -- Clear for everything the cell paints, as a placed cell is, and on
      -- the field's side and its panel.
      local free = in_side and on_panel and onpage[c] and dens > 0 and ok and d >= gap
      return false, 0, false, free, share
    end
    local a = 0
    -- A cell of a layout that places itself (c.fixed) is kept whenever it
    -- keeps clear of the text and the page has any density; it does not
    -- thin out toward the text.
    if c.fixed then
      local ok = dens > 0 and d >= gap
      return true, ok and 1 or 0, false, ok, 1
    end
    if dens > 0 and d >= gap then
      local t = (d - gap) / ramp
      if edge == "dissolve" then a = r < smooth(t) and 1 or 0
      elseif edge == "fade" then a = smooth(t); if a < 0.04 then a = 0 end
      else a = t >= 0.35 and 1 or 0
      end
    end
    return true, a, dens > 0 and d >= gap and edge == "dissolve", dens > 0 and d >= gap, share
  end
  local function choose(list)
    kept, offered, bare = {}, 0, {}
    -- Cells that fall away as units: one draw and one verdict per group,
    -- the group kept only when every cell of it that lies on the page
    -- would be placed, and as far as its least kept cell.
    local groups = {}
    local verdict = {}
    for _, c in ipairs(list) do
      local r, jitter = fall:next(), stagger:next()
      local placed, a, grounds = judge(c, r)
      verdict[#verdict + 1] = { c = c, placed = placed, a = a, grounds = grounds, jitter = jitter, r = r }
      if opts.units and c.group then
        local g = groups[c.group] or { r = r, a = 1, placed = true }
        groups[c.group] = g
        if onpage[c] then
          g.placed = g.placed and placed
          if placed then g.a = math.min(g.a, a) end
        end
      end
    end
    for _, v in ipairs(verdict) do
      local placed, a = v.placed, v.a
      local g = opts.units and v.c.group and groups[v.c.group]
      if g then placed, a = g.placed, g.placed and g.a or 0 end
      if placed then
        offered = offered + 1
        if a > 0 then
          kept[#kept + 1] = { cell = v.c, a = a, jitter = v.jitter }
        elseif v.grounds then
          -- A cell dissolved away still lays its piece of the ground, so the
          -- ground runs whole to the field's edge and the cells fall away
          -- over it.
          bare[#bare + 1] = { cell = v.c, a = 1, jitter = v.jitter }
        end
      end
    end
  end
  choose(cells)
  -- Reweave: the pattern is drawn again with the field's edge as its own
  -- border (pat_celtic.lua, pat_kolam.lua close their lines there), so no
  -- line ends loose; every cell of the second drawing that is placed is
  -- kept, with the share judge gives it, as any cell keeps (edge=fade
  -- pales it toward the text). A turn the edge mode would leave out takes
  -- judge's share without that choice.
  if opts.reweave and p.reweave then
    local keep = {}
    for _, k in ipairs(kept) do keep[M.cell_key(k.cell)] = k.cell end
    env.blocked = function(x, y) return not keep[M.cell_key({ x = x, y = y })] end
    -- A line turning back at the edge draws its turn in the cell beyond
    -- it. Where that cell may not be painted (too near the text) the kept
    -- cells round it are walled in as well and the field is drawn again,
    -- until every cell of the drawing on the page may be painted.
    local list
    for _ = 1, 6 do
      -- The same draws as the first drawing, so only the edge changes.
      env.rng = rng:fork("cells")
      cells = p.cells(env)
      list = {}
      local failed = {}
      for _, c in ipairs(cells) do
        -- A turn may lie where the edge mode would leave no cell (edge=cell's
        -- margin): it is painted so long as it keeps clear of the text.
        local placed, a, _, clear, share = judge(c, 0)
        if placed and a > 0 then list[#list + 1] = { c = c, a = a }
        elseif clear then list[#list + 1] = { c = c, a = share, turn = true }
        elseif onpage[c] then
          failed[#failed + 1] = c
        end
      end
      if #failed == 0 then break end
      local r2 = (0.75 * size) ^ 2
      for key, o in pairs(keep) do
        for _, c in ipairs(failed) do
          if (o.x - c.x) ^ 2 + (o.y - c.y) ^ 2 < r2 then keep[key] = nil; break end
        end
      end
    end
    kept, offered, bare = {}, #list, {}
    for _, v in ipairs(list) do kept[#kept + 1] = { cell = v.c, a = v.a, turn = v.turn, jitter = stagger:next() } end
  end

  -- Growth starts at the page's outer edge, away from the text. A cell
  -- whose centre lies off the page (outer=bleed) starts with the edge,
  -- not before it, so no cell is born before the growth begins.
  local function root(c)
    if side and side.left and c.x < text.x0 then return math.max(0, c.x) end
    if side and side.right and c.x > text.x1 then return math.max(0, W - c.x) end
    return math.max(0, math.min(c.x, c.y, W - c.x, H - c.y))
  end
  -- Growth time runs over every cell that paints: the kept ones and,
  -- under a ground, the dissolved ones that lay only their piece of it.
  local grounded = {}
  for _, k in ipairs(kept) do grounded[#grounded + 1] = k end
  if base.ground then for _, k in ipairs(bare) do grounded[#grounded + 1] = k end end
  local far = 1e-6
  for _, k in ipairs(grounded) do far = math.max(far, root(k.cell)) end

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
  -- Nothing is laid that does not keep the gaps itself (fits), whatever
  -- laid the cells round it: a plate, a piece of the ground, the ground's
  -- panel and a plate between cells alike, each subpath as painted (filled,
  -- and stroked 0.6 wide). One that does not is left out, and the paper
  -- (or what lies under it) shows there.
  local PLATE_REACH = 0.3
  local function plate(c, k, path, colour, form)
    if not fits(form, subpath_shapes(path), PLATE_REACH) then return false end
    local function draw() lit(function() pt:fill(path, colour, 1); pt:stroke(path, colour, 0.6, 1) end) end
    if grow then
      if grow >= k.painted then draw() end
    else
      Progression.part(pt, "pattern_ground", { c.x, c.y }, k.painted, BAND, draw, nil, { no_area = true })
    end
  end
  local holes = 0
  local ge = opts.ground_edge or "cells"
  -- A1 (a prototype's dark): the ground only on a dark backdrop.
  if ge == "dark" and not pt.backdrop then base.ground = nil end
  -- The field's edge is measured only where something follows it.
  local need = base.ground or opts.measure
  if not need and not base.lines then
    for _, k in ipairs(kept) do if k.cell.plates then need = true break end end
  end
  local edgeinfo = need and M.field_edges(cells, grounded, onpage) or { share = {}, depth = {}, isolated = 0, edge = 0, nd = size }
  local fr = { text = text, gap = gap, side = side, W = W, top = top, ramp = ramp, avoid = keep_rects, hero = hero, outer = outer }
  local pieces = M.edge_pieces(ge, fr, edgeinfo)
  if base.ground then
    local K = require("flora.pat_kit")
    if pieces.panel then
      -- The panel lies under the pattern's cells; with none (density=0)
      -- there is no pattern, and no panel.
      local first = grounded[1] or { cell = { x = 0, y = 0 }, painted = 0 }
      if #grounded > 0 then plate(first.cell, first, pieces.panel, M.cell_inks(base, 1).ground, "panel") end
    else
      for _, k in ipairs(grounded) do
        local c = k.cell
        local under, colour = pieces.piece(k, c.under or (c.tile and K.path(c.tile)), M.cell_inks(base, k.a).ground)
        if under then plate(c, k, under, colour, "piece")
        elseif not c.rests and not pieces.drops then holes = holes + 1 end
      end
    end
  end
  -- A cell's plates: fields that tile the plane, painted with the ground.
  -- They belong to the kept cells only, so their edge is the kept cells',
  -- whatever the ground does.
  if not base.lines then
    -- A plate that lies between cells (pl.between, their positions) is
    -- laid only when every one of them is kept, so the field ends along
    -- the cells' own outline rather than in squares.
    local keptat = {}
    for _, k in ipairs(kept) do keptat[M.cell_key(k.cell)] = true end
    local function between_ok(pl)
      if not pl.between then return true end
      local n = 0
      for _, q in ipairs(pl.between) do
        if keptat[M.cell_key({ x = q[1], y = q[2] })] then n = n + 1 end
      end
      return n == #pl.between
    end
    for _, k in ipairs(kept) do
      for _, pl in ipairs(k.cell.plates or {}) do
        local ik = M.cell_inks(base, k.a)
        local colour = pl[2] == "accent" and ik.accent or ik.fill[pl[2] == "b" and 2 or 1]
        if between_ok(pl) then plate(k.cell, k, pl[1], colour, pl.between and "between" or "plate") end
      end
    end
  end
  for _, k in ipairs(kept) do
    local c, ink = k.cell, band_ink(M.cell_inks(base, k.a), p, spec, k_scale)
    local birth, painted = k.birth, k.painted
    -- The same precondition for the cell itself, its outline and what it
    -- lays (M.footprint), as judge placed it.
    if not fits("cell", M.footprint(c, base), width / 2 + (c.pad or 0)) then
      -- Left out. judge keeps no such cell; this holds should it ever.
      pt.pattern_unfit = (pt.pattern_unfit or 0) + 1
    elseif grow then
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
  if hero and fits("hero", { { circle = hero } }, 0) then
    M.paint_hero(pt, hero, band_ink(M.cell_inks(base, 1, true), p, spec, k_scale), grow)
  end
  if edge == "guilloche" and (not grow or grow >= 0.1) then
    local ink = band_ink(M.cell_inks(base, 1, true), p, spec, k_scale)
    Progression.part(pt, "pattern_border", { text.x0, text.y0 }, 0, 0.2, function()
      require("flora.pattern_hero").paint_band(pt, text, gap / 2, 4, ink)
    end)
  end
  if edge == "border" and (not grow or grow >= 0.1) then
    local ink = M.cell_inks(base, 1, true)
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
    -- Every cell of the drawing, kept or not, and which lie on the page
    -- (for tests/pattern_matrix.lua's holes).
    all = cells, onpage = onpage, warnings = pt.pattern_warnings,
    -- Cells that should lay a piece of the ground and have none.
    holes = holes, grounded = base.ground and #grounded or 0,
    -- Kept cells left out at painting for not keeping their gaps (none,
    -- tests/test_pattern_protect.lua).
    unfit = pt.pattern_unfit or 0,
    -- The field's edge (M.field_edges): cells with no grounded neighbour, and
    -- at the edge.
    isolated = edgeinfo.isolated, edge_cells = edgeinfo.edge }
  -- For measuring (pattern_opts.measure): the kept cells' own edge.
  if opts.measure then
    local ki = M.field_edges(cells, kept, onpage)
    pt.pattern.isolated, pt.pattern.edge_cells = ki.isolated, ki.edge
  end
  return true
end

return M
