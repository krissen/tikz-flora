-- Flora round the paper's edge: pages for measuring where layout=perimeter
-- and surround put their flora, and prototypes of flora laid in a band of
-- chosen width (ALTS below), for the sheets tools/frame_flora.py makes.
-- The prototypes live here only: nothing in lua/flora/ calls them, and the
-- layouts' own output is unchanged (they swap Frames.of while one of their
-- pages is painted).
--
--   texlua tools/frame_flora.lua OUTDIR SET [SEEDS]
--
-- SET is one of the sets in SETS (measure, alts, widths, papers, band,
-- margins). SEEDS (default 11) is a comma-separated list of seeds. Writes
-- OUTDIR/<page>.pdf for each page and OUTDIR/pages.tsv, one line a page:
-- its sheet row and column labels, the paper (pt), the text block, the
-- frame title's and the reservation's boxes, the band asked (mm) and laid
-- (pt), the seed, the md5 of the body and the seconds it took.
--
-- The pages are tests/pattern_perimeter.lua's (M.spec): the text block the
-- band + 4 mm in from every edge, or given margins; with a title, a frame
-- title in the block's top 16 pt, the theme's 20 pt top inset and header
-- clip, and a reservation in the top band's right half.

package.path = "./lua/?.lua;" .. package.path
require("flora.tune").gilt_dpi = 100

local B = dofile("tests/pattern_perimeter.lua")
local Compose = require("flora.compose")
local Frames = require("flora.frames")
local Paint = require("flora.paint")
local Pdf = require("flora.pdfout")

local MM = 72 / 25.4
-- LuaTeX's md5 library, a global there (.luals/luatex.lua declares it).
local md5 = rawget(_G, "md5")

-- ------------------------------------------------------------------
-- Pages

-- The page for paper `paper` (B.PAPERS's form), a band `wmm` mm wide, with
-- or without a title, `margins` in mm (left, right, foot, top) or nil.
local function page(paper, wmm, titled, margins)
  local spec = B.spec(nil, wmm, paper, false, "light", margins)
  spec.pattern = nil
  if not titled then
    spec.lines, spec.header_y, spec.header, spec.frametitle, spec.frametitle_height = nil, nil, nil, nil, nil
    spec.top_inset, spec.tune, spec.reserve = 0, nil, {}
  end
  return spec
end

local function paper_of(name)
  for _, p in ipairs(B.PAPERS) do if p[1] == name then return p end end
  error("no paper " .. name)
end

-- ------------------------------------------------------------------
-- Frames for the prototypes. Each plant grows in a virtual frame in which
-- the band is V pt wide, as a slide's margin is, and the frame is scaled
-- down to the band: the plant keeps its proportions at every width.

local V = 70
local EDGE, GUTTER = 6, 4

local function invert(m) return Frames.invert(m) end

local function map_box(m, bx)
  local ax, ay = Frames.apply(m, bx.x0, bx.y0)
  local cx, cy = Frames.apply(m, bx.x1, bx.y1)
  return { x0 = math.min(ax, cx), y0 = math.min(ay, cy), x1 = math.max(ax, cx), y1 = math.max(ay, cy) }
end

local function clip(bx, w, h)
  local c = { x0 = math.max(0, bx.x0), y0 = math.max(0, bx.y0), x1 = math.min(w, bx.x1), y1 = math.min(h, bx.y1) }
  if c.x1 <= c.x0 or c.y1 <= c.y0 then return nil end
  return c
end

local function copy(t)
  local s = {}
  for k, v in pairs(t) do s[k] = v end
  return s
end

-- The parts of a frame spec every prototype sets: its size, text block and
-- reservations, no header, no lines, framing only.
local function base(spec, w, h, text, reserve, opts)
  local s = copy(spec)
  s.width, s.height, s.text, s.lines, s.reserve = w, h, text, nil, reserve
  s.header, s.header_y, s.body_top, s.top_inset, s.frametitle = "margin", nil, nil, 0, nil
  s.layout, s.frame_only = nil, true
  s.edge, s.gutter = opts.edge or EDGE, GUTTER
  s.seed = opts.seed or spec.seed
  if opts.density then
    s.mix = copy(spec.mix or {})
    s.mix.density = (s.mix.density or 1) * opts.density
  end
  if opts.tune then s.tune = opts.tune end
  return s
end

-- An affine frame (matrix m, frame to page) of size w x h whose text block
-- is the page box `block` carried in.
local function affine(spec, m, w, h, block, opts)
  local inv = invert(m)
  local text = clip(map_box(inv, block), w, h)
  if not text then return nil end
  local res = {}
  for _, r in ipairs(spec.reserve or {}) do
    local b = clip(map_box(inv, { x0 = r[1], y0 = r[2], x1 = r[3], y1 = r[4] }), w, h)
    if b then res[#res + 1] = { b.x0, b.y0, b.x1, b.y1 } end
  end
  local s = base(spec, w, h, text, res, opts)
  s.closed = opts.closed
  return { spec = s, map = m, fn = function(x, y) return Frames.apply(m, x, y) end, label = opts.label }
end

-- A bare frame (no foot, no corner: frames.lua's curved frames) along a
-- path, mapped by fn and back by inv, w x h, its text block from x = xi in.
local function bare(spec, fn, inv, w, h, xi, opts)
  local res = {}
  for _, r in ipairs(spec.reserve or {}) do
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for i = 0, 8 do
      for j = 0, 8 do
        local x, y = inv(r[1] + (r[3] - r[1]) * i / 8, r[2] + (r[4] - r[2]) * j / 8)
        x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
      end
    end
    local b = clip({ x0 = x0, y0 = y0, x1 = x1, y1 = y1 }, w, h)
    if b and y1 - y0 < h / 2 then res[#res + 1] = { b.x0, b.y0, b.x1, b.y1 } end
  end
  local s = base(spec, w, h, { x0 = xi, y0 = 0, x1 = w, y1 = h }, res, opts)
  s.bare = true
  return { spec = s, fn = fn, inv = inv, label = opts.label }
end

-- A path round the page at the band's centre line: a rectangle with
-- corners rounded to radius rc, walked clockwise from the foot's centre
-- (as oval.lua walks its oval), with maps for a bare frame laid along it.
local Loop = {}
Loop.__index = Loop

local function loop(x0, y0, x1, y1, rc)
  local o = setmetatable({ x0 = x0, y0 = y0, x1 = x1, y1 = y1, rc = rc, segs = {} }, Loop)
  local pi = math.pi
  local cx0, cy0, cx1, cy1 = x0 + rc, y0 + rc, x1 - rc, y1 - rc
  local function line(ax, ay, bx, by)
    local l = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    local tx, ty = (bx - ax) / l, (by - ay) / l
    o.segs[#o.segs + 1] = { len = l, at = function(u) return ax + tx * u, ay + ty * u, ty, -tx end }
  end
  local function arc(cx, cy, a0)
    -- A quarter turned clockwise from angle a0 about (cx, cy).
    o.segs[#o.segs + 1] = { len = rc * pi / 2, cx = cx, cy = cy, at = function(u)
      local a = a0 - u / rc
      return cx + rc * math.cos(a), cy + rc * math.sin(a), -math.cos(a), -math.sin(a)
    end }
  end
  local mx = (x0 + x1) / 2
  line(mx, y0, cx0, y0)
  arc(cx0, cy0, -pi / 2)
  line(x0, cy0, x0, cy1)
  arc(cx0, cy1, pi)
  line(cx0, y1, cx1, y1)
  arc(cx1, cy1, pi / 2)
  line(x1, cy1, x1, cy0)
  arc(cx1, cy0, 0)
  line(cx1, y0, mx, y0)
  local s = 0
  for _, g in ipairs(o.segs) do g.s0 = s; s = s + g.len end
  o.len = s
  return o
end

-- The point and inward normal at arclength s.
function Loop:at(s)
  s = s % self.len
  for _, g in ipairs(self.segs) do
    if s <= g.s0 + g.len then return g.at(s - g.s0) end
  end
  return self.segs[#self.segs].at(self.segs[#self.segs].len)
end

-- The arclength of the path point nearest (px, py), and that point's
-- signed distance inward.
function Loop:nearest(px, py)
  local best, bs, bd = math.huge, 0, 0
  for _, g in ipairs(self.segs) do
    local u
    if g.cx then
      local a = math.atan(py - g.cy, px - g.cx)
      -- The arc's own range of u, clamped.
      local _, _, nx, ny = g.at(0)
      local a0 = math.atan(-ny, -nx)
      local du = ((a0 - a) % (2 * math.pi))
      if du > math.pi * 1.25 then du = du - 2 * math.pi end
      u = math.max(0, math.min(g.len, du * self.rc))
    else
      local ax, ay = g.at(0)
      local bx, by = g.at(g.len)
      local tx, ty = (bx - ax) / g.len, (by - ay) / g.len
      u = math.max(0, math.min(g.len, (px - ax) * tx + (py - ay) * ty))
    end
    local x, y, nx, ny = g.at(u)
    local d2 = (px - x) ^ 2 + (py - y) ^ 2
    if d2 < best then best, bs, bd = d2, g.s0 + u, (px - x) * nx + (py - y) * ny end
  end
  return bs, bd
end

-- Maps for a frame along the loop scaled by k: frame (x, y) lies at
-- arclength s0 + k y, k (x - xc) inward; mirrored about the loop's
-- vertical axis for the right-hand plant.
function Loop:maps(s0, xc, k, mirror)
  local mx = (self.x0 + self.x1) / 2
  local function fn(x, y)
    local px, py, nx, ny = self:at(s0 + k * y)
    local d = k * (x - xc)
    px, py = px + nx * d, py + ny * d
    if mirror then px = 2 * mx - px end
    return px, py
  end
  local function inv(px, py)
    if mirror then px = 2 * mx - px end
    local s, d = self:nearest(px, py)
    if s > self.len * 0.75 then s = s - self.len end
    return xc + d / k, (s - s0) / k
  end
  return fn, inv
end

-- ------------------------------------------------------------------
-- The prototypes. Each takes the page spec, the band's inner rectangle I
-- (x0, y0, x1, y1 as a box) and its laid width w (pt), and returns frames
-- for compose.lua, and optionally a function that finishes the painter.

local ALTS = {}
local ALT_ORDER = { "wreath", "vine", "corners", "cut" }
ALTS.label = {
  wreath = "A  wreath in the band",
  vine = "B  running vine",
  corners = "C  corners and vine",
  cut = "D  dense band, cut",
}

local function seed_of(spec, k) return (tonumber(spec.seed) or 1) * 31 + k * 7907 end

-- The pinwheel of surround (frames.lua), each plant in a frame scaled so
-- that the band is its margin: the first up the left and along the foot,
-- the second, turned half a circle, down the right and along the top. With
-- `over` the plants' margin reaches over x the band, and `opts` passes on.
local function pinwheel(spec, _, w, over, opts)
  local W, H = spec.width, spec.height
  local k = w / V
  local fw, fh = W / k, H / k
  -- The plants' text block: the band's inner rectangle, or one `over`
  -- times as far in.
  local d = w * (over or 1)
  local block = { x0 = d, y0 = d, x1 = W - d, y1 = H - d }
  local fs = {}
  for i, m in ipairs({ { k, 0, 0, k, 0, 0 }, { -k, 0, 0, -k, W, H } }) do
    local o = copy(opts or {})
    o.label, o.seed = i == 1 and "left" or "right", i == 2 and seed_of(spec, 2) or nil
    local f = affine(spec, m, fw, fh, block, o)
    if f then
      local ft = f.spec.text
      f.spec.closed = { { ft.x1, ft.y0 - 6, fw, fh }, { 0, ft.y1 + 4, fw, fh } }
      fs[#fs + 1] = f
    end
  end
  return fs
end

-- A: today's wreath, with the plant scaled to the band and its stems in
-- the band's middle.
function ALTS.wreath(spec, I, w)
  return pinwheel(spec, I, w, 1, { tune = { gesture = { edge = 0.42 } } })
end

-- B: one vine round all four sides along the band's centre line, its
-- corners rounded: two plants rooted at the foot's centre, each round one
-- half to the top's centre, where their heroes meet.
function ALTS.vine(spec, _, w)
  local W, H = spec.width, spec.height
  local k = w / V
  local c = w / 2
  local lp = loop(c, c, W - c, H - c, w)
  local xc = V / 2
  local fs = {}
  local s0 = -(EDGE + 10) * k
  local s1 = lp.len / 2 - 8 * k
  for i, side in ipairs({ "left", "right" }) do
    local fn, inv = lp:maps(s0, xc, k, side == "right")
    fs[#fs + 1] = bare(spec, fn, inv, V + 40, (s1 - s0) / k, V,
      { label = side, seed = i == 2 and seed_of(spec, 2) or nil, edge = EDGE })
  end
  return fs
end

-- C: a full plant in each corner, its two arms along the two sides, and a
-- sparse vine with a small bloom between them; turned a quarter at each
-- corner, so the four go round as a pinwheel.
function ALTS.corners(spec, I, w)
  local W, H = spec.width, spec.height
  local k = w / V
  local arm = 0.3
  local fs = {}
  -- Corner k's frame: origin at the corner, x inward from the side its
  -- column runs along, y along that side clockwise from the corner.
  local corners = {
    { m = { k, 0, 0, k, 0, 0 }, col = H, foot = W },        -- foot-left: up the left
    { m = { 0, -k, k, 0, 0, H }, col = W, foot = H },       -- top-left: right along the top
    { m = { -k, 0, 0, -k, W, H }, col = H, foot = W },      -- top-right: down the right
    { m = { 0, k, -k, 0, W, 0 }, col = W, foot = H },       -- foot-right: left along the foot
  }
  local block = { x0 = I.x0, y0 = I.y0, x1 = I.x1, y1 = I.y1 }
  for i, c in ipairs(corners) do
    local fw, fh = c.foot * arm / k, c.col * arm / k
    local f = affine(spec, c.m, fw, fh, block, { label = "corner " .. i, seed = seed_of(spec, i) })
    if f then fs[#fs + 1] = f end
  end
  -- The vine along each side's middle, between the corners' arms.
  local rails = {
    { m = { k, 0, 0, k, 0, 0 }, from = H * arm, to = H * (1 - arm) },
    { m = { 0, -k, k, 0, 0, H }, from = W * arm, to = W * (1 - arm) },
    { m = { -k, 0, 0, -k, W, H }, from = H * arm, to = H * (1 - arm) },
    { m = { 0, k, -k, 0, W, 0 }, from = W * arm, to = W * (1 - arm) },
  }
  local small = { compose = { hero_min = 9, hero_max = 12 } }
  for i, r in ipairs(rails) do
    if r.to - r.from > 2 * w then
      local m = r.m
      local y0 = r.from / k
      local h = (r.to - r.from) / k
      local mm = { m[1], m[2], m[3], m[4], m[3] * y0 + m[5], m[4] * y0 + m[6] }
      local inv = invert(mm)
      fs[#fs + 1] = bare(spec, function(x, y) return Frames.apply(mm, x, y) end,
        function(x, y) return Frames.apply(inv, x, y) end, V + 40, h, V,
        { label = "rail " .. i, seed = seed_of(spec, 10 + i), density = 0.35, tune = small })
    end
  end
  return fs
end

-- D: the band filled densely by the pinwheel's plants grown half as far
-- again into the margin and off the paper's edge, then cut along the
-- band's inner edge, with a rule there, as a pattern band's edge=border.
function ALTS.cut(spec, I, w)
  local fs = pinwheel(spec, I, w, 1.5, { edge = 0.5, density = 1.6, tune = { gesture = { edge = 0.3 } } })
  local W, H = spec.width, spec.height
  local function finish(pt)
    local q = Paint.new({ backend = "pdf" })
    q:clip_begin({
      { "m", 0, 0 }, { "l", W, 0 }, { "l", W, H }, { "l", 0, H }, { "z" },
      { "m", I.x0, I.y0 }, { "l", I.x0, I.y1 }, { "l", I.x1, I.y1 }, { "l", I.x1, I.y0 }, { "z" },
    })
    table.insert(pt.out, 1, q.out[1])
    pt.out[#pt.out + 1] = "Q"
    pt:stroke({ { "m", I.x0, I.y0 }, { "l", I.x1, I.y0 }, { "l", I.x1, I.y1 }, { "l", I.x0, I.y1 }, { "z" } },
      Paint.palette.gold or { 0.7, 0.55, 0.2 }, 0.8, 1)
  end
  return fs, finish
end

-- Sets t[k] to v and returns what it was: the prototypes stand in for a
-- module's function while a page is painted.
local function swap(t, k, v)
  local was = t[k]
  t[k] = v
  return was
end

-- Paints `spec` with alternative `name`: Frames.of gives the prototype's
-- frames while the page is painted.
local function paint_alt(spec, name)
  local _, w = B.inner(spec, (spec.perimeter_width or 12) * MM)
  local I = { x0 = w, y0 = w, x1 = spec.width - w, y1 = spec.height - w }
  local fs, finish = ALTS[name](spec, I, w)
  -- As a pattern's band (compose.lua's banded pages): the band runs to the
  -- paper's top, past the top inset and the header clip; the frame title
  -- lies in the text block, which the band keeps clear of.
  spec.layout, spec.top_inset, spec.header_y, spec.frametitle = "surround", 0, nil, nil
  local of = swap(Frames, "of", function() return fs end)
  local ok, pt = pcall(Compose.page, spec)
  swap(Frames, "of", of)
  if not ok then error(pt, 0) end
  if finish then finish(pt) end
  return pt, w
end

-- ------------------------------------------------------------------
-- Sets

-- A page to render: { row, col, paper, wmm, titled, margins, kind } where
-- kind is a layout (perimeter, surround), "band:<pattern>" or "alt:<name>".
local function item(row, col, paper, wmm, titled, kind, margins)
  return { row = row, col = col, paper = paper_of(paper), wmm = wmm, titled = titled, kind = kind, margins = margins }
end

local SETS = {}

-- Today's layout=perimeter and surround with flora: three papers, three
-- widths, with and without a title; and the band asked under fixed margins.
function SETS.measure()
  local out = {}
  for _, kind in ipairs({ "perimeter", "surround" }) do
    for _, p in ipairs(B.PAPERS) do
      for _, wmm in ipairs(B.WIDTHS) do
        for _, titled in ipairs({ true, false }) do
          out[#out + 1] = item(string.format("%s %s", kind, p[1]), string.format("%d mm%s", wmm, titled and " title" or ""), p[1], wmm, titled, kind)
        end
      end
    end
  end
  -- The control: margins held at 20 mm while the band asked changes. A
  -- layout that follows the band paints these three differently.
  for _, wmm in ipairs(B.WIDTHS) do
    out[#out + 1] = item("perimeter 16:9, margins 20 mm", wmm .. " mm", "16:9", wmm, false, "perimeter", { 20, 20, 20, 20 })
  end
  return out
end

-- (1) The prototypes side by side, 16:9 with a title, 12 mm, beside today's.
function SETS.alts()
  local out = { item("16:9, 12 mm, title", "today (perimeter)", "16:9", 12, true, "perimeter") }
  for _, a in ipairs(ALT_ORDER) do out[#out + 1] = item("16:9, 12 mm, title", ALTS.label[a], "16:9", 12, true, "alt:" .. a) end
  return out
end

-- (2) Each prototype at 8, 12 and 18 mm.
function SETS.widths()
  local out = {}
  for _, a in ipairs(ALT_ORDER) do
    for _, wmm in ipairs(B.WIDTHS) do out[#out + 1] = item(ALTS.label[a], wmm .. " mm", "16:9", wmm, true, "alt:" .. a) end
  end
  return out
end

-- (3) Each prototype on 4:3 and A4.
function SETS.papers()
  local out = {}
  for _, a in ipairs(ALT_ORDER) do
    for _, p in ipairs({ "4:3", "A4" }) do out[#out + 1] = item(ALTS.label[a], p .. ", 12 mm", p, 12, true, "alt:" .. a) end
  end
  return out
end

-- (4) Each prototype beside the pattern band (kikko) at the same width.
function SETS.band()
  local out = {}
  for _, a in ipairs(ALT_ORDER) do
    out[#out + 1] = item(ALTS.label[a], "flora", "16:9", 12, true, "alt:" .. a)
    out[#out + 1] = item(ALTS.label[a], "kikko", "16:9", 12, true, "band:kikko")
  end
  return out
end

-- (5) Margins of 25/10/8/12 mm round a 12 mm band, which narrows to the
-- foot's margin less the gap: the same all round.
function SETS.margins()
  local m = { 25, 10, 8, 12 }
  local out = {
    item("margins 25/10/8/12, 12 mm asked", "today (perimeter)", "16:9", 12, true, "perimeter", m),
    item("margins 25/10/8/12, 12 mm asked", "kikko", "16:9", 12, true, "band:kikko", m),
  }
  for _, a in ipairs(ALT_ORDER) do out[#out + 1] = item("margins 25/10/8/12, 12 mm asked", ALTS.label[a], "16:9", 12, true, "alt:" .. a, m) end
  return out
end

-- ------------------------------------------------------------------

local outdir, setname, seeds_arg = arg[1], arg[2], arg[3]
if not (outdir and setname) or not SETS[setname] then
  local names = {}
  for k in pairs(SETS) do names[#names + 1] = k end
  table.sort(names)
  io.stderr:write("usage: texlua tools/frame_flora.lua OUTDIR SET [SEEDS]; SET is one of " .. table.concat(names, ", ") .. "\n")
  os.exit(2)
end
local seeds = {}
for s in (seeds_arg or "11"):gmatch("[^,]+") do seeds[#seeds + 1] = assert(tonumber(s), "a seed must be a number: " .. s) end

local tsv = assert(io.open(outdir .. "/pages.tsv", "w"))
local cols = { "file", "row", "col", "kind", "paper", "W", "H", "tx0", "ty0", "tx1", "ty1", "title", "reserve", "band_mm", "band_pt", "seed", "md5", "secs" }
tsv:write(table.concat(cols, "\t"), "\n")
local function box(b) return b and string.format("%.2f,%.2f,%.2f,%.2f", b[1], b[2], b[3], b[4]) or "" end
local n = 0
for _, it in ipairs(SETS[setname]()) do
  for _, seed in ipairs(seeds) do
    n = n + 1
    local spec
    local pattern = it.kind:match("^band:(.+)$")
    if pattern then
      spec = B.spec(pattern, it.wmm, it.paper, false, "light", it.margins)
      if not it.titled then spec.frametitle, spec.lines, spec.header_y, spec.header, spec.reserve = nil, nil, nil, nil, {} end
    else
      spec = page(it.paper, it.wmm, it.titled, it.margins)
    end
    spec.seed = seed
    local t = { spec.text.x0, spec.text.y0, spec.text.x1, spec.text.y1 }
    local title = it.titled and spec.lines and spec.lines[1]
    local reserve = spec.reserve and spec.reserve[1]
    local t0 = os.clock()
    Paint.reset_resources()
    local pt, laid
    local alt = it.kind:match("^alt:(.+)$")
    if alt then
      pt, laid = paint_alt(spec, alt)
    else
      if not pattern then spec.layout = it.kind end
      pt = Compose.page(spec)
      local _, w = B.inner(spec, it.wmm * MM)
      laid = w
    end
    local secs = os.clock() - t0
    local file = string.format("p%03d", n)
    Pdf.write(outdir .. "/" .. file .. ".pdf", pt, spec.width, spec.height)
    tsv:write(table.concat({ file, it.row, it.col, it.kind, it.paper[1], string.format("%.3f", spec.width), string.format("%.3f", spec.height),
      string.format("%.3f", t[1]), string.format("%.3f", t[2]), string.format("%.3f", t[3]), string.format("%.3f", t[4]),
      title and box({ title.x0, title.y0, title.x1, title.y1 }) or "", box(reserve), tostring(it.wmm), string.format("%.3f", laid),
      tostring(seed), md5.sumhexa(pt:body()), string.format("%.2f", secs) }, "\t"), "\n")
    io.stderr:write(string.format("frame_flora: %s %s | %s | seed %d: %.1f s\n", file, it.row, it.col, seed, secs))
  end
end
tsv:close()
