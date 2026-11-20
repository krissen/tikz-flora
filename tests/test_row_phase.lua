-- Pattern.row_phase remembers the offsets it measured (pattern.lua): a band
-- of whole rows painted again finds its offset without measuring it again,
-- and whatever changes what it would measure (a tuned value that sizes the
-- cells, the page's pattern scale, the pattern's own values, its cells
-- function) is measured anew, so the page is the one painted with nothing
-- remembered.
local H = dofile("tests/helper.lua")
local Pattern = require("flora.pattern")
local Patterns = require("flora.patterns")
local Compose = require("flora.compose")
local Paint = require("flora.paint")
local B = dofile("tests/pattern_perimeter.lua")

local measured = 0
local measure = Pattern.measure_row_phase
Pattern.measure_row_phase = function(...)
  measured = measured + 1
  return measure(...)
end

local function spec(name)
  return B.spec(name or "kikko", 12, B.PAPERS[1], "rows", "light")
end
local function body(s)
  Paint.reset_resources()
  return Compose.page(s):body()
end
-- The page painted with nothing remembered.
local function fresh(s)
  Pattern.forget_row_phases()
  return body(s)
end

Pattern.forget_row_phases()
measured = 0
local first = body(spec())
H.check(measured > 0, "a band of whole rows measured no offset")
local n = measured
H.check(body(spec()) == first, "the same page painted again differs")
H.check(measured == n, "the same page painted again measured its offset again")

-- Each change, made between two paintings in one process: the offset is
-- measured again and the page is the one painted with nothing remembered.
local function changed(what, apply, undo)
  Pattern.forget_row_phases()
  body(spec())
  apply()
  local before = measured
  local got = body(spec())
  H.check(measured > before, what .. ": the offset was not measured again")
  H.check(got == fresh(spec()), what .. ": the page differs from the one painted with nothing remembered")
  undo()
end

local FS = Pattern.FIELD_SCALE
local ref = FS.ref
changed("the field scale's reference width", function() FS.ref = ref * 0.3 end, function() FS.ref = ref end)
local floor = FS.floor
changed("the field scale's floor", function() FS.floor = 0.9 end, function() FS.floor = floor end)

local kikko = Patterns.by_name.kikko
local scale = kikko.scale
changed("the pattern's own scale", function() kikko.scale = scale * 1.25 end, function() kikko.scale = scale end)
-- A value of the pattern's own that is not among the arguments: the cells
-- function may read it, so it is part of the key.
local core = kikko.core
changed("a value of the pattern's own", function() kikko.core = core + 0.1 end, function() kikko.core = core end)
local cells = kikko.cells
changed("a cells function swapped", function()
  kikko.cells = function(env)
    local out = cells(env)
    for _, c in ipairs(out) do for _, v in ipairs(c.verts) do v[2] = v[2] - 0.5 end end
    return out
  end
end, function() kikko.cells = cells end)

-- The page's own pattern scale.
do
  Pattern.forget_row_phases()
  body(spec())
  local before = measured
  local s = spec()
  s.pattern_scale = 1.5
  local got = body(s)
  H.check(measured > before, "pattern scale 1.5: the offset was not measured again")
  local s2 = spec()
  s2.pattern_scale = 1.5
  H.check(got == fresh(s2), "pattern scale 1.5: the page differs from the one painted with nothing remembered")
end

Pattern.measure_row_phase = measure
H.done("test_row_phase")
