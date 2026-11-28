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

-- Run the checks on `backdrop`; with `mutations`, prove each fails when its
-- invariant is broken.
function M.run(backdrop, mutations)
  local t0 = os.clock()
  local total = 0
  for _, check in ipairs({ "off", "gold", "deviant", "stray", "seed" }) do
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
    { "whole cells in the field", [[if deg[k] >= 0.6 * top and area(k.cell) >= big and not taken[k] then]], [[if not taken[k] then]], "deviant", { "stars_8_4" }, { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } },
    { "the plate's distance from the text", [[and text_dist(nx, ny) >= field
            if ok then
              ok = ctx.fits(]], [[
            if ok then
              ok = true or ctx.fits(]], "stray", { "stars_8_4", "kikko" }, { 1, 2, 3, 4, 5, 6, 7, 8 } },
    { "the same seed", [[local rng = ctx.rng:fork("pattern touches")]], [[local rng = ctx.rng:fork("pattern touches" .. tostring({}))]], "seed", { "stars_8_4" } },
  }) do
    local i, j = src:find(m[2], 1, true)
    H.check(i ~= nil, "mutation: the line is gone from pattern_touches.lua: " .. m[2])
    if i then
      -- pattern.lua holds the module it loaded: load it again over the mutant.
      package.loaded["flora.pattern_touches"] = assert(load(src:sub(1, i - 1) .. m[3] .. src:sub(j + 1), "@pattern_touches.lua (mutated)"))()
      package.loaded["flora.pattern"] = nil
      local ok, a, fs = pcall(M[m[4]], backdrop, m[5], m[6], m[7])
      package.loaded["flora.pattern_touches"], package.loaded["flora.pattern"] = real, real_pattern
      if not ok then error(a, 0) end
      H.check(#fs > 0, "the " .. m[4] .. " check missed " .. m[1])
      if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation %s: %d failures", m[1], #fs)) end
    end
  end
end

return function(backdrop, mutations)
  M.run(backdrop, mutations)
  H.done("pattern touches " .. backdrop)
end
