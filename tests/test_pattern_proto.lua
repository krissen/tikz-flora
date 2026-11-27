-- The pattern prototypes (lua/flora/pattern_proto.lua, spec.pattern_opts):
-- off unless set, a log line for a value or a pattern they cannot take,
-- and the places they lay.
local H = dofile("tests/helper.lua")
local Compose = require("flora.compose")
local Paint = require("flora.paint")
local P = require("flora.progression")
local Patterns = require("flora.patterns")
local Proto = require("flora.pattern_proto")

local function spec(name, opts, extra)
  local sp = { width = 360, height = 270, text = { x0 = 130, y0 = 40, x1 = 230, y1 = 230 }, seed = 7,
    layout = "centered", pattern = { [name or "stars_8_4"] = 1 }, pattern_opts = opts }
  for k, v in pairs(extra or {}) do sp[k] = v end
  return sp
end

local function page(name, opts, extra)
  Paint.reset_resources()
  return Compose.page(spec(name, opts, extra))
end

local function warned(pt, text)
  for _, w in ipairs(pt.pattern_warnings or {}) do
    if w:find(text, 1, true) then return true end
  end
  return false
end

-- Off as they come: no key, or every key off, paints what a page without
-- pattern_opts paints, and the page keeps no prototype report.
for _, p in ipairs(Patterns.list) do
  local plain = page(p.name):body()
  local off = page(p.name, { deviant = false, loose = "off" })
  H.check(off:body() == plain, p.name .. ": keys set to off change the page")
  H.check(off.pattern.proto == nil, p.name .. ": keys set to off leave a report")
end

-- A value that is none of the key's is logged and the key left off.
do
  local plain = page():body()
  local g = page(nil, { gold = "silver" })
  H.check(warned(g, "pattern_opts.gold=silver is not one of core, cells, knobs, crossings, hero"), "unknown gold value not logged")
  H.check(g:body() == plain, "an unknown gold value changed the page")
  for _, key in ipairs({ "deviant", "loose" }) do
    local d = page(nil, { [key] = "maybe" })
    H.check(warned(d, "pattern_opts." .. key .. "=maybe is not true or false"), key .. ": unknown value not logged")
    H.check(d:body() == plain, key .. ": an unknown value changed the page")
  end
end

-- Every gold value, on a pattern that can take it, paints something else
-- and lays places; hero lays none in the field.
for _, g in ipairs(Proto.GOLD_ORDER) do
  local plain = page("stars_8_4"):body()
  local pt = page("stars_8_4", { gold = g })
  H.check(pt.pattern.proto and pt.pattern.proto.gold == g, g .. ": no report")
  H.check(pt.pattern_warnings == nil, g .. ": logged on a pattern that takes it")
  if g == "hero" then
    H.check(pt.pattern.proto.places == 0, "gold=hero laid gold in the field")
  else
    H.check(pt.pattern.proto.places > 0, g .. ": laid no places")
    H.check(pt:body() ~= plain, g .. ": the page is as without it")
  end
end

-- A few cells and glints, not all: well under a tenth of the cells.
do
  local pt = page("stars_8_4", { gold = "cells" })
  H.check(pt.pattern.proto.places >= 2 and pt.pattern.proto.places < 0.1 * pt.pattern.cells, "gold=cells laid more than a few")
  pt = page("stars_8_4", { gold = "knobs" })
  H.check(pt.pattern.proto.places == pt.pattern.cells, "gold=knobs: not one knob in every cell")
end

-- A pattern a key cannot use says so, and is painted as it is (without
-- gold in the field for gold).
for name, why in pairs(Proto.NO_CELLS) do
  local plain = page(name):body()
  for _, key in ipairs({ "deviant", "loose" }) do
    local pt = page(name, { [key] = true })
    H.check(warned(pt, "pattern_opts." .. key .. ": " .. name .. " has no cells to turn or move (" .. why .. ")"), name .. ": " .. key .. " not logged")
    H.check(pt:body() == plain, name .. ": " .. key .. " changed the page")
  end
  local pt = page(name, { gold = "cells" })
  H.check(warned(pt, "pattern_opts.gold=cells: " .. name), name .. ": gold=cells not logged")
end
for name in pairs(Proto.NO_CROSSINGS) do
  H.check(warned(page(name, { gold = "crossings" }), "pattern_opts.gold=crossings: " .. name), name .. ": gold=crossings not logged")
end
for name in pairs(Proto.NO_CENTRES) do
  H.check(warned(page(name, { gold = "knobs" }), "pattern_opts.gold=knobs: " .. name), name .. ": gold=knobs not logged")
end

-- A deviant: at most one on a side of the text, whole cells, the same on a
-- page painted twice, and another with another seed.
do
  local pt = page("stars_8_4", { deviant = true })
  local d = pt.pattern.proto.deviants
  H.check(#d >= 1 and #d <= 2, "deviants: not one on each of the two sides")
  local seen = {}
  for _, q in ipairs(d) do
    H.check(not seen[q.side], "deviants: two on the " .. q.side)
    seen[q.side] = true
  end
  H.check(page("stars_8_4", { deviant = true }):body() == pt:body(), "deviants: a page's seed did not decide them")
  H.check(page("stars_8_4", { deviant = true }, { seed = 8 }):body() ~= pt:body(), "deviants: another seed gave the same page")
  H.check(pt:body() ~= page("stars_8_4"):body(), "deviants: the page is as without them")
end

-- A loose plate: it moved out beyond the field, clear of the text, with a
-- dotted path back.
do
  local pt = page("stars_8_4", { loose = true })
  local l = pt.pattern.proto.loose
  H.check(l and l.dots >= 2, "loose: no plate or no path")
  if l then
    local sp = spec()
    local t = sp.text
    local inside = l.to_x > t.x0 and l.to_x < t.x1 and l.to_y > t.y0 and l.to_y < t.y1
    H.check(not inside, "loose: the plate lies on the text")
    H.check(l.to_x > 0 and l.to_x < sp.width and l.to_y > 0 and l.to_y < sp.height, "loose: the plate lies off the page")
  end
  H.check(pt:body() ~= page("stars_8_4"):body(), "loose: the page is as without it")
end

-- The last frame of a growth is the page, with the keys on.
for _, opts in ipairs({ { gold = "knobs" }, { gold = "crossings" }, { deviant = true }, { loose = true } }) do
  Paint.reset_resources()
  local plan = P.plan(spec("stars_8_4", opts), { resolution = 1 })
  H.check(plan.final:body() == page("stars_8_4", opts):body(), "growth: the last frame differs from the page")
end

H.done("pattern_proto")
