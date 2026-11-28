-- The invariants of the pattern touches (lua/flora/pattern_touches.lua; the
-- settings glint, herogilding, deviant and stray) over six patterns of
-- different kinds, a field beside the text and a perimeter band, on one
-- backdrop, and proof that each fails when it is broken (the module's
-- source mutated and the check run again). tests/test_pattern_touches_matrix_1.lua
-- runs it on paper and _2 on the dark backdrop.
--
--   off          every key off paints the page a page without them paints
--   gold         the gold of glint lies at the places the report names,
--                none elsewhere (counted from the painting); a core that is
--                drawn is gold, one that is not is logged
--   deviant      whole cells inside the field, at most one along a side
--   stray        at most one plate, in the page, keeping the field's own
--                distance from what it keeps clear of
--   unsupported  a pattern without what a key needs logs it and is painted
--                as without the key
--   seed         the same seed gives the same page
local H = dofile("tests/helper.lua")
local Compose = require("flora.compose")
local Paint = require("flora.paint")
local Settings = require("flora.settings")

local M = {}

M.PATTERNS = { "stars_8_4", "overlapping_circles", "asanoha", "kikko", "truchet", "celtic_knot" }
M.LAYOUTS = {
  field = { width = 360, height = 270, text = { x0 = 130, y0 = 40, x1 = 230, y1 = 230 }, layout = "centered", seed = 7 },
  perimeter = { width = 360, height = 480, text = { x0 = 60, y0 = 60, x1 = 300, y1 = 420 }, layout = "perimeter", perimeter_width = 24, seed = 5 },
}
M.LAYOUT_ORDER = { "field", "perimeter" }
-- How far a stray plate lies from its gap at least, in cell widths (twice
-- the farthest corner or the radius), set after measuring the cells.
M.MIN_MOVE = 1.15
M.KEYS = { "glint", "herogilding", "deviant", "stray" }

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
local function rect_dist(x, y, r)
  local dx, dy = math.max(r[1] - x, 0, x - r[3]), math.max(r[2] - y, 0, y - r[4])
  return math.sqrt(dx * dx + dy * dy)
end

-- A page of `name` on `layout` and `backdrop` with settings `set`.
local function spec(name, layout, backdrop, set, extra)
  local sp = { pattern = { [name] = 1 }, backdrop = backdrop }
  for k, v in pairs(M.LAYOUTS[layout]) do sp[k] = v end
  for k, v in pairs(set or {}) do sp[Settings.SPEC[k]] = v end
  for k, v in pairs(extra or {}) do sp[k] = v end
  return sp
end
local function page(name, layout, backdrop, set, extra)
  Paint.reset_resources()
  return Compose.page(spec(name, layout, backdrop, set, extra))
end
M.page = page

local function warned(pt, text)
  for _, w in ipairs(pt.pattern_warnings or {}) do
    if w:find(text, 1, true) then return true end
  end
  return false
end

-- Run fn with Paint:fill and Paint:stroke watched: calls `seen(kind, pt,
-- cmds)` for each in gold.
local function watching(seen, fn)
  local fill, stroke = Paint.fill, Paint.stroke
  rawset(Paint, "fill", function(self, cmds, rgb, ...)
    if rgb == Paint.palette.gold then seen("fill", self, cmds) end
    return fill(self, cmds, rgb, ...)
  end)
  rawset(Paint, "stroke", function(self, cmds, rgb, ...)
    if rgb == Paint.palette.gold then seen("stroke", self, cmds) end
    return stroke(self, cmds, rgb, ...)
  end)
  local ok, err = pcall(fn)
  rawset(Paint, "fill", fill)
  rawset(Paint, "stroke", stroke)
  if not ok then error(err, 0) end
end

-- Where a painted path lies, on the page: the mean of its points.
local function centre(pt, cmds)
  local path = cmds
  if type(cmds[1]) == "table" and type(cmds[1][1]) == "table" then path = cmds[1] end
  local sx, sy, n = 0, 0, 0
  for _, c in ipairs(path) do
    local x, y
    if c[1] == "o" then x, y = c[2], c[3]
    elseif c[1] == "c" then x, y = c[6], c[7]
    elseif c[1] == "m" or c[1] == "l" then x, y = c[2], c[3] end
    if x then sx, sy, n = sx + x, sy + y, n + 1 end
  end
  local x, y = sx / math.max(n, 1), sy / math.max(n, 1)
  if pt.frame_fn then x, y = pt.frame_fn(x, y) end
  return x, y
end

local function supports(name, value)
  local T = require("flora.pattern_touches")
  if value == "cells" then return not T.NO_CELLS[name] end
  if value == "knobs" then return not T.NO_CENTRES[name] end
  if value == "on" then return not T.NO_CROSSINGS[name] end
  return true
end

-- Every key off is the page without keys.
function M.off(backdrop, only)
  local fs, pages = {}, 0
  for _, name in ipairs(only or M.PATTERNS) do
    for _, layout in ipairs(M.LAYOUT_ORDER) do
      local plain = page(name, layout, backdrop):body()
      local off = page(name, layout, backdrop, { glint = "off", herogilding = "off", deviant = "off", stray = "off" })
      pages = pages + 2
      if off:body() ~= plain then fs[#fs + 1] = string.format("%s %s %s: keys set to off change the page", name, layout, backdrop) end
      if off.pattern.touches then fs[#fs + 1] = string.format("%s %s %s: keys set to off leave a report", name, layout, backdrop) end
    end
  end
  return pages, fs
end

-- The gold of glint = on, cells, knobs lies at the reported places and only
-- there; a core that is drawn is gold and one that is not is logged.
function M.gold(backdrop, only)
  local fs, pages = {}, 0
  for _, name in ipairs(only or M.PATTERNS) do
    for _, layout in ipairs(M.LAYOUT_ORDER) do
      local plain = page(name, layout, backdrop)
      for _, value in ipairs({ "on", "cells", "knobs", "core" }) do
        local tag = string.format("%s %s %s glint=%s", name, layout, backdrop, value)
        local fills, strokes = {}, 0
        local pt
        watching(function(kind, p, cmds)
          if kind == "fill" then fills[#fills + 1] = { centre(p, cmds) } else strokes = strokes + 1 end
        end, function() pt = page(name, layout, backdrop, { glint = value }) end)
        pages = pages + 1
        local rep = pt.pattern.touches
        if not supports(name, value) then
          if pt:body() ~= plain:body() then fs[#fs + 1] = tag .. ": a pattern without the geometry changed the page" end
          if not pt.pattern_warnings then fs[#fs + 1] = tag .. ": an unsupported key is not logged" end
        elseif value == "core" then
          local gold = 0
          if rep then gold = rep.places end
          if (gold > 0) == warned(pt, "glint=core") then fs[#fs + 1] = tag .. ": the core is both laid and logged, or neither" end
        else
          if not rep or rep.places == 0 then
            fs[#fs + 1] = tag .. ": no places laid"
          else
            local med = rep.spacing
            for _, f in ipairs(fills) do
              local ok = false
              for _, q in ipairs(rep.at) do
                if dist(f[1], f[2], q[1], q[2]) <= 0.6 * med then ok = true break end
              end
              if not ok then fs[#fs + 1] = string.format("%s: gold painted at %.1f, %.1f, no place of the report", tag, f[1], f[2]) break end
            end
            if #fills < rep.places then fs[#fs + 1] = string.format("%s: %d places, %d gold fills", tag, rep.places, #fills) end
          end
        end
        if value ~= "core" and strokes > 0 and rep and rep.places > 0 and not (layout == "perimeter") then
          -- strokes of gold outside the field's own accent: none, the accent turned to the core's
          fs[#fs + 1] = tag .. ": gold strokes in the field"
        end
      end
    end
  end
  return pages, fs
end

-- Deviants: on is one on the page, a count of 2 to 4 that many at most, on
-- different edges (of the paper in a band, of the text in a field) before
-- two share one and never close together; whole cells inside the field.
function M.deviant(backdrop, only, seeds, values)
  local fs, pages = {}, 0
  local T = require("flora.pattern_touches")
  for _, name in ipairs(only or M.PATTERNS) do
    for _, layout in ipairs(M.LAYOUT_ORDER) do
      for _, seed in ipairs(seeds or { M.LAYOUTS[layout].seed }) do
        for _, value in ipairs(values or { "on", "2", "3", "4" }) do
          local tag = string.format("%s %s %s seed %d deviant=%s", name, layout, backdrop, seed, value)
          local pt = page(name, layout, backdrop, { deviant = value }, { seed = seed })
          pages = pages + 1
          if T.NO_CELLS[name] then
            if pt:body() ~= page(name, layout, backdrop, nil, { seed = seed }):body() then fs[#fs + 1] = tag .. ": a pattern without cells changed the page" end
            if not pt.pattern_warnings then fs[#fs + 1] = tag .. ": unsupported and not logged" end
          else
            local rep = pt.pattern.touches
            local L = M.LAYOUTS[layout]
            local want = value == "on" and 1 or tonumber(value)
            local list = rep and rep.deviants or {}
            if #list > want then fs[#fs + 1] = string.format("%s: %d on the page", tag, #list) end
            if #list < want and not warned(pt, "deviant=" .. value .. ": room for") then
              fs[#fs + 1] = string.format("%s: %d of %d laid and no line says why", tag, #list, want)
            end
            -- Different edges before the same one twice.
            local per, parts = {}, layout == "perimeter" and 4 or 2
            for _, d in ipairs(list) do
              local part
              if layout == "perimeter" then
                local e = { l = d.x, r = L.width - d.x, b = d.y, t = L.height - d.y }
                part = "l"
                for k, v in pairs(e) do if v < e[part] then part = k end end
              else
                part = d.x < L.text.x0 and "l" or "r"
              end
              per[part] = (per[part] or 0) + 1
            end
            for part, n in pairs(per) do
              if n > math.ceil(want / parts) then fs[#fs + 1] = string.format("%s: %d on edge %s", tag, n, part) end
            end
            -- Never two close together.
            local apart = 3 * (rep and rep.spacing or 0)
            for i = 1, #list do
              for j = i + 1, #list do
                if dist(list[i].x, list[i].y, list[j].x, list[j].y) < apart then fs[#fs + 1] = tag .. ": two close together" end
              end
            end
            -- Whole cells with most of the field's neighbours.
            local kept = pt.pattern.kept
            local nn = {}
            for i, k in ipairs(kept) do
              local best = math.huge
              for j, o in ipairs(kept) do
                if i ~= j then best = math.min(best, dist(k.cell.x, k.cell.y, o.cell.x, o.cell.y)) end
              end
              nn[#nn + 1] = best
            end
            table.sort(nn)
            local med = nn[math.ceil(#nn / 2)] or 0
            local degree, top = {}, 0
            for i, k in ipairs(kept) do
              local n = 0
              for j, o in ipairs(kept) do
                if i ~= j and dist(k.cell.x, k.cell.y, o.cell.x, o.cell.y) < 1.5 * med then n = n + 1 end
              end
              degree[i] = n
              top = math.max(top, n)
            end
            for _, d in ipairs(list) do
              for i, k in ipairs(kept) do
                -- Strips report in page coordinates, cells in their own.
                if layout == "field" and dist(k.cell.x, k.cell.y, d.x, d.y) < 1e-6 and degree[i] < 0.6 * top then
                  fs[#fs + 1] = string.format("%s: a deviant with %d of %d neighbours", tag, degree[i], top)
                end
              end
            end
          end
        end
      end
    end
  end
  return pages, fs
end

-- The stray plate: at most one, on the page, no nearer what the field keeps
-- clear of than the field's own cells.
function M.stray(backdrop, only, seeds)
  local fs, pages = {}, 0
  for _, name in ipairs(only or M.PATTERNS) do
    for _, layout in ipairs(M.LAYOUT_ORDER) do
      for _, seed in ipairs(seeds or (layout == "field" and { 7, 11, 13 } or { 5 })) do
        local tag = string.format("%s %s %s seed %d stray", name, layout, backdrop, seed)
        local L = M.LAYOUTS[layout]
        local reserve = { { 20, 20, 50, 50 } }
        local pt = page(name, layout, backdrop, { stray = "on" }, { seed = seed, reserve = reserve })
        pages = pages + 1
        if require("flora.pattern_touches").NO_CELLS[name] then
          if pt:body() ~= page(name, layout, backdrop, nil, { seed = seed, reserve = reserve }):body() then fs[#fs + 1] = tag .. ": a pattern without cells changed the page" end
        else
          local l = pt.pattern.touches and pt.pattern.touches.stray
          if l and layout == "field" then
            local keep = { { L.text.x0, L.text.y0, L.text.x1, L.text.y1 }, reserve[1] }
            local field = math.huge
            for _, k in ipairs(pt.pattern.kept) do
              for _, r in ipairs(keep) do field = math.min(field, rect_dist(k.cell.x, k.cell.y, r)) end
            end
            -- Clear of every cell the page draws, by a fraction of its width.
            if l.clear < require("flora.pattern_touches").MIN_CLEAR * l.width - 1e-6 then
              fs[#fs + 1] = string.format("%s: the plate lies %.2f cell widths from the nearest cell", tag, l.clear / l.width)
            end
            -- It lies about a cell's width or more from its gap.
            for _, k in ipairs(pt.pattern.kept) do
              if dist(k.cell.x, k.cell.y, l.x, l.y) < 1e-6 then
                local r = 0
                for _, v in ipairs(k.cell.circle and { { k.cell.circle[1] + k.cell.circle[3], k.cell.circle[2] } } or k.cell.tile or k.cell.verts) do
                  r = math.max(r, dist(v[1], v[2], k.cell.x, k.cell.y))
                end
                if dist(l.x, l.y, l.to_x, l.to_y) < M.MIN_MOVE * 2 * r - 1e-6 then
                  fs[#fs + 1] = string.format("%s: the plate moved %.2f cell widths", tag, dist(l.x, l.y, l.to_x, l.to_y) / (2 * r))
                end
              end
            end
            for _, q in ipairs(l.points) do
              if q[1] < 0 or q[1] > L.width or q[2] < 0 or q[2] > L.height then fs[#fs + 1] = tag .. ": a point off the page" end
              for _, r in ipairs(keep) do
                if rect_dist(q[1], q[2], r) < field - 0.5 * pt.pattern.touches.spacing - 1e-6 then
                  fs[#fs + 1] = string.format("%s: a point %.1f from a rectangle the field keeps %.1f from", tag, rect_dist(q[1], q[2], r), field)
                  break
                end
              end
            end
          end
        end
      end
    end
  end
  return pages, fs
end

-- A key changes only its own target: the colours the hero and the text's
-- frame (edge=border, guilloche, a band's rule) are painted in are the page's
-- own whatever the key, bar the hero's for herogilding; and herogilding on a
-- page with no hero is the page without it, byte for byte (under lacquer the
-- band is gold already, so the hero's does not change). Checked on the
-- inks the page reports (edge_inks, hero_inks) over each edge, a hero or
-- none, and each finish.
M.KEY_VALUES = {
  { "glint", "on" }, { "glint", "core" }, { "glint", "cells" }, { "glint", "knobs" },
  { "herogilding", "on" }, { "deviant", "on" }, { "stray", "on" },
}
local INK_ROLES = { "band", "core", "accent", "line", "band0", "line0" }
local function same_colour(a, b)
  if a == nil or b == nil then return a == b end
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
local function same_inks(a, b)
  for _, k in ipairs(INK_ROLES) do
    if not same_colour(a[k], b[k]) then return false, k end
  end
  return true
end

function M.target(backdrop, only)
  local fs, pages = {}, 0
  local sweeps = {}
  for _, name in ipairs(only or { "stars_8_4", "asanoha" }) do
    for _, edge in ipairs({ "dissolve", "border", "guilloche" }) do
      for _, hero in ipairs({ "none", "rosette" }) do sweeps[#sweeps + 1] = { name, edge, hero, "filled" } end
    end
    for _, finish in ipairs(name == "asanoha" and { "lines", "lacquer" } or { "lines" }) do
      sweeps[#sweeps + 1] = { name, "border", "rosette", finish }
    end
  end
  local extra = { layout = "right", text = { x0 = 34, y0 = 30, x1 = 256, y1 = 225 }, width = 453, height = 256, seed = 3 }
  for _, sw in ipairs(sweeps) do
    local name, edge, hero, finish = sw[1], sw[2], sw[3], sw[4]
    local function render(set)
      local e = { pattern_edge = edge, pattern_hero = hero, pattern_finish = finish }
      for k, v in pairs(extra) do e[k] = v end
      Paint.reset_resources()
      return Compose.page(spec(name, "field", backdrop, set, e))
    end
    local off = render(nil)
    pages = pages + 1
    for _, kv in ipairs(M.KEY_VALUES) do
      local tag = string.format("%s edge=%s hero=%s finish=%s %s=%s", name, edge, hero, finish, kv[1], kv[2])
      local on = render({ [kv[1]] = kv[2] })
      pages = pages + 1
      local ok, role = same_inks(off.pattern.edge_inks, on.pattern.edge_inks)
      if not ok then fs[#fs + 1] = tag .. ": the frame's " .. role .. " changed" end
      if kv[1] ~= "herogilding" then
        ok, role = same_inks(off.pattern.hero_inks, on.pattern.hero_inks)
        if not ok then fs[#fs + 1] = tag .. ": the hero's " .. role .. " changed" end
      elseif hero == "none" and on:body() ~= off:body() then
        fs[#fs + 1] = tag .. ": a page with no hero changed"
      elseif hero ~= "none" and finish ~= "lacquer" and on:body() == off:body() then
        fs[#fs + 1] = tag .. ": the hero was not gilded"
      end
    end
  end
  return pages, fs
end

-- What the touches paint keeps the field's distance from the text and from a
-- reserved rectangle, measured on the painting: every path painted for a
-- touched cell (its cell, a knob, a glint, a dotted path), its points and
-- half its stroke, no nearer than the page's gap. `reserve` puts a
-- rectangle in the field, or in the band.
M.RESERVES = { field = { { 30, 90, 70, 130 } }, perimeter = { { 6, 200, 30, 260 } } }

-- The page's touched ink as { kind, margin } pairs, `margin` how far
-- beyond the gap its nearest point lies (negative inside it).
local function touched_ink(name, layout, backdrop, set, extra, rects)
  local Touches = require("flora.pattern_touches")
  local flag, found = nil, {}
  local painters = Touches.painters
  rawset(Touches, "painters", function(plan, pl, c, ink, pt)
    local h = painters(plan, pl, c, ink, pt)
    -- What the cell is painted as, and what it paints beyond its own: a
    -- knob and glints in `late`, a gilded cell's underfill, a stray's dots.
    local kind = pl.stray and "moved" or pl.deviant and "turned" or "cell"
    for _, f in ipairs({ "construct", "paint", "late" }) do
      local g = h[f]
      if g then
        h[f] = function(...)
          local was = flag
          flag = { kind = f == "late" and (pl.glints and "glint" or "knob") or kind, gilt = pl.gilt, stray = pl.stray }
          local r = g(...)
          flag = was
          return r
        end
      end
    end
    return h
  end)
  local fill, stroke = Paint.fill, Paint.stroke
  local function record(self, cmds, width, rgb)
    if not flag then return end
    local pj = self:_pj()
    local paths = cmds
    if not (type(cmds[1]) == "table" and type(cmds[1][1]) == "table") then paths = { cmds } end
    local best = math.huge
    for _, path in ipairs(paths) do
      for _, c in ipairs(path) do
        local pts, r = {}, 0
        if c[1] == "o" then pts[1], r = { c[2], c[3] }, c[4]
        elseif c[1] == "c" then pts = { { c[2], c[3] }, { c[4], c[5] }, { c[6], c[7] } }
        elseif c[1] == "m" or c[1] == "l" then pts[1] = { c[2], c[3] } end
        for _, q in ipairs(pts) do
          local x, y = q[1], q[2]
          if pj then x, y = pj(x, y) end
          for _, rect in ipairs(rects) do best = math.min(best, rect_dist(x, y, rect) - r - width / 2) end
        end
      end
    end
    local kind = flag.kind
    if flag.gilt and rgb == Paint.palette.gold and kind == "cell" then kind = "gilt" end
    if flag.stray and paths[1] and paths[1][1] and paths[1][1][1] == "o" and #paths > 1 then kind = "dots" end
    found[#found + 1] = { kind = kind, d = best }
  end
  rawset(Paint, "fill", function(self, cmds, rgb, ...) record(self, cmds, 0, rgb); return fill(self, cmds, rgb, ...) end)
  rawset(Paint, "stroke", function(self, cmds, rgb, width, ...) record(self, cmds, width or 0, rgb); return stroke(self, cmds, rgb, width, ...) end)
  local ok, pt = pcall(function() return page(name, layout, backdrop, set, extra) end)
  rawset(Paint, "fill", fill)
  rawset(Paint, "stroke", stroke)
  rawset(Touches, "painters", painters)
  if not ok then error(pt, 0) end
  return pt, found
end

function M.ink(backdrop, only, seeds, values, report, combos)
  local fs, pages = {}, 0
  -- A field; a band of whole cells (no clip along what it keeps clear of);
  -- and a band cut along it by clip (edge=border), whose ink is measured
  -- before the clip cuts it.
  combos = combos or {
    { "field", nil, false }, { "field", nil, true }, { "perimeter", "cell", true }, { "perimeter", "border", true },
  }
  for _, name in ipairs(only or M.PATTERNS) do
    for _, combo in ipairs(combos) do
      local layout, edge, reserved = combo[1], combo[2], combo[3]
      for _, seed in ipairs(seeds or { 7 }) do
        local L = M.LAYOUTS[layout]
        local rects = { { L.text.x0, L.text.y0, L.text.x1, L.text.y1 } }
        local extra = { seed = seed, pattern_edge = edge }
        if reserved then
          rects[2] = M.RESERVES[layout][1]
          extra.reserve = M.RESERVES[layout]
        end
        for _, kv in ipairs(values or { { "glint", "on" }, { "glint", "knobs" }, { "glint", "cells" }, { "deviant", "4" }, { "stray", "on" } }) do
          local pt, found = touched_ink(name, layout, backdrop, { [kv[1]] = kv[2] }, extra, rects)
          pages = pages + 1
          local gap = pt.pattern.gap or 6
          for _, f in ipairs(found) do
            local tag = string.format("%s %s%s %s seed %d%s %s=%s %s", name, layout, edge and ("/" .. edge) or "", backdrop, seed, reserved and " reserve" or "", kv[1], kv[2], f.kind)
            if report then report[f.kind] = math.min(report[f.kind] or math.huge, f.d - gap) end
            if f.kind ~= "cell" and f.d < gap - 0.3 then fs[#fs + 1] = string.format("%s: ink %.2f pt from what the field keeps clear of, the gap %.1f", tag, f.d, gap) end
          end
        end
      end
    end
  end
  return pages, fs
end

-- Fields of 0, 1 and 2 cells (a narrow strip beside the text, or none at
-- all): every key and value leaves no number that is not finite in the
-- painting, does not fail, and says so in the log where nothing can be laid.
M.TINY = {
  { "stars_8_4", 4 }, { "stars_8_4", 8 }, { "kikko", 4 }, { "kikko", 8 }, { "kikko", 12 },
  { "asanoha", 4 }, { "asanoha", 8 }, { "overlapping_circles", 4 }, { "celtic_knot", 8 }, { "sikku_kolam", 8 },
}
M.ALL_VALUES = {
  { "glint", "on" }, { "glint", "core" }, { "glint", "cells" }, { "glint", "knobs" }, { "herogilding", "on" },
  { "deviant", "on" }, { "deviant", "2" }, { "deviant", "4" }, { "stray", "on" },
}

function M.finite(backdrop, only)
  local fs, pages = {}, 0
  for _, case in ipairs(only or M.TINY) do
    local name, x0 = case[1], case[2]
    for _, kv in ipairs(M.ALL_VALUES) do
      local tag = string.format("%s text from %d %s %s=%s", name, x0, backdrop, kv[1], kv[2])
      local sp = { width = 200, height = 120, text = { x0 = x0, y0 = 10, x1 = 190, y1 = 110 }, seed = 3, layout = "left",
        pattern = { [name] = 1 }, backdrop = backdrop, [Settings.SPEC[kv[1]]] = kv[2] }
      Paint.reset_resources()
      local ok, pt = pcall(Compose.page, sp)
      pages = pages + 1
      if not ok then
        fs[#fs + 1] = tag .. ": " .. tostring(pt)
      else
        local body = pt:body()
        if body:find("%f[%w]inf%f[%W]") or body:find("%f[%w]nan%f[%W]") or body:find("%-inf") then fs[#fs + 1] = tag .. ": a number that is not finite in the painting" end
        local rep = pt.pattern and pt.pattern.touches
        if rep and rep.spacing and (rep.spacing ~= rep.spacing or rep.spacing == math.huge) then fs[#fs + 1] = tag .. ": a spacing that is not finite" end
        local laid = rep and (rep.places > 0 or #rep.deviants > 0 or rep.stray)
        if rep and not laid and not pt.pattern_warnings then fs[#fs + 1] = tag .. ": nothing laid and no line says why" end
      end
    end
  end
  return pages, fs
end

-- The same seed gives the same page, every key on.
function M.seed(backdrop, only)
  local fs, pages = {}, 0
  local all = { glint = "on", herogilding = "on", deviant = "on", stray = "on" }
  for _, name in ipairs(only or M.PATTERNS) do
    for _, layout in ipairs(M.LAYOUT_ORDER) do
      local a = page(name, layout, backdrop, all):body()
      local b = page(name, layout, backdrop, all):body()
      pages = pages + 2
      if a ~= b then fs[#fs + 1] = string.format("%s %s %s: two pages of one seed differ", name, layout, backdrop) end
    end
  end
  return pages, fs
end

-- A string, or a list of them, as a list.
---@param v any
---@return string[]
local function as_list(v)
  if type(v) == "table" then return v end
  return { v }
end

-- Run the checks on `backdrop`; with `mutations`, prove each fails when its
-- invariant is broken.
function M.run(backdrop, mutations)
  local t0 = os.clock()
  local total = 0
  for _, check in ipairs({ "off", "gold", "deviant", "stray", "seed", "target", "ink", "finite" }) do
    local pages, fs = M[check](backdrop)
    total = total + pages
    H.check(pages > 0, check .. ": no pages")
    for _, f in ipairs(fs) do H.check(false, f) end
    if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("touches %s: %d pages, %d failures", check, pages, #fs)) end
  end
  if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("touches %s: %d pages, %.1f s", backdrop, total, os.clock() - t0)) end
  if not mutations then return end
  local f = assert(io.open("lua/flora/pattern_touches.lua"))
  local src = f:read("a")
  f:close()
  local real, real_pattern = package.loaded["flora.pattern_touches"], package.loaded["flora.pattern"]
  -- Each: the invariant, the source line, its replacement, the check and its picks.
  for _, m in ipairs({
    { "off", [[if g ~= nil and g ~= "off" then]], [[if g ~= nil then]], "off", { "truchet" } },
    { "gold at the places", [[pt:fill(disc(c.x, c.y, 0.16 * med), ink.gold, 1)]], [[pt:fill(disc(c.x + 4 * med, c.y, 0.16 * med), ink.gold, 1)]], "gold", { "kikko" } },
    { "an unsupported key", [[      if why then
        warn(]], [[      if false then
        warn(]], "gold", { "truchet" } },
    { "on is one", [[local n = dv == "on" and 1 or tonumber(dv)]], [[local n = dv == "on" and 2 or tonumber(dv)]], "deviant", { "stars_8_4" }, nil, { "on" } },
    { "different edges first", [[for _, s in ipairs(sides) do
          if #picked < N then]], [[for _, s in ipairs({ sides[1] }) do
          if #picked < N then]], "deviant", { "stars_8_4" }, nil, { "2" } },
    { "never close together", [[local function free(k)]], [[local function free(k)
        if true then return true end]], "deviant", { "stars_8_4", "kikko" }, { 1, 2, 3, 4, 5, 6, 7, 8 }, { "4" } },
    { "a plate clear of the cells", [[< M.MIN_CLEAR * 2 * reach then]], [[< -1 then]], "stray", { "kikko", "stars_8_4" }, { 7, 8, 9, 10, 11, 12 } },
    { "a plate a cell's width away", [[if f * med < M.MIN_MOVE * 2 * reach then goto too_near end]], [[f = 1.0]], "stray", { "stars_8_4" } },
    { "whole cells in the field", [[if deg[k] >= 0.6 * top and area(k.cell) >= big and not taken[k] and cell_clear(k.cell) then]], [[if not taken[k] then]], "deviant", { "stars_8_4" }, { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } },
    { "the plate's distance from the text", [[and text_dist(nx, ny) >= field
              and clear(nx, ny, reach, ctx.width / 2 + (c.pad or 0))
            if ok then
              ok = ctx.fits(]], [[
            if ok then
              ok = true or ctx.fits(]], "stray", { "stars_8_4", "kikko" }, { 1, 2, 3, 4, 5, 6, 7, 8 } },
    { "a glint keeps the field's distance", [[not plan.at[c.owner] and clear(c.x, c.y, 0.42 * med, 0.15) then]], [[not plan.at[c.owner] then]], "ink", { "stars_8_4", "kikko" }, { 7 }, { { "glint", "on" } } },
    { "the plate clear of text and reservations", [[
              and clear(nx, ny, reach, ctx.width / 2 + (c.pad or 0))]], "", "ink", { "overlapping_circles", "kikko" }, { 7, 8, 9 }, { { "stray", "on" } } },
    { "the frame keeps its colours", [[hero.band, hero.band0 = pal.gold, pal.gold]], [[hero.band, hero.band0, outer.band = pal.gold, pal.gold, pal.gold]], "target", { "stars_8_4" } },
    { "a spacing that is finite", { [[if best < math.huge then nn[#nn + 1] = best end]], [[if med <= 0 or med > 4 * ctx.size then med = ctx.size end]] }, { [[nn[#nn + 1] = best]], "" }, "finite", { { "stars_8_4", 8 }, { "kikko", 8 } } },
    { "the same seed", [[local rng = ctx.rng:fork("pattern touches")]], [[local rng = ctx.rng:fork("pattern touches" .. tostring({}))]], "seed", { "stars_8_4" } },
  }) do
    -- One replacement, or a list of them (a guard held twice is broken twice).
    local from, to = as_list(m[2]), as_list(m[3])
    local mutated, found = src, true
    for n, line in ipairs(from) do
      local i, j = mutated:find(line, 1, true)
      H.check(i ~= nil, "mutation: the line is gone from pattern_touches.lua: " .. line)
      if not i then found = false break end
      mutated = mutated:sub(1, i - 1) .. to[n] .. mutated:sub(j + 1)
    end
    if found then
      -- pattern.lua holds the module it loaded: load it again over the mutant.
      package.loaded["flora.pattern_touches"] = assert(load(mutated, "@pattern_touches.lua (mutated)"))()
      package.loaded["flora.pattern"] = nil
      local ok, a, fs = pcall(M[m[4]], backdrop, m[5], m[6], m[7])
      package.loaded["flora.pattern_touches"], package.loaded["flora.pattern"] = real, real_pattern
      if not ok then error(a, 0) end
      H.check(#fs > 0, "the " .. m[4] .. " check missed " .. m[1])
      if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation %s: %d failures", m[1], #fs)) end
    end
  end
end

-- Called with a backdrop, runs the checks; M holds them one by one.
return setmetatable({ M = M }, { __call = function(_, backdrop, mutations)
  M.run(backdrop, mutations)
  H.done("pattern touches " .. backdrop)
end })
