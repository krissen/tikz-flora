-- The perimeter band (band.lua, pattern.lua's M.perimeter_band): cells moved about
-- the paper's centre paint what they painted before, moved; the band's
-- invariants hold over every pattern, width, paper, edge and backdrop
-- (tests/pattern_perimeter.lua), and each of them fails when the engine is
-- broken the way it guards against; an edge the page leaves out is the
-- pattern's own in a band, and edge=dissolve written out is not; and the
-- band's keys leave every other layout as it was.
local H = dofile("tests/helper.lua")
local Patterns = require("flora.patterns")
local Pattern = require("flora.pattern")
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Rng = require("flora.rng")

-- The numbers in a painter's output, for comparing two drawings.
local function numbers(s)
  local out = {}
  for n in s:gmatch("-?%d+%.?%d*") do out[#out + 1] = tonumber(n) end
  return out
end

local function same(a, b, tol)
  if #a ~= #b then return false, string.format("%d numbers against %d", #a, #b) end
  for i = 1, #a do
    if math.abs(a[i] - b[i]) > tol then return false, string.format("number %d: %g against %g", i, a[i], b[i]) end
  end
  return true
end

-- Every cell of pattern p painted (its lines and the cell) with the map
-- `fn` on every coordinate.
local function paint_cells(p, cells, fn)
  local pt = Paint.new({ backend = "pdf" })
  local base = Pattern.role_inks(Rng.new(3), p, {})
  local ink = Pattern.band_ink(Pattern.cell_inks(base, 1), p, {}, 1, 1)
  pt:frame(fn)
  for _, c in ipairs(cells) do
    c.construct(pt, c, ink)
    c.paint(pt, c, ink)
  end
  pt:frame(nil)
  return pt:body()
end

local function env_of(p)
  return { x0 = -40, y0 = -30, x1 = 160, y1 = 120, size = p.scale, rng = Rng.new(7), opts = {}, style = {} }
end

local ox, oy = 37.25, -11.5
for _, p in ipairs(Patterns.list) do
  local moved = Pattern.shift_cells(p.cells(env_of(p)), ox, oy)
  local a = paint_cells(p, p.cells(env_of(p)), function(x, y) return x + ox, y + oy end)
  local b = paint_cells(p, moved, function(x, y) return x, y end)
  local ok, why = same(numbers(a), numbers(b), 2e-3)
  H.check(ok, p.name .. ": moved cells paint differently: " .. tostring(why))
  -- Moving one drawing leaves the module's own tables where they were.
  local c = paint_cells(p, p.cells(env_of(p)), function(x, y) return x + ox, y + oy end)
  H.check(a == c, p.name .. ": moving cells changed a later drawing")
end

local Band = require("flora.band")
local B = dofile("tests/pattern_perimeter.lua")

-- The repeats the whole rows are sized by: kikko's honeycomb repeats
-- every three sides along x and every sqrt(3) sides along y.
local function pattern(name)
  for _, p in ipairs(Patterns.list) do if p.name == name then return p end end
end
do
  local px, py = Pattern.periods(pattern("kikko"))
  H.check(px and math.abs(px - 3 * pattern("kikko").scale) < 1e-3, "kikko's repeat along x: " .. tostring(px))
  H.check(py and math.abs(py - math.sqrt(3) * pattern("kikko").scale) < 1e-3, "kikko's repeat along y: " .. tostring(py))
end

-- The matrix.
local verbose = os.getenv("FLORA_MATRIX_VERBOSE")
local cells, failures = B.run()
if verbose then print(string.format("band: %d cells, %d failures", #failures == 0 and cells or cells, #failures)) end
H.check(cells == #Patterns.list * (#B.WIDTHS * #B.PAPERS + #B.NARROW) * #B.EDGES * #B.BACKDROPS, "band cells: " .. cells)
for i, f in ipairs(failures) do
  if i > 40 then break end
  H.check(false, string.format("band %s: %s: %s", f[1], f[2], f[3]))
end

-- Each invariant fails when the engine is broken as it guards against: on
-- a smaller sweep, with one of the band's functions replaced.
local SMALL = { patterns = { kikko = true, asanoha = true, stars_8_4 = true, greek_crosses = true },
  widths = { 12 }, papers = { B.PAPERS[1] }, backdrops = { "light" } }
local function mutant(name, fn, replacement, invariant, opts)
  local orig = Pattern[fn]
  Pattern[fn] = replacement(orig)
  local _, fails = B.run(opts or SMALL)
  Pattern[fn] = orig
  local n = 0
  for _, f in ipairs(fails) do if f[1] == invariant then n = n + 1 end end
  H.check(n > 0, string.format("mutation %s: the %s invariant does not fail", name, invariant))
end
-- The field measured against nothing: the cells come into the text.
mutant("no keep", "measure", function(orig) return function(shapes, reach, f, is_hero)
  local g = {}
  for k, v in pairs(f) do g[k] = v end
  g.keep = {}
  return orig(shapes, reach, g, is_hero)
end end, "text")
-- edge=border cut along the inner rectangle alone, not round the text.
mutant("no text holes", "band_holes", function() return function(band) return { band.I } end end, "text")
-- edge=border cut along a rectangle 3 pt larger than the inner one.
mutant("cut off the band", "band_holes", function(orig) return function(band, keep, gap)
  local out = orig(band, keep, gap)
  local I = out[1]
  out[1] = { I[1] - 3, I[2] - 3, I[3] + 3, I[4] + 3 }
  return out
end end, "width")
mutant("crooked cut", "band_holes", function(orig) return function(band, keep, gap)
  local out = orig(band, keep, gap)
  local I = out[1]
  out[1] = { I[1] + 2, I[2], I[3], I[4] }
  return out
end end, "straight")
-- The lattice moved off the paper's centre.
mutant("off centre", "shift_cells", function(orig) return function(cs, dx, dy) return orig(cs, dx + 2, dy) end end, "gaps")
-- Whole rows laid a third of a repeat off the inner edge.
mutant("rows off the edge", "row_phase", function(orig) return function(p, size, w, period, along)
  local at, share = orig(p, size, w, period, along)
  return at - period / 3, share
end end, "rows")
-- The band's field stopping 60 pt below the paper's top.
mutant("top cut", "band_top", function() return function(_, Hh) return Hh - 60 end end, "top")
-- The band's inner rectangle taken whole where the margin is narrower:
-- edge=border's rule crosses the text.
mutant("rule over the text", "band_inner", function() return function(spec, w)
  return { w, w, spec.width - w, spec.height - w }
end end, "text", { patterns = { kikko = true }, narrow_only = true, backdrops = { "light" }, edges = { "border" } })
-- celtic_knot's closed panel kept a square (8 pt at 12 mm) further from
-- the inner edge than it may come: the rectangle it keeps clear of grown
-- by that much on every side.
mutant("narrow panel", "panel_room", function(orig) return function(band, gap, keep)
  local out = orig(band, gap, keep)
  local r, d = out[1], 8
  out[1] = { r[1] - d, r[2] - d, r[3] + d, r[4] + d }
  return out
end end, "width", { patterns = { celtic_knot = true }, widths = { 12 }, papers = { B.PAPERS[1] }, backdrops = { "light" }, edges = { false } })
-- Every warning given twice.
mutant("warn twice", "warn", function(orig) return function(pt, msg)
  orig(pt, msg)
  table.insert(pt.pattern_warnings, msg)
end end, "warn", { patterns = { penrose_rhombs = true }, widths = { 12 }, papers = { B.PAPERS[1] }, backdrops = { "light" } })
-- And with the warnings: a hero, the patterns that do not carry a band.
do
  local orig = B.expected
  B.expected = function(p, wmm, edge, widths)
    local out = orig(p, wmm, edge, widths)
    for i = #out, 1, -1 do if out[i][1] == "does not carry a perimeter band" then table.remove(out, i) end end
    return out
  end
  local _, fails = B.run({ patterns = { khatam = true }, widths = { 8 }, papers = { B.PAPERS[1] }, backdrops = { "light" }, edges = { false }, narrow = false })
  B.expected = orig
  local n = 0
  for _, f in ipairs(fails) do if f[1] == "warn" then n = n + 1 end end
  H.check(n > 0, "khatam at 8 mm gives no warning, or the check does not see it")
end
do
  local spec = B.spec("kikko", 12, B.PAPERS[1], false, "light")
  spec.pattern_hero = "rosette"
  local pt = Compose.page(spec)
  local n = 0
  for _, g in ipairs(pt.pattern_warnings or {}) do if g:find("is not drawn in a perimeter band", 1, true) then n = n + 1 end end
  H.check(n == 1, "hero in a band: warned " .. n .. " times")
  spec = B.spec("kikko", 12, B.PAPERS[1], "guilloche", "light")
  pt = Compose.page(spec)
  n = 0
  for _, g in ipairs(pt.pattern_warnings or {}) do if g:find("has no form in a perimeter band", 1, true) then n = n + 1 end end
  H.check(n == 1, "edge=guilloche in a band: warned " .. n .. " times")
  H.check(pt.pattern.band and pt.pattern.band.inner == "rule", "edge=guilloche in a band: kikko is not laid with its own edge")
end

-- The edge a page leaves out is the pattern's own in a band; edge=dissolve
-- written out (the key's default) is dissolve, into the margin.
do
  local function inner(name, edge)
    local pt = Compose.page(B.spec(name, 12, B.PAPERS[1], edge, "light"))
    return pt.pattern.band and pt.pattern.band.inner or pt.pattern.inner
  end
  H.check(inner("kikko", false) == "rule", "kikko's own edge in a band is not border")
  H.check(inner("truchet", false) == "rule", "truchet's own edge in a band is not border")
  H.check(inner("asanoha", false) == "rows", "asanoha's own edge in a band is not rows")
  H.check(inner("stars_8_4", false) == "rows", "stars_8_4's own edge in a band is not rows")
  H.check(inner("celtic_knot", false) == "panel", "celtic_knot's own edge in a band is not its closed panel")
  H.check(inner("kikko", "dissolve") == "margin", "edge=dissolve written out is not dissolve in a band")
  H.check(inner("asanoha", "dissolve") == "margin", "edge=dissolve written out gives asanoha its own edge")
  H.check(Band.default_edge("kikko") == Band.EDGE, "band.lua's default edge")
end

-- Under edge=cell on a dark backdrop the ground follows the cells
-- (ground=auto); under border and whole rows it is a straight panel.
do
  local function ground(name, edge)
    local spec = B.spec(name, 12, B.PAPERS[1], edge, "dark")
    local pt = Compose.page(spec)
    return pt.pattern
  end
  local q = ground("asanoha", "cell")
  H.check(q.grounded > 0 and q.ground_edge == "cells", "asanoha edge=cell on dark: the ground does not follow its cells")
  q = ground("asanoha", "border")
  H.check(q.grounded > 0 and q.ground_edge == "panel", "asanoha edge=border on dark: the ground is not one straight panel")
end

-- The band's keys change nothing on a page of another layout.
do
  local function page(extra)
    local spec = B.spec("kikko", 12, B.PAPERS[1], false, "light")
    spec.layout, spec.perimeter_width = "surround", nil
    for k, v in pairs(extra or {}) do spec[k] = v end
    return Compose.page(spec):body()
  end
  H.check(page() == page({ perimeter_width = 8 }), "surround: the band's width changed the page")
end

H.done("test_pattern_perimeter")
