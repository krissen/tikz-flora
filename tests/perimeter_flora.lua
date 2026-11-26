-- Flora in the perimeter band (frames.lua's M.vine, compose.lua's
-- C.flora_band): the invariants every page holds, checked on the painter's
-- output. The plants are cut to the band by a clip, so what they paint is
-- what lies inside it: the checks read the clip and the paint inside it.
-- M.run sweeps papers x band widths x frame title x backdrop, each cell
-- with a seed and an edge (none or border) dealt in turn, and the narrow
-- pages, and returns the cells swept and every failure, named by its
-- invariant:
--
--   narrow  a band under M.NARROWEST (6) mm has no flora and says so
--           once in the log; a wider one has flora
--   width   the band is the paper less the pattern band's inner rectangle
--           (tests/pattern_perimeter.lua's M.inner: as wide on every side,
--           narrowed alike to the narrowest margin), and the clip is that
--   band    every plant's paint lies inside that clip: nothing is painted
--           outside it but the clips round it and the rule
--   text    the clip's inner rectangle holds the text block and its gap,
--           and every reservation is cut out of the page
--   sides   each of the four sides has paint inside the band, the top
--           under a frame title included, and nothing but the
--           reservations' clips cuts the band
--   rule    edge=border draws a rule along the inner rectangle; no other
--           edge does
--   density each density is laid as asked, or in a band too narrow for it
--           as the next denser one the band holds, said once in the log
--   frames  the form is laid with all its frames (vine 2, pinwheel 2,
--           corners 8), or, where corners has no room for its arms, as the
--           vine, saying so once in the log: no frame is left out silently
--   mark    no frame of the page carries a running head, so it has no mark
--
-- Sizes are as users give them: papers and bands in mm.

package.path = "./lua/?.lua;" .. package.path
local Compose = require("flora.compose")
local Paint = require("flora.paint")

local M = {}
local B = dofile("tests/pattern_perimeter.lua")
-- The painter's own clip, taken before any test replaces it, for the clips
-- the page should hold.
local clip_begin = getmetatable(Paint.new({ backend = "pdf" })).__index.clip_begin
-- The narrowest band flora is laid in, mm: the test's own number, not the
-- engine's (band.lua's FLORA_NARROWEST), so that a change to that one shows.
M.NARROWEST = 6
local MM = 72 / 25.4
local BP = 72 / 72.27
local GAP = 6

M.PAPERS = B.PAPERS
M.WIDTHS = { 6, 8, 12, 18 }
M.SEEDS = { 1, 2, 3 }
M.EDGES = { false, "border" }
-- The densities (band.lua's perimeterdensity) and, the test's own numbers,
-- the narrowest band in mm each is laid in; a narrower band takes the
-- next denser one.
M.DENSITIES = { "dense", "open", "sparse" }
-- The forms (perimeterflora), dealt over the cells as the densities are.
M.FORMS = { "vine", "pinwheel", "corners" }
M.DENSITY_NARROWEST = { dense = 6, open = 7, sparse = 9 }
-- The frames each form lays, and, the test's own number like the others,
-- the least an arm of corners is in bands: a band over the paper's shorter
-- side less than twice that is too wide for corners, which is laid as the
-- vine.
M.FRAMES = { vine = 2, pinwheel = 2, corners = 8 }
M.CORNER_ROOM = 1.25
M.BACKDROPS = { "light", "dark" }
-- Pages whose band is too narrow for flora: 5 mm asked, and 12 mm asked in
-- a slide theme's margins (25/10/8/12 mm), which narrow it to 4.8 mm.
M.NARROW = {
  { "16:9, 5 mm", B.PAPERS[1], 5, nil },
  { "16:9, 12 mm in margins 25/10/8/12", B.PAPERS[1], 12, { 25, 10, 8, 12 } },
}

-- The page: tests/pattern_perimeter.lua's, with flora and no pattern;
-- without a title, no frame title, running head, inset or reservation.
function M.spec(wmm, paper, titled, backdrop, seed, edge, margins)
  local spec = B.spec(nil, wmm, paper, edge, backdrop, margins)
  spec.pattern, spec.seed = nil, seed
  if not titled then
    spec.lines, spec.header_y, spec.header, spec.frametitle, spec.frametitle_height = nil, nil, nil, nil, nil
    spec.top_inset, spec.tune, spec.reserve = 0, nil, {}
  end
  return spec
end

-- The clip a painter writes for the band: the paper with rectangle I
-- reversed inside it.
local function ring_clip(W, H, I)
  local q = Paint.new({ backend = "pdf" })
  clip_begin(q, {
    { "m", 0, 0 }, { "l", W, 0 }, { "l", W, H }, { "l", 0, H }, { "z" },
    { "m", I[1], I[2] }, { "l", I[1], I[4] }, { "l", I[3], I[4] }, { "l", I[3], I[2] }, { "z" },
  })
  return q.out[1]
end
M.ring_clip = ring_clip

-- Whether an output chunk paints (fills, strokes, shades or places an
-- image) rather than only clipping or saving and restoring state.
local function paints(chunk)
  local s = " " .. chunk:gsub("\n", " ") .. " "
  return s:find(" [fFsSbB]%*? ") ~= nil or s:find(" sh ", 1, true) ~= nil or s:find(" Do ", 1, true) ~= nil
end

-- The path points (pt) in an output chunk.
local function points(chunk, out)
  for line in chunk:gmatch("[^\n]+") do
    for a, b in line:gmatch("(-?[%d.]+) (-?[%d.]+) [mlc]") do out[#out + 1] = { tonumber(a) / BP, tonumber(b) / BP } end
    for a, b in line:gmatch("(-?[%d.]+) (-?[%d.]+) %-?[%d.]+ %-?[%d.]+ %-?[%d.]+ %-?[%d.]+ c") do
      out[#out + 1] = { tonumber(a) / BP, tonumber(b) / BP }
    end
  end
end

-- Checks one page; returns its failures as { invariant, text }.
function M.check(spec, wmm)
  local fails = {}
  local function fail(inv, msg) fails[#fails + 1] = { inv, msg } end
  local W, H = spec.width, spec.height
  local Iw, we = B.inner(spec, wmm * MM)
  Paint.reset_resources()
  local pt = Compose.page(spec)
  local frames = pt.frames or {}
  local b = pt.perimeter_flora
  local warned = 0
  for _, w in ipairs(pt.pattern_warnings or {}) do
    if w:find("narrower than the", 1, true) and w:find("flora is laid in", 1, true) then warned = warned + 1 end
  end
  -- narrow
  local narrow = we < M.NARROWEST * MM - 1e-6
  if narrow then
    if b then fail("narrow", string.format("a %.1f mm band has flora", we / MM)) end
    if warned ~= 1 then fail("narrow", string.format("a %.1f mm band says %d times that it has no flora", we / MM, warned)) end
    for _, chunk in ipairs(pt.out) do
      if paints(chunk) then fail("narrow", "a band too narrow for flora is painted"); break end
    end
    return fails
  end
  if not b then fail("narrow", string.format("a %.1f mm band has no flora", we / MM)); return fails end
  if warned > 0 then fail("narrow", "a band wide enough for flora says it has none") end
  -- width
  local I = b.I or {}
  for i = 1, 4 do
    if not I[i] or math.abs(I[i] - Iw[i]) > 1e-6 then
      fail("width", string.format("the inner rectangle is %s, not the pattern band's %.2f %.2f %.2f %.2f",
        table.concat(I, " "), Iw[1], Iw[2], Iw[3], Iw[4]))
      break
    end
  end
  if not b.first or pt.out[b.first] ~= ring_clip(W, H, Iw) then fail("width", "the band's clip is not the paper less the inner rectangle") end
  -- band: nothing paints outside the clip's span but the rule after it.
  if b.first and b.last then
    for i, chunk in ipairs(pt.out) do
      if (i < b.first or i > b.last) and paints(chunk) and not (b.rule and i > b.last) then
        fail("band", string.format("output %d paints outside the band's clip", i))
        break
      end
    end
  else
    fail("band", "the plants are not cut to the band")
  end
  -- text: the inner rectangle holds the text block and its gap, and every
  -- reservation is cut out of the page before the plants paint.
  local t = spec.text
  if not (I[1] and I[1] <= t.x0 - GAP + 1e-6 and I[2] <= t.y0 - GAP + 1e-6 and I[3] >= t.x1 + GAP - 1e-6 and I[4] >= t.y1 + GAP - 1e-6) then
    fail("text", "the band's inner rectangle does not hold the text block and its gap")
  end
  local reserved = {}
  for _, r in ipairs(spec.reserve or {}) do
    local q = Paint.new({ backend = "pdf" })
    clip_begin(q, {
      { "m", 0, 0 }, { "l", W, 0 }, { "l", W, H }, { "l", 0, H }, { "z" },
      { "m", r[1], r[2] }, { "l", r[1], r[4] }, { "l", r[3], r[4] }, { "l", r[3], r[2] }, { "z" },
    })
    local found = false
    for i = 1, (b.first or #pt.out) do if pt.out[i] == q.out[1] then found = true end end
    if not found then fail("text", "a reservation is not cut out of the page") end
    reserved[q.out[1]] = true
  end
  -- sides: the band is cut by nothing but the reservations (no header
  -- clip, no top inset), so the paint in it shows on every side.
  for i = 1, (b.first or 1) - 1 do
    if pt.out[i]:find("W n", 1, true) and not reserved[pt.out[i]] then
      fail("sides", "a clip other than the reservations' cuts the band")
      break
    end
  end
  -- sides: points of the paint inside the band, by the nearest edge.
  local pts = {}
  for i = b.first or 1, b.last or 0 do points(pt.out[i], pts) end
  local count = { left = 0, right = 0, foot = 0, top = 0 }
  for _, p in ipairs(pts) do
    local x, y = p[1], p[2]
    local d = { left = x, right = W - x, foot = y, top = H - y }
    local side, best = "left", d.left
    for _, k in ipairs({ "right", "foot", "top" }) do
      if d[k] < best then side, best = k, d[k] end
    end
    if best >= 0 and best <= we then count[side] = count[side] + 1 end
  end
  for _, k in ipairs({ "left", "right", "foot", "top" }) do
    if count[k] < 50 then fail("sides", string.format("the %s side has %d points of paint in the band", k, count[k])) end
  end
  -- rule
  local border = spec.pattern_edge == "border"
  local corner = string.format("%.2f %.2f m", Iw[1] * BP, Iw[2] * BP)
  local ruled = b.rule_at ~= nil and paints(pt.out[b.rule_at]) and pt.out[b.rule_at]:find(corner, 1, true) ~= nil
  if border and not ruled then fail("rule", "edge=border draws no rule along the inner rectangle") end
  if not border and ruled then fail("rule", "a rule is drawn without edge=border") end
  -- density: the one asked, or in a band too narrow for it the next
  -- denser one that the band holds, said once in the log.
  local asked = spec.perimeter_density or "dense"
  local want = asked
  for i = #M.DENSITIES, 2, -1 do
    if want == M.DENSITIES[i] and we < M.DENSITY_NARROWEST[want] * MM - 1e-6 then want = M.DENSITIES[i - 1] end
  end
  if b.density ~= want then fail("density", string.format("%s in a %.1f mm band is laid %s, not %s", asked, we / MM, tostring(b.density), want)) end
  local said = 0
  for _, w in ipairs(pt.pattern_warnings or {}) do if w:find("perimeterdensity=" .. asked .. " needs", 1, true) then said = said + 1 end end
  if said ~= (want ~= asked and 1 or 0) then fail("density", string.format("%s in a %.1f mm band says %d times it is laid denser", asked, we / MM, said)) end
  -- frames: every frame of the form, or the vine in a band corners has no
  -- room in, said once.
  local formask = spec.perimeter_flora or "vine"
  local formwant = formask
  if formask == "corners" and we > math.min(W, H) / (2 * M.CORNER_ROOM) + 1e-6 then formwant = "vine" end
  if b.form ~= formwant then fail("frames", string.format("%s in a %.1f mm band is laid %s, not %s", formask, we / MM, tostring(b.form), formwant)) end
  if #frames ~= M.FRAMES[formwant] then fail("frames", string.format("%s in a %.1f mm band has %d frames, not %d", formask, we / MM, #frames, M.FRAMES[formwant])) end
  local fsaid = 0
  for _, w in ipairs(pt.pattern_warnings or {}) do if w:find("perimeterflora=" .. formask .. " needs", 1, true) then fsaid = fsaid + 1 end end
  if fsaid ~= (formwant ~= formask and 1 or 0) then fail("frames", string.format("%s in a %.1f mm band says %d times that it is laid as the vine", formask, we / MM, fsaid)) end
  -- mark
  for _, f in ipairs(frames) do
    if f.spec and f.spec.header_y then fail("mark", "a frame of the band carries a running head") break end
  end
  if #Compose.header_marks(spec) > 0 then fail("mark", "the page has a running-head mark") end
  return fails
end

-- The cell n's seed, edge, density and form, dealt in turn: the density
-- moves on every second cell, the form on every cell and one more with each
-- eighth, so that the 48 cells hold every form asked at every density.
function M.deal(n)
  return M.SEEDS[(n - 1) % #M.SEEDS + 1],
    M.EDGES[(n - 1) // #M.SEEDS % #M.EDGES + 1],
    M.DENSITIES[(n - 1) // 2 % #M.DENSITIES + 1],
    M.FORMS[((n - 1) + (n - 1) // 8) % #M.FORMS + 1]
end

-- The cells of the sweep: papers x widths x titles x backdrops.
M.CELLS = #M.PAPERS * #M.WIDTHS * 2 * #M.BACKDROPS

-- The form x density pairs M.deal does not ask in its cells.
function M.unasked()
  local seen, out = {}, {}
  for n = 1, M.CELLS do
    local _, _, d, f = M.deal(n)
    seen[f .. " " .. d] = true
  end
  for _, f in ipairs(M.FORMS) do
    for _, d in ipairs(M.DENSITIES) do
      if not seen[f .. " " .. d] then out[#out + 1] = f .. " " .. d end
    end
  end
  return out
end

-- Wide bands, one cell of each form: where the sweep's widths (to 18 mm)
-- stop and the key goes on to 40.
M.WIDE = { { "16:9", 30 }, { "4:3", 40 } }

-- The sweep: opts.papers, widths, titles and backdrops (default all), each
-- cell with its own seed, edge, density and form, dealt by M.deal
-- (opts.density and opts.form set one for every cell)
-- so that the sweep holds several of each, in opts.margins (mm) if given;
-- opts.narrow (default true); and opts.wide, the forms set true that also
-- have a cell in each of M.WIDE's bands.
-- Returns the cells swept and every failure as { invariant, cell, text }.
function M.run(opts)
  opts = opts or {}
  local cells, failures = 0, {}
  local function one(name, spec, wmm)
    cells = cells + 1
    for _, f in ipairs(M.check(spec, wmm)) do failures[#failures + 1] = { f[1], name, f[2] } end
  end
  local n = 0
  for _, paper in ipairs(M.PAPERS) do
    for _, wmm in ipairs(M.WIDTHS) do
      for _, titled in ipairs({ true, false }) do
        for _, bd in ipairs(M.BACKDROPS) do
          n = n + 1
          local seed, edge, density, form = M.deal(n)
          local want = (not opts.papers or opts.papers[paper[1]]) and (not opts.widths or opts.widths[wmm])
            and (not opts.titles or opts.titles[titled]) and (not opts.backdrops or opts.backdrops[bd])
          if want then
            local name = string.format("%s %g mm %s %s seed %d edge %s", paper[1], wmm, titled and "title" or "no title", bd, seed, tostring(edge))
            local spec = M.spec(wmm, paper, titled, bd, seed, edge or nil, opts.margins)
            spec.perimeter_density = opts.density or density
            spec.perimeter_flora = opts.form or form
            one(name .. " " .. spec.perimeter_density .. " " .. spec.perimeter_flora, spec, wmm)
          end
        end
      end
    end
  end
  for i, c in ipairs(M.WIDE) do
    for j, form in ipairs(M.FORMS) do
      if opts.wide and opts.wide[form] then
        local paper
        for _, p in ipairs(M.PAPERS) do if p[1] == c[1] then paper = p end end
        local spec = M.spec(c[2], paper, true, "light", 1, nil)
        spec.perimeter_density, spec.perimeter_flora = M.DENSITIES[(i + j) % #M.DENSITIES + 1], form
        one(string.format("%s %g mm wide %s %s", c[1], c[2], spec.perimeter_density, form), spec, c[2])
      end
    end
  end
  if opts.narrow ~= false then
    for _, c in ipairs(M.NARROW) do one(c[1], M.spec(c[3], c[2], true, "light", 1, nil, c[4]), c[3]) end
  end
  return cells, failures
end

-- The frames and the log alone, no painting: every paper (and a small one, A6),
-- both title modes, every form and density, every band from 6 to 40 mm in
-- steps of 1 mm, and uneven margins. It costs a few seconds, so it can run
-- over all of them. Returns the pages checked and every failure as
-- { "frames", page, text }.
-- (160 x 90 mm is the 16:9 paper; A6 is the smallest in which a 40 mm band
-- leaves a text block.)
M.SMALL = { "A6", 105, 148 }
function M.layout(opts)
  opts = opts or {}
  local Frames = require("flora.frames")
  local failures, pages = {}, 0
  local papers = {}
  for _, p in ipairs(M.PAPERS) do papers[#papers + 1] = p end
  papers[#papers + 1] = M.SMALL
  local margins = { false, { 25, 10, 8, 12 } }
  for _, paper in ipairs(papers) do
    for _, m in ipairs(margins) do
      for _, titled in ipairs({ true, false }) do
        for _, form in ipairs(M.FORMS) do
          for _, density in ipairs(M.DENSITIES) do
            for wmm = 6, 40 do
              local spec = M.spec(wmm, paper, titled, "light", 1, nil, m or nil)
              spec.perimeter_density, spec.perimeter_flora = density, form
              local fs = Frames.of(spec)
              local b = fs.band
              local pt = Paint.new({ backend = "pdf" })
              Compose.flora_band(pt, spec, fs)
              local we = b.w
              local want = form
              if form == "corners" and we > math.min(spec.width, spec.height) / (2 * M.CORNER_ROOM) + 1e-6 then want = "vine" end
              local said = 0
              for _, w in ipairs(pt.pattern_warnings or {}) do if w:find("perimeterflora=" .. form .. " needs", 1, true) then said = said + 1 end end
              local name = string.format("%s %g mm%s %s %s %s", paper[1], wmm, m and " margins" or "", titled and "title" or "no title", density, form)
              pages = pages + 1
              if b.none then
                if #fs ~= 0 then failures[#failures + 1] = { "frames", name, #fs .. " frames in a band without flora" } end
              elseif b.form ~= want or #fs ~= M.FRAMES[want] or said ~= (want ~= form and 1 or 0) then
                failures[#failures + 1] = { "frames", name, string.format("laid %s with %d frames (%d said), wanted %s with %d (%d said)",
                  tostring(b.form), #fs, said, want, M.FRAMES[want], want ~= form and 1 or 0) }
              end
            end
          end
        end
      end
    end
  end
  return pages, failures
end

return M
