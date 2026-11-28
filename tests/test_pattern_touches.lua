-- The pattern touches (lua/flora/pattern_touches.lua; the settings glint,
-- herogilding, deviant and stray): off unless set, a log line for a value or a
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
for _, k in ipairs({ "glint", "herogilding", "deviant", "stray" }) do
  H.check(Settings.PATTERN[k] == "off", k .. " is not off by default")
  H.check(Settings.parse(k .. "=off")[k] == "off", k .. "=off does not parse")
  H.check(not pcall(Settings.parse, k .. "=silver"), k .. "=silver was accepted")
end
-- deviant takes off, on, or a count from 2 to 4.
for _, v in ipairs({ "off", "on", "2", "3", "4" }) do H.check(Settings.parse("deviant=" .. v).deviant == v, "deviant=" .. v .. " does not parse") end
for _, v in ipairs({ "1", "5", "0", "2.5", "many" }) do H.check(not pcall(Settings.parse, "deviant=" .. v), "deviant=" .. v .. " was accepted") end
for _, v in ipairs(Touches.GLINT_ORDER) do H.check(Settings.parse("glint=" .. v).glint == v, "glint=" .. v .. " does not parse") end
H.check(not pcall(Settings.parse, "glint=crossings"), "glint=crossings was accepted")

-- Off as they come: no key, or every key off, paints what a page without
-- them paints, and the page keeps no report.
for _, p in ipairs(Patterns.list) do
  local plain = page(p.name):body()
  local off = page(p.name, { glint = "off", herogilding = "off", deviant = "off", stray = "off" })
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
  for _, key in ipairs({ "herogilding", "deviant", "stray" }) do
    local d = page(nil, { [key] = "maybe" })
    H.check(warned(d, key .. "=maybe is not one of " .. (key == "deviant" and "off, on, 2, 3, 4" or "on, off")), key .. ": unknown value not logged")
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
  for _, key in ipairs({ "deviant", "stray" }) do
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

-- herogilding paints the hero's lines in gold and combines with a glint; with no
-- hero on the page it logs that and paints the page as it is.
do
  local with_hero = { pattern_hero = "rosette", layout = "right", text = { x0 = 40, y0 = 40, x1 = 200, y1 = 230 }, width = 453, height = 256 }
  local plain = page("stars_8_4", nil, with_hero)
  local gold = page("stars_8_4", { herogilding = "on" }, with_hero)
  H.check(plain.pattern.hero ~= nil, "the page has no hero to test herogilding on")
  H.check(gold:body() ~= plain:body() and gold.pattern_warnings == nil, "herogilding=on did not paint the hero in gold")
  local both = page("stars_8_4", { herogilding = "on", glint = "on" }, with_hero)
  H.check(both:body() ~= gold:body() and both.pattern.touches.places > 0, "herogilding and glint do not combine")
  local none = page("stars_8_4", { herogilding = "on" })
  H.check(warned(none, "herogilding=on: the page has no hero") and none:body() == page("stars_8_4"):body(), "herogilding without a hero is not logged and painted as it is")
end

-- The gold of a gilded cell lies within the outline the field's rule was asked
-- about: in an enlarged stars_8_4 band a reservation in the void at an
-- octagon tile's corner clears the star and its strokes, but cut the gold
-- fill, which covers the whole tile. Seeds 24, 25 and 34 gild that cell.
do
  local M = dofile("tests/pattern_touches_suite.lua").M
  local rect = { 16.54, 253.0, 17.54, 254.0 }
  for _, seed in ipairs({ 24, 25, 34 }) do
    local pt, found = M.touched_ink("stars_8_4", "perimeter", "light", { glint = "cells" }, {
      seed = seed, width = 360, height = 480, text = { x0 = 100, y0 = 100, x1 = 300, y1 = 400 }, layout = "perimeter",
      perimeter_width = 40, pattern_scale = 6, pattern_edge = "cell", reserve = { rect } })
    local near = math.huge
    for _, f in ipairs(found) do
      for _, q in ipairs(f.points) do
        local dx, dy = math.max(rect[1] - q[1], 0, q[1] - rect[3]), math.max(rect[2] - q[2], 0, q[2] - rect[4])
        near = math.min(near, math.sqrt(dx * dx + dy * dy) - q[3] - q[4] / 2)
      end
    end
    H.check(near >= pt.pattern.gap - 0.05, string.format("seed %d: gold lies %.2f pt from the reservation, the gap is %.1f", seed, near, pt.pattern.gap))
  end
end

-- A knob on a stray plate is reported where it is painted, on the plate, not
-- at the gap the plate left; and a band's deviants do not depend on the run
-- (an exact tie of two edges was once broken by the order pairs() gave).
do
  local sp = { width = 453, height = 256, text = { x0 = 34, y0 = 30, x1 = 256, y1 = 225 }, layout = "right", seed = 11 }
  local pt = page("stars_8_4", { glint = "knobs", stray = "on" }, sp)
  local rep = pt.pattern.touches
  H.check(rep.stray ~= nil, "no stray plate to hold the knob to")
  if rep.stray then
    local function at_point(x, y)
      for _, q in ipairs(rep.at) do
        if math.abs(q[1] - x) < 1e-6 and math.abs(q[2] - y) < 1e-6 then return true end
      end
      return false
    end
    H.check(at_point(rep.stray.to_x, rep.stray.to_y), "the plate's knob is not reported on the plate")
    H.check(not at_point(rep.stray.x, rep.stray.y), "a knob is reported at the gap the plate left")
  end
  -- A cell exactly as far out of a band's inner rectangle across one edge as
  -- across another lies on a side chosen by a fixed order of the edges (l, r,
  -- b, t), not by whatever order a table gives.
  local Pattern = require("flora.pattern")
  local Rng = require("flora.rng")
  local I = { 100, 100, 260, 380 }
  local ties = { { 80, 80, "l" }, { 280, 80, "r" }, { 80, 400, "l" }, { 280, 400, "r" }, { 180, 80, "b" }, { 180, 400, "t" } }
  for _, tie in ipairs(ties) do
    local x, y = tie[1], tie[2]
    -- Equal excess across the two edges the cell lies out of, for the corners.
    local cell = { x = x, y = y, verts = { { x - 3, y - 3 }, { x + 3, y - 3 }, { x + 3, y + 3 }, { x - 3, y + 3 } } }
    local tpt = {}
    local S = assert(Touches.new({ deviant = "on" }, Patterns.by_name.kikko, function() end, tpt))
    local ctx = { kept = { { cell = cell, a = 1 } }, size = 6, width = 2, text = { x0 = I[1], y0 = I[2], x1 = I[3], y1 = I[4] },
      W = 360, top = 480, rng = Rng.new(7), warn = function() end, grid = Pattern.cell_grid, band = { I = I },
      place = function() return true end, measure = function() return 100, true end, pt = tpt }
    Touches.plan(S, ctx)
    local d = S.report.deviants[1]
    H.check(d ~= nil, string.format("a cell at %d, %d outside a band's inner rectangle takes no deviant", x, y))
    if d then H.check(d.side == tie[3], string.format("a cell at %d, %d lies on side %s, not %s", x, y, tostring(d.side), tie[3])) end
  end
end

-- The last frame of a growth is the page, with the keys on.
for _, set in ipairs({ { glint = "knobs" }, { glint = "on" }, { deviant = "on" }, { stray = "on" } }) do
  Paint.reset_resources()
  local plan = P.plan(spec("stars_8_4", set), { resolution = 1 })
  H.check(plan.final:body() == page("stars_8_4", set):body(), "growth: the last frame differs from the page")
end

-- The invariants of the places, measured on the pages' own cells.
local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
local function rect_dist(x, y, r)
  local dx, dy = math.max(r[1] - x, 0, x - r[3]), math.max(r[2] - y, 0, y - r[4])
  return math.sqrt(dx * dx + dy * dy)
end

-- The kept cells' typical spacing, and each one's neighbours within 1.5 of it.
local function neighbours(kept)
  local nn = {}
  for i, k in ipairs(kept) do
    local best = math.huge
    for j, o in ipairs(kept) do
      if i ~= j then best = math.min(best, dist(k.cell.x, k.cell.y, o.cell.x, o.cell.y)) end
    end
    nn[#nn + 1] = best
  end
  table.sort(nn)
  local med = nn[math.ceil(#nn / 2)]
  local degree, top = {}, 0
  for i, k in ipairs(kept) do
    local n = 0
    for j, o in ipairs(kept) do
      if i ~= j and dist(k.cell.x, k.cell.y, o.cell.x, o.cell.y) < 1.5 * med then n = n + 1 end
    end
    degree[i] = n
    top = math.max(top, n)
  end
  return med, degree, top
end

local SLIDE = { width = 453, height = 256, text = { x0 = 34, y0 = 30, x1 = 256, y1 = 225 }, layout = "right" }

-- A deviant is a whole cell inside the field, never a stray edge cell or a
-- fragment of one: at least 60 % of the neighbours a cell has in the field.
for _, name in ipairs({ "stars_8_4", "kikko", "asanoha" }) do
  for seed = 1, 20 do
    local pt = page(name, { deviant = "on" }, { width = SLIDE.width, height = SLIDE.height, text = SLIDE.text, layout = SLIDE.layout, seed = seed })
    local kept = pt.pattern.kept
    local _, degree, top = neighbours(kept)
    for _, d in ipairs(pt.pattern.touches.deviants) do
      for i, k in ipairs(kept) do
        if dist(k.cell.x, k.cell.y, d.x, d.y) < 1e-6 then
          H.check(degree[i] >= 0.6 * top, string.format("%s seed %d: a deviant with %d of %d neighbours", name, seed, degree[i], top))
        end
      end
    end
  end
end

-- In a perimeter band at most one deviant lies along each side of the
-- paper, whatever the edge and the pattern: the places the painting turns
-- (Touches.painters), by the paper's edge nearest each.
do
  local turned
  local painters = Touches.painters
  rawset(Touches, "painters", function(plan, pl, c, ink, pt)
    if pl.deviant then
      local x, y = c.x, c.y
      if pt.frame_fn then x, y = pt.frame_fn(x, y) end
      turned[#turned + 1] = { x, y }
    end
    return painters(plan, pl, c, ink, pt)
  end)
  for _, name in ipairs({ "stars_8_4", "kikko", "asanoha", "overlapping_circles" }) do
    for _, edge in ipairs({ "auto", "cell", "border" }) do
      turned = {}
      local extra = { width = 360, height = 480, text = { x0 = 60, y0 = 60, x1 = 300, y1 = 420 }, layout = "perimeter", perimeter_width = 24, seed = 5 }
      if edge ~= "auto" then extra.pattern_edge = edge end
      page(name, { deviant = "on" }, extra)
      local per = { l = 0, r = 0, b = 0, t = 0 }
      for _, q in ipairs(turned) do
        local d = { l = q[1], r = 360 - q[1], b = q[2], t = 480 - q[2] }
        local best = "l"
        for k, v in pairs(d) do if v < d[best] then best = k end end
        per[best] = per[best] + 1
      end
      for side, n in pairs(per) do
        H.check(n <= 1, string.format("%s edge=%s: %d deviants along side %s", name, edge, n, side))
      end
    end
  end
  rawset(Touches, "painters", painters)
end

-- A stray plate and its path keep the field's own distance from the text
-- and clear of every reserved rectangle, or none is laid.
for _, name in ipairs({ "stars_8_4", "kikko" }) do
  for seed = 1, 12 do
    local reserve = { { 300, 60, 340, 100 } }
    local pt = page(name, { stray = "on" }, { width = SLIDE.width, height = SLIDE.height, text = SLIDE.text, layout = SLIDE.layout, seed = seed, reserve = reserve })
    local l = pt.pattern.touches.stray
    if l then
      local keep = { { 34, 30, 256, 225 }, reserve[1] }
      local field = math.huge
      for _, k in ipairs(pt.pattern.kept) do
        -- The nearest the cell's outline comes (the field's own distance is
        -- an outline's, the plate's is held to it).
        local c = k.cell
        local corners = c.circle and { { c.circle[1], c.circle[2] } } or c.verts
        local rad = c.circle and c.circle[3] or 0
        for _, r in ipairs(keep) do
          for _, v in ipairs(corners) do field = math.min(field, rect_dist(v[1], v[2], r) - rad) end
        end
      end
      H.check(l.points and #l.points > 0, name .. " seed " .. seed .. ": the report keeps no points")
      for _, q in ipairs(l.points or {}) do
        for _, r in ipairs(keep) do
          H.check(rect_dist(q[1], q[2], r) >= field - 0.5 * pt.pattern.touches.spacing - 1e-6,
            string.format("%s seed %d: a point of the stray plate %.1f from a rectangle the field keeps %.1f from", name, seed, rect_dist(q[1], q[2], r), field))
        end
      end
    end
  end
end

-- A pattern that draws no band core (its bands have none, as seigaiha's
-- discs; or a core under 0.6 pt) is painted as without the key, and the log
-- says so: glint=core changes the core of a band and nothing else.
for _, name in ipairs({ "asanoha", "overlapping_circles", "shippo", "seigaiha", "penrose_rhombs" }) do
  local pt = page(name, { glint = "core" })
  H.check(pt:body() == page(name):body(), name .. ": glint=core changed a page that draws no band core")
  H.check(warned(pt, "glint=core: " .. name .. " draws no band core"), name .. ": a core that is not drawn is not logged")
  H.check(pt.pattern.touches.places == 0, name .. ": places counted for a core that is not drawn")
end
H.check(not warned(page("stars_8_4", { glint = "core" }), "glint=core"), "stars_8_4: logged a core that is drawn")

H.done("pattern_touches")
