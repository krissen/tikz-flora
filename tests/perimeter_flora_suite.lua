-- Flora in the perimeter band (frames.lua's M.vine): the invariants of
-- tests/perimeter_flora.lua over every paper, band width, frame title and
-- backdrop, each of them failing when the engine is broken the way it
-- guards against; the forms the key names that are not drawn yet laid as
-- vine, saying so; and the line the vine follows (loop.lua) mapped there
-- and back.
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
  { "sweep:16:9 6", 35 }, { "sweep:16:9 8", 49 }, { "sweep:16:9 12", 50 }, { "sweep:16:9 18", 44 },
  { "sweep:4:3 6", 31 }, { "sweep:4:3 8", 46 }, { "sweep:4:3 12", 45 }, { "sweep:4:3 18", 42 },
  { "sweep:A4 6", 62 }, { "sweep:A4 8", 86 }, { "sweep:A4 12", 76 }, { "sweep:A4 18", 71 },
  { "mutant:not cut", 12 }, { "mutant:own width", 12 }, { "mutant:one plant", 8 }, { "mutant:narrow allowed", 10 },
  { "mutant:no rule", 12 }, { "mutant:header clip", 12 }, { "mutant:running head", 12 }, { "mutant:reservation drawn over", 12 },
  { "mutant:inner gap", 12 },
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

-- The forms not drawn yet are laid as vine, and the log says so once.
if S.once("forms") then
  for _, form in ipairs(Band.FLORAS) do
    local spec = F.spec(8, F.PAPERS[1], false, "light", 1, nil)
    spec.perimeter_flora = form
    local fs = Frames.of(spec)
    H.check(#fs == 2 and fs.band.form == form, form .. ": two plants of the vine")
    Paint.reset_resources()
    local pt = Paint.new({ backend = "pdf" })
    Compose.flora_band(pt, spec, fs)
    local said = 0
    for _, w in ipairs(pt.pattern_warnings or {}) do if w:find(form .. " is not drawn yet", 1, true) then said = said + 1 end end
    H.check(said == (Band.FLORA_BUILT[form] and 0 or 1), string.format("%s: says %d times it is not drawn yet", form, said))
  end
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
-- the one page that shows it: field `key` of table `t` is replaced by what
-- `make` returns for it while the sweep runs, and set back after.
local ONE = { papers = { ["16:9"] = true }, widths = { [12] = true }, titles = { [true] = true }, backdrops = { light = true }, narrow = false }
local function mutant(name, invariant, t, key, make, opts)
  if not S.mine("mutant:" .. name) then return end
  local orig = t[key]
  t[key] = make(orig)
  local ok, cells, fails = pcall(F.run, opts or ONE)
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
mutant("one plant", "sides", Frames, "vine", function(orig) return function(spec)
  local fs = orig(spec)
  fs[2] = nil
  return fs
end end)
-- Flora laid in bands down to 4 mm.
mutant("narrow allowed", "narrow", Band, "FLORA_NARROWEST", function() return 4 end, { papers = {}, narrow = true })
-- edge=border without its rule.
mutant("no rule", "rule", Band, "FLORA_RULE", function() return "nothing" end,
  { papers = { ["16:9"] = true }, widths = { [12] = true }, titles = { [false] = true }, backdrops = { light = true }, narrow = false })
-- The page clipped under its running head and top inset, as surround is.
mutant("header clip", "sides", Compose, "perimeter_page", function() return function() return false end end)
-- The vine's frames given the page's running head.
mutant("running head", "mark", Frames, "vine", function(orig) return function(spec)
  local fs = orig(spec)
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
