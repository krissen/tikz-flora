-- Nothing a pattern paints comes within the field's gap of the text, its
-- lines or a reservation, measured as overlap of the paint itself
-- (tests/pattern_protect.lua): a small reservation inside a cell, inside a
-- plate between cells, under a piece of ground, inside the ground's panel,
-- inside celtic_knot's field panel or at a hero's middle, over scale 1, 2
-- and 4, edge=cell and dissolve, the four layouts and both backdrops.
local H = dofile("tests/helper.lua")
local M = dofile("tests/pattern_protect.lua")

-- The sweep's own geometry: a fill that holds the rectangle's middle
-- overlaps it at a gap of 0 too (the sweep takes the gap less a hair, so
-- the limit is negative), whatever the box test would say.
do
  local square = { { 0, 0 }, { 20, 0 }, { 20, 20 }, { 0, 20 } }
  local r = { 9, 9, 11, 11 }
  for _, g in ipairs({ 6 - 1e-6, 0, -1e-6 }) do
    H.check(M.shape_overlaps({ polys = { square }, discs = {} }, true, 0, r, g), "a fill that holds the rectangle's middle overlaps it at gap " .. g)
  end
  H.check(not M.shape_overlaps({ polys = { square }, discs = {} }, false, 0, r, -1e-6), "a stroke far from the rectangle does not overlap it")
end

-- Four whole stars round a cross, and a reservation inside the cross only:
-- every star clears it by more than the gap, the cross does not. (The
-- page's widest strip, 344 pt at its foot, is past the field scale's
-- ceiling: the cells are khatam's own at scale 4, 112 pt.)
do
  local function spec(reserve)
    return { width = 400, height = 400, text = { x0 = 20, y0 = 350, x1 = 380, y1 = 390 }, seed = 7, layout = "surround",
      pattern = { khatam = 1 }, pattern_scale = 4, pattern_edge = "cell", mix = { density = 10 }, reserve = reserve,
      lines = { { x0 = 20, y0 = 380, x1 = 100, y1 = 390 } } }
  end
  -- The stars sit on the lattice of the cells' size a (112 pt at khatam's
  -- own size and scale 4), the cross between four of them at 1.5 a.
  local a = M.overlaps(spec(nil)).pattern.size
  local m, h = 1.5 * a, 4 * a / 112
  local pt, o = M.overlaps(spec({ { m - h, m - h, m + h, m + h } }))
  local stars = 0
  for _, k in ipairs(pt.pattern.kept) do
    local c = k.cell
    local function on(v) return math.abs(v - a) < 1e-6 or math.abs(v - 2 * a) < 1e-6 end
    if on(c.x) and on(c.y) then stars = stars + 1 end
  end
  H.check(stars == 4, "the four stars round the cross stand: " .. stars)
  H.check(#o == 0, "a plate between cells keeps clear of a reservation inside it: " .. #o .. " overlaps")
end

local Pattern = require("flora.pattern")
local verbose = os.getenv("FLORA_MATRIX_VERBOSE")

-- The sweep. FLORA_PROTECT_FULL=1 runs M.PLAN whole (every page at every
-- scale, the heroes too: some 16 minutes); the suite runs the small page
-- at every scale and the large one at scale 4, where whole stars stand
-- round a plate, and the heroes on the small page at scale 1.
local full = os.getenv("FLORA_PROTECT_FULL")
local plan = full and M.PLAN or { { 1, 1 }, { 1, 2 }, { 1, 4 }, { 2, 4 } }
local cells, failures = M.sweep(nil, { plan = plan, heroes = full and nil or false })
if not full then
  local hc, hf = M.sweep(function(_, form) return form:find("^hero") end, { plan = { { 1, 1 } } })
  for _, c in ipairs(hc) do cells[#cells + 1] = c end
  for _, f in ipairs(hf) do failures[#failures + 1] = f end
end
for _, f in ipairs(failures) do H.check(false, f) end
-- Every form is swept, and found on the page often enough to be tested.
local per = {}
for _, c in ipairs(cells) do
  local k = c.form:find("^hero") and "hero" or c.form
  per[k] = per[k] or { n = 0, found = 0 }
  per[k].n = per[k].n + 1
  if c.found then per[k].found = per[k].found + 1 end
end
for _, form in ipairs({ "cell", "plate between cells", "ground piece", "ground panel", "field panel", "hero" }) do
  local v = per[form]
  H.check(v and v.found > 0, "protect: no example found of " .. form)
  if verbose and v then print(string.format("protect %s: %d cases, %d with an example", form, v.n, v.found)) end
end

-- Proof, form by form, that the sweep fails when that form is laid without
-- its own check: the precondition (Pattern.lays) waived for it, and with it
-- whatever else keeps that form clear (the footprint judge measures, the
-- panel's holes, the field panel's room, the hero's placing).
local function mutant(name, patch, filter, opts)
  local undo = patch()
  local ok, _, fs = pcall(M.sweep, filter, opts)
  undo()
  if verbose then print(string.format("mutation %s: %s", name, ok and (#fs .. " failing cells") or tostring(_))) end
  H.check(ok and #fs > 0, "protect: the sweep misses " .. name)
end
local function waive(form, extra)
  return function()
    local lays = Pattern.lays
    Pattern.lays = function(f, ...) if f == form then return true end return lays(f, ...) end
    local undo = extra and extra()
    return function() Pattern.lays = lays; if undo then undo() end end
  end
end
local one = { edges = { "cell" }, layouts = { "left" }, backdrops = { "light" } }
local function with(t) local o = {}; for k, v in pairs(one) do o[k] = v end; for k, v in pairs(t) do o[k] = v end; return o end
local function only(pattern, form) return function(p, f) return p == pattern and f == form end end
mutant("a plate between cells laid unchecked", waive("between"), only("khatam", "plate between cells"), with({ plan = { { 2, 4 } } }))
mutant("a cell laid by its pieces alone", waive("cell", function()
  local footprint = Pattern.footprint
  Pattern.footprint = function(c, base) local o = footprint(c, base); table.remove(o, 1); return o end
  return function() Pattern.footprint = footprint end
end), only("stars_8_4", "cell"), with({ plan = { { 1, 1 } } }))
mutant("a piece of ground laid unmeasured", waive("piece", function()
  local footprint = Pattern.footprint
  Pattern.footprint = function(c) return { c } end
  return function() Pattern.footprint = footprint end
end), only("rosette_lattice", "ground piece"), with({ plan = { { 1, 1 } } }))
mutant("the ground's panel laid without its holes", waive("panel", function()
  local panel_path = Pattern.panel_path
  Pattern.panel_path = function(f)
    local g = {}
    for k, v in pairs(f) do g[k] = v end
    g.avoid = { { f.text.x0, f.text.y0, f.text.x1, f.text.y1 } }
    return panel_path(g)
  end
  return function() Pattern.panel_path = panel_path end
end), only("asanoha", "ground panel"), with({ plan = { { 1, 1 } } }))
mutant("celtic_knot's field panel laid without its room", waive("cell", function()
  local Celtic = require("flora.pat_celtic").engine
  local inner, measure = Celtic.field_inner, Pattern.measure
  Celtic.field_inner = function(env, mode)
    local e = {}
    for k, v in pairs(env) do e[k] = v end
    e.room = {}
    for k, v in pairs(env.room or {}) do e.room[k] = v end
    e.room.avoid = {}
    return inner(e, mode)
  end
  Pattern.measure = function(sh, ...)
    if sh[1] and sh[1].fixed then return math.huge, true end
    return measure(sh, ...)
  end
  return function() Celtic.field_inner, Pattern.measure = inner, measure end
end), only("celtic_knot", "field panel"), with({ plan = { { 1, 1 } } }))
mutant("a hero placed and laid unchecked", waive("hero", function()
  local Hero = require("flora.pattern_hero")
  local place = Hero.place
  Hero.place = function(name, spec, side, top, _, ...) return place(name, spec, side, top, {}, ...) end
  return function() Hero.place = place end
end), only("stars_8_4", "hero rosette"), with({ plan = { { 1, 1 } } }))

H.done("pattern protect")
