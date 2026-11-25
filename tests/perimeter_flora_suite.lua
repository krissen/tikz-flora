-- Flora in the perimeter band (frames.lua's M.vine): the invariants of
-- tests/perimeter_flora.lua over every paper, band width, frame title and
-- backdrop, each of them failing when the engine is broken the way it
-- guards against; each form's own frames; the log's band widths; and the
-- line the vine follows (loop.lua) mapped there and back.
-- The suite is split over tests/test_perimeter_flora_1.lua .. _4.lua: each
-- runs run(part, parts), its share of the sweep and of the mutations, and
-- part 1 the checks too small to weigh (tests/split.lua).
local H = dofile("tests/helper.lua")
local Compose = require("flora.compose")
local Frames = require("flora.frames")
local Pattern = require("flora.pattern")
local Paint = require("flora.paint")
local Band = require("flora.band")
local Loop = require("flora.loop")

-- What each item weighs, in CPU seconds (each item timed alone, 2026-11): a
-- paper and band width's share of the sweep (its four cells), and each
-- mutation.
local WEIGHTS = {
  { "sweep:16:9 6", 37 }, { "sweep:16:9 8", 33 }, { "sweep:16:9 12", 33 }, { "sweep:16:9 18", 37 },
  { "sweep:4:3 6", 28 }, { "sweep:4:3 8", 36 }, { "sweep:4:3 12", 36 }, { "sweep:4:3 18", 27 },
  { "sweep:A4 6", 68 }, { "sweep:A4 8", 68 }, { "sweep:A4 12", 44 }, { "sweep:A4 18", 49 },
  { "mutant:not cut", 12 }, { "mutant:own width", 12 }, { "mutant:one plant", 8 }, { "mutant:narrow allowed", 10 },
  { "mutant:no rule", 12 }, { "mutant:header clip", 12 }, { "mutant:running head", 12 }, { "mutant:reservation drawn over", 12 },
  { "mutant:inner gap", 12 }, { "mutant:density too narrow", 6 }, { "mutant:one pinwheel plant", 6 },
}

return function(part, parts)
local S = dofile("tests/split.lua").new(part, parts, WEIGHTS)
local F = dofile("tests/perimeter_flora.lua")

-- The line round the page, and its maps there and back.
if S.once("loop") then
  local lp = Loop.new(10, 20, 410, 220, 15)
  H.check(math.abs(lp.len - (2 * (400 - 30) + 2 * (200 - 30) + 2 * math.pi * 15)) < 1e-9, "loop length " .. lp.len)
  local x, y, nx, ny = lp:at(0)
  H.check(math.abs(x - 210) < 1e-9 and math.abs(y - 20) < 1e-9 and nx == 0 and ny == 1, "the loop starts at the foot's centre, inward up")
  for _, s0 in ipairs({ 0, lp:corner(1), lp:corner(3) }) do
    for _, dir in ipairs({ 1, -1 }) do
      local fn, inv = lp:maps(s0, 30, 0.5, dir)
      for _, p in ipairs({ { 30, 0 }, { 25, 100 }, { 40, 300 }, { 22, -20 } }) do
        local px, py = fn(p[1], p[2])
        local a, b = inv(px, py)
        H.check(math.abs(a - p[1]) < 1e-6 and math.abs(b - p[2]) < 1e-6,
          string.format("loop map at s0 %.1f dir %d: (%g, %g) comes back as (%g, %g)", s0, dir, p[1], p[2], a, b))
      end
    end
  end
end

-- Each form lays its own frames: the vine two plants along the line, the
-- pinwheel two turned a half circle, corners four corner plants and four
-- vines along the sides; none says in the log that it is laid as another.
if S.once("forms") then
  local want = { vine = 2, pinwheel = 2, corners = 8 }
  for _, form in ipairs(Band.FLORAS) do
    local spec = F.spec(12, F.PAPERS[1], false, "light", 1, nil)
    spec.perimeter_flora = form
    local fs = Frames.of(spec)
    H.check(#fs == want[form] and fs.band.form == form, string.format("%s: %d frames, not %d", form, #fs, want[form]))
    local pt = Paint.new({ backend = "pdf" })
    Compose.flora_band(pt, spec, fs)
    H.check(#(pt.pattern_warnings or {}) == 0, form .. ": the log says " .. tostring((pt.pattern_warnings or {})[1]))
  end
end

-- The log's band widths never cross the limit they are told against: a
-- band just under a limit is written under it, one on it at it. The
-- flora band's limits (6 mm, open's 7 and sparse's 9), the narrowing below
-- the width asked, and the pattern band's 4 mm.
if S.once("log widths") then
  local function said(warnings, pattern)
    for _, w in ipairs(warnings or {}) do
      local n = w:match(pattern)
      if n then return tonumber(n) end
    end
  end
  for _, c in ipairs({ { 5.99, "dense", 6 }, { 6, "dense", nil }, { 6.99, "open", 7 }, { 7, "open", nil }, { 8.99, "sparse", 9 }, { 9, "sparse", nil } }) do
    local spec = F.spec(c[1], F.PAPERS[1], false, "light", 1, nil)
    spec.perimeter_density = c[2]
    local pt = Paint.new({ backend = "pdf" })
    Compose.flora_band(pt, spec, Frames.of(spec))
    local n = said(pt.pattern_warnings, "the perimeter band is ([%d.]+) mm, narrower") or said(pt.pattern_warnings, "the ([%d.]+) mm band is laid")
    if c[3] then
      H.check(n and n < c[3], string.format("a %g mm band at %s is written as %s mm against %g mm", c[1], c[2], tostring(n), c[3]))
    else
      H.check(n == nil, string.format("a %g mm band at %s says it is too narrow (%s mm)", c[1], c[2], tostring(n)))
    end
  end
  -- Narrowed by its margins to just under the 12 mm asked.
  local B = dofile("tests/pattern_perimeter.lua")
  local m = (11.99 * 72 / 25.4 + 9) * 25.4 / 72
  local spec = F.spec(12, F.PAPERS[1], false, "light", 1, nil, { m, m, m, m })
  local pt = Paint.new({ backend = "pdf" })
  Compose.flora_band(pt, spec, Frames.of(spec))
  local n = said(pt.pattern_warnings, "the band is ([%d.]+) mm on all four sides")
  H.check(n and n < 12, "a band narrowed to 11.99 mm is written as " .. tostring(n) .. " mm, not under the 12 mm asked")
  -- The pattern band's 4 mm: margins that leave 3.99 mm.
  m = (3.99 * 72 / 25.4 + 9) * 25.4 / 72
  local ps = B.spec("kikko", 12, B.PAPERS[1], false, "light", { m, m, m, m })
  pt = Paint.new({ backend = "pdf" })
  local kikko
  for _, p in ipairs(require("flora.patterns").list) do if p.name == "kikko" then kikko = p end end
  Pattern.perimeter_band(ps, kikko, pt)
  n = said(pt.pattern_warnings, "room for no perimeter band %(([%d.]+) mm%)")
  H.check(n and n < 4, "a 3.99 mm pattern band is written as " .. tostring(n) .. " mm against 4 mm")
end

-- The sweep.
local verbose = os.getenv("FLORA_MATRIX_VERBOSE")
local total = 0
for _, paper in ipairs(F.PAPERS) do
  for _, wmm in ipairs(F.WIDTHS) do
    if S.mine(string.format("sweep:%s %d", paper[1], wmm)) then
      local cells, failures = F.run({ papers = { [paper[1]] = true }, widths = { [wmm] = true }, narrow = false })
      total = total + cells
      if verbose then print(string.format("perimeter flora %s %d mm: %d cells, %d failures", paper[1], wmm, cells, #failures)) end
      S.check(H, cells == 4, string.format("perimeter flora %s %d mm: %d cells", paper[1], wmm, cells))
      for i, f in ipairs(failures) do
        if i > 20 then break end
        H.check(false, string.format("perimeter flora %s: %s: %s", f[1], f[2], f[3]))
      end
    end
  end
end
if S.once("narrow") then
  local cells, failures = F.run({ papers = {}, narrow = true })
  H.check(cells == #F.NARROW, "narrow cells: " .. cells)
  for _, f in ipairs(failures) do H.check(false, string.format("perimeter flora %s: %s: %s", f[1], f[2], f[3])) end
end

-- Each invariant fails when the engine is broken as it guards against, on
-- the one page that shows it (a vine's, unless opts.form says otherwise):
-- field `key` of table `t` is replaced by what `make` returns for it while
-- the sweep runs, and set back after.
local ONE = { papers = { ["16:9"] = true }, widths = { [12] = true }, titles = { [true] = true }, backdrops = { light = true }, narrow = false }
local function mutant(name, invariant, t, key, make, opts)
  if not S.mine("mutant:" .. name) then return end
  opts = opts or ONE
  if not opts.form then
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.form, opts = "vine", o
  end
  local orig = t[key]
  t[key] = make(orig)
  local ok, cells, fails = pcall(F.run, opts)
  t[key] = orig
  H.check(ok, string.format("mutation %s: the sweep stopped: %s", name, tostring(cells)))
  local n = 0
  for _, f in ipairs(ok and fails or {}) do if f[1] == invariant then n = n + 1 end end
  H.check(n > 0, string.format("mutation %s: the %s invariant does not fail", name, invariant))
end

-- The plants left uncut.
mutant("not cut", "band", Compose, "flora_band", function(orig) return function(pt, spec, frames)
  return orig(pt, setmetatable({ keep_bounds = true }, { __index = spec }), frames)
end end)
-- The band 3 pt wider than the pattern band's.
mutant("own width", "width", Pattern, "band_width", function(orig) return function(spec)
  local w, asked, side, I = orig(spec)
  if not (w and I) then return nil end
  return w + 3, asked, side, { I[1] + 3, I[2] + 3, I[3] - 3, I[4] - 3 }
end end)
-- The second plant, round the foot and up the right, left out.
mutant("one plant", "sides", Frames, "vine", function(orig) return function(spec, b)
  local fs = orig(spec, b)
  fs[2] = nil
  return fs
end end)
-- The pinwheel's second plant, down the right and along the top, left out.
mutant("one pinwheel plant", "sides", Frames, "pinwheel", function(orig) return function(spec, b)
  local fs = orig(spec, b)
  fs[2] = nil
  return fs
end end, { papers = { ["16:9"] = true }, widths = { [12] = true }, titles = { [true] = true }, backdrops = { light = true }, narrow = false,
  form = "pinwheel" })
-- Flora laid in bands down to 4 mm.
mutant("narrow allowed", "narrow", Band, "FLORA_NARROWEST", function() return 4 end, { papers = {}, narrow = true })
-- edge=border without its rule.
mutant("no rule", "rule", Band, "FLORA_RULE", function() return "nothing" end,
  { papers = { ["16:9"] = true }, widths = { [12] = true }, titles = { [false] = true }, backdrops = { light = true }, narrow = false })
-- sparse laid in bands down to 6 mm: an 8 mm band keeps it.
mutant("density too narrow", "density", Band, "DENSITY_NARROWEST", function(orig)
  local t = {}
  for k, v in pairs(orig) do t[k] = v end
  t.sparse = 6
  return t
end, { papers = { ["16:9"] = true }, widths = { [8] = true }, titles = { [true] = true }, backdrops = { light = true }, narrow = false,
  density = "sparse" })
-- The page clipped under its running head and top inset, as surround is.
mutant("header clip", "sides", Compose, "perimeter_page", function() return function() return false end end)
-- The vine's frames given the page's running head.
mutant("running head", "mark", Frames, "vine", function(orig) return function(spec, b)
  local fs = orig(spec, b)
  for i = 1, #fs do fs[i].spec.header_y = spec.header_y end
  return fs
end end)
-- A reservation's clip left out: the band paints over it. The
-- reservation's clip is the paper with a box in its right half cut out;
-- the band's is cut out from its left edge.
mutant("reservation drawn over", "text", getmetatable(Paint.new({ backend = "pdf" })).__index, "clip_begin",
  function(orig) return function(self, cmds)
    if cmds[7] and cmds[7][2] > 200 then
      self.clips = (self.clips or 0) + 1
      self.out[#self.out + 1] = "q"
      return
    end
    return orig(self, cmds)
  end end)
-- The text block's gap left out of the band's narrowing (pattern.lua's
-- band_inner): a band to the margin's full width, on a page whose 14 mm
-- margins hold a 12 mm band only less the gap.
mutant("inner gap", "text", Pattern, "band_inner", function() return function(spec, w)
  local W, Ht, t = spec.width, spec.height, spec.text
  local m = math.min(w, t.x0, t.y0, W - t.x1, Ht - t.y1)
  return { m, m, W - m, Ht - m }, ""
end end, { papers = { ["16:9"] = true }, widths = { [12] = true }, titles = { [true] = true }, backdrops = { light = true },
  narrow = false, margins = { 14, 14, 14, 14 } })

-- The band's keys change nothing on a page of another layout.
if S.once("other layouts") then
  local function page(extra)
    local spec = F.spec(12, F.PAPERS[1], true, "light", 1, nil)
    spec.layout = "surround"
    for k, v in pairs(extra or {}) do spec[k] = v end
    Paint.reset_resources()
    return Compose.page(spec):body()
  end
  local base = page()
  H.check(base == page({ perimeter_width = 8 }), "surround: the band's width changed the page")
  H.check(base == page({ perimeter_flora = "pinwheel" }), "surround: the band's form changed the page")
end

if verbose then print(string.format("perimeter flora: %d cells in part %d of %d", total, part, parts)) end
S.finish(H)
H.done("test_perimeter_flora_" .. part)
end
