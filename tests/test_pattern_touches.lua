-- The pattern touches (lua/flora/pattern_touches.lua; the settings glint,
-- herogold, deviant and loose): off unless set, a log line for a value or a
-- pattern they cannot take, and the places they lay.
local H = dofile("tests/helper.lua")
local Compose = require("flora.compose")
local Paint = require("flora.paint")
local P = require("flora.progression")
local Patterns = require("flora.patterns")
local Settings = require("flora.settings")
local Touches = require("flora.pattern_touches")

-- A page of `name` with settings `set` ({ glint = "on", ... }).
local function spec(name, set, extra)
  local sp = { width = 360, height = 270, text = { x0 = 130, y0 = 40, x1 = 230, y1 = 230 }, seed = 7,
    layout = "centered", pattern = { [name or "stars_8_4"] = 1 } }
  for k, v in pairs(set or {}) do sp[Settings.SPEC[k]] = v end
  for k, v in pairs(extra or {}) do sp[k] = v end
  return sp
end

local function page(name, set, extra)
  Paint.reset_resources()
  return Compose.page(spec(name, set, extra))
end

local function warned(pt, text)
  for _, w in ipairs(pt.pattern_warnings or {}) do
    if w:find(text, 1, true) then return true end
  end
  return false
end

-- The keys are settings: they parse, default to off, and an unknown value
-- is an error as any key's.
for _, k in ipairs({ "glint", "herogold", "deviant", "loose" }) do
  H.check(Settings.PATTERN[k] == "off", k .. " is not off by default")
  H.check(Settings.parse(k .. "=off")[k] == "off", k .. "=off does not parse")
  H.check(not pcall(Settings.parse, k .. "=silver"), k .. "=silver was accepted")
end
for _, v in ipairs(Touches.GLINT_ORDER) do H.check(Settings.parse("glint=" .. v).glint == v, "glint=" .. v .. " does not parse") end
H.check(not pcall(Settings.parse, "glint=crossings"), "glint=crossings was accepted")

-- Off as they come: no key, or every key off, paints what a page without
-- them paints, and the page keeps no report.
for _, p in ipairs(Patterns.list) do
  local plain = page(p.name):body()
  local off = page(p.name, { glint = "off", herogold = "off", deviant = "off", loose = "off" })
  H.check(off:body() == plain, p.name .. ": keys set to off change the page")
  H.check(off.pattern.touches == nil, p.name .. ": keys set to off leave a report")
end

-- A value that is none of the key's, given to a page straight (a spec the
-- parser did not see), is logged and the key left off.
do
  local plain = page():body()
  local g = page(nil, { glint = "silver" })
  H.check(warned(g, "glint=silver is not one of off, on, core, cells, knobs"), "unknown glint value not logged")
  H.check(g:body() == plain, "an unknown glint value changed the page")
  for _, key in ipairs({ "herogold", "deviant", "loose" }) do
    local d = page(nil, { [key] = "maybe" })
    H.check(warned(d, key .. "=maybe is not one of on, off"), key .. ": unknown value not logged")
    H.check(d:body() == plain, key .. ": an unknown value changed the page")
  end
end

-- Every glint value, on a pattern that can take it, paints something else
-- and lays places.
for _, g in ipairs({ "on", "core", "cells", "knobs" }) do
  local plain = page("stars_8_4"):body()
  local pt = page("stars_8_4", { glint = g })
  H.check(pt.pattern.touches and pt.pattern.touches.places > 0, g .. ": laid no places")
  H.check(pt.pattern_warnings == nil, g .. ": logged on a pattern that takes it")
  H.check(pt:body() ~= plain, g .. ": the page is as without it")
end

-- A few cells and glints, not all: well under a tenth of the cells.
do
  local pt = page("stars_8_4", { glint = "cells" })
  H.check(pt.pattern.touches.places >= 2 and pt.pattern.touches.places < 0.1 * pt.pattern.cells, "glint=cells laid more than a few")
  pt = page("stars_8_4", { glint = "knobs" })
  H.check(pt.pattern.touches.places == pt.pattern.cells, "glint=knobs: not one knob in every cell")
end

-- A pattern a key cannot use says so, and is painted as without the key.
for name, why in pairs(Touches.NO_CELLS) do
  local plain = page(name):body()
  for _, key in ipairs({ "deviant", "loose" }) do
    local pt = page(name, { [key] = "on" })
    H.check(warned(pt, key .. "=on: " .. name .. " has no cells to " .. (key == "deviant" and "turn" or "move") .. " (" .. why .. ")"), name .. ": " .. key .. " not logged")
    H.check(pt:body() == plain, name .. ": " .. key .. " changed the page")
  end
  local pt = page(name, { glint = "cells" })
  H.check(warned(pt, "glint=cells: " .. name), name .. ": glint=cells not logged")
  H.check(pt:body() == plain, name .. ": glint=cells changed the page")
end
for name in pairs(Touches.NO_CROSSINGS) do
  local pt = page(name, { glint = "on" })
  H.check(warned(pt, "glint=on: " .. name), name .. ": glint=on not logged")
  H.check(pt:body() == page(name):body(), name .. ": glint=on changed the page")
end
for name in pairs(Touches.NO_CENTRES) do
  local pt = page(name, { glint = "knobs" })
  H.check(warned(pt, "glint=knobs: " .. name), name .. ": glint=knobs not logged")
  H.check(pt:body() == page(name):body(), name .. ": glint=knobs changed the page")
end

-- The last frame of a growth is the page, with the keys on.
for _, set in ipairs({ { glint = "knobs" }, { glint = "on" }, { deviant = "on" }, { loose = "on" } }) do
  Paint.reset_resources()
  local plan = P.plan(spec("stars_8_4", set), { resolution = 1 })
  H.check(plan.final:body() == page("stars_8_4", set):body(), "growth: the last frame differs from the page")
end

H.done("pattern_touches")
