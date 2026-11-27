-- The touches a pattern field may carry, each a setting that is off unless
-- set (settings.lua): where gold lies in the field, gold on the hero, a
-- deviant cell and a loose plate. A page without them is painted as it is
-- without this module.
--
--   glint      where gold lies in the field, in place of the pattern's own:
--                on     a few glints where bands cross, spread by seed
--                core   in the band's core (the accent and the core gold)
--                cells  a few whole cells gilded, chosen by seed
--                knobs  a gold knob at the middle of every cell
--   herogold   the hero's lines in gold; it combines with any glint
--   deviant    at most one whole cell on each side is turned and painted
--              in another colour, its place drawn by seed
--   loose      one cell has come loose from the field's edge and lies a
--              little way outside it, a dotted path leading back to the
--              gap it left
--
-- The places are drawn from the page's seed on a stream of their own
-- ("pattern touches"), so a page without the keys draws what it always
-- did. A pattern that cannot give a key what it needs says so in the page's
-- log and is painted as it is without that key. M.plan chooses the places
-- once the field is kept; M.painters paints a cell through its plan. The
-- page keeps one report of what was laid (pt.touches_report), summed over
-- the strips of a perimeter band.

local Paint = require("flora.paint")
local Color = require("flora.color")
local K = require("flora.pat_kit")
local sqrt, sin, cos, pi = math.sqrt, math.sin, math.cos, math.pi

local M = {}

-- The values of glint; "on" is the glints at crossings.
M.GLINT = { off = true, on = true, core = true, cells = true, knobs = true }
M.GLINT_ORDER = { "off", "on", "core", "cells", "knobs" }

-- Patterns whose cells are not tiles a key can gild, turn or move, and why.
M.NO_CELLS = {
  celtic_knot = "its strands run across the edges of its cells",
  sikku_kolam = "its dots and loops are not the cells of a tiling",
}

-- Patterns whose cells have no middle a knob could sit at, and why.
M.NO_CENTRES = {
  celtic_knot = "its cells are pieces of strand, not tiles with a middle",
  sikku_kolam = "its cells are dots and loops, not tiles with a middle",
}

-- Patterns whose bands do not cross at the corners of their cells or at
-- the meeting of their circles, and why.
M.NO_CROSSINGS = {
  celtic_knot = "its strands cross at the middle of its cells' edges, which the field does not know",
  sikku_kolam = "its loops are drawn through dots, not along cells",
  truchet = "its arcs meet at the middle of a tile's edges, never cross",
  rosette_lattice = "its straps cross inside the rosette, not at the cell's corners",
}

-- The share of the kept cells (or crossings) a few means, at least MIN of
-- them, and how far apart in cell sizes the places keep.
M.SHARE = { cells = 0.04, crossings = 0.08 }
M.MIN = { cells = 2, crossings = 5 }
M.APART = { cells = 3.2, crossings = 2.6 }

-- The state for a page, or nil when no key is set. `want` holds the keys'
-- values (glint, herogold, deviant, loose); `warn` takes a line for the
-- page's log. A value that is none of the key's is logged and the key left
-- off; so is a key the pattern cannot take.
function M.new(want, p, warn, pt)
  local S = { pattern = p }
  local function no(k, v, list)
    warn(string.format("%s=%s is not one of %s; it is left off", k, tostring(v), list))
  end
  local g = want.glint
  if g ~= nil and g ~= "off" then
    if not M.GLINT[g] then
      no("glint", g, table.concat(M.GLINT_ORDER, ", "))
    else
      local mode = g == "on" and "crossings" or g
      local why
      if mode == "cells" then why = M.NO_CELLS[p.name] and ("no cells to gild (" .. M.NO_CELLS[p.name] .. ")")
      elseif mode == "knobs" then why = M.NO_CENTRES[p.name] and ("no cell middles the field knows (" .. M.NO_CENTRES[p.name] .. ")")
      elseif mode == "crossings" then why = M.NO_CROSSINGS[p.name] and ("no crossings the field knows (" .. M.NO_CROSSINGS[p.name] .. ")") end
      if why then
        warn(string.format("glint=%s: %s has %s; it is painted as it is", g, p.name, why))
      else
        S.gold = mode
      end
    end
  end
  for _, k in ipairs({ "herogold", "deviant", "loose" }) do
    local v = want[k]
    if v ~= nil and v ~= "off" then
      if v ~= "on" then
        no(k, v, "on, off")
      elseif k ~= "herogold" and M.NO_CELLS[p.name] then
        warn(string.format("%s=on: %s has no cells to %s (%s); it is painted as it is", k, p.name, k == "deviant" and "turn" or "move", M.NO_CELLS[p.name]))
      else
        S[k] = true
      end
    end
  end
  if not (S.gold or S.herogold or S.deviant or S.loose) then return nil end
  pt.touches_report = pt.touches_report or { places = 0, deviants = {} }
  S.report = pt.touches_report
  return S
end

-- The role colours the keys set on `base` (pattern.lua's role_inks). Keeps
-- a copy for what lies outside the field (the hero, the border's rule and
-- frame): S.outer, the colours as they were, the hero's lines gold for
-- herogold.
function M.colours(S, base)
  local pal = Paint.palette
  local outer = {}
  for k, v in pairs(base) do outer[k] = v end
  S.outer = outer
  if S.herogold then
    outer.band, outer.band0 = pal.gold, pal.gold
    outer.line0 = Paint.mix(pal.gold, pal.paper, 0.45)
  end
  local g = S.gold
  if not g then return end
  base.gold = pal.gold
  if g == "core" then
    base.core, base.accent = pal.gold, pal.gold
    return
  end
  -- No gold of the pattern's own in the field.
  base.accent = base.core
end

-- A colour with its hue turned a third of the way round the wheel.
local function foil(c)
  if not c then return nil end
  local L, Ch, h = Color.lch(c)
  return Color.oklch(L, Ch, h + 150)
end

local function copy(t)
  local o = {}
  for k, v in pairs(t) do o[k] = v end
  return o
end

local function dist(ax, ay, bx, by) return sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-- The cell's outline as path commands, or nil.
local function region(c)
  if c.circle then return { { "o", c.circle[1], c.circle[2], c.circle[3] } } end
  local P = c.tile or c.verts
  if P and #P >= 3 then return K.path(P) end
end

-- The area of a cell's outline.
local function area(c)
  if c.circle then return pi * c.circle[3] ^ 2 end
  local P, a = c.tile or c.verts, 0
  for i = 1, #P do
    local u, v = P[i], P[i % #P + 1]
    a = a + u[1] * v[2] - v[1] * u[2]
  end
  return math.abs(a) / 2
end

-- n of items spread by seed: the first drawn that keep `apart` from those
-- drawn already, as many as there are room for.
local function spread(rng, items, n, apart)
  local order = {}
  for i = 1, #items do order[i] = i end
  for i = #order, 2, -1 do
    local j = rng:int(1, i)
    order[i], order[j] = order[j], order[i]
  end
  local out = {}
  for _, i in ipairs(order) do
    local it = items[i]
    local ok = true
    for _, o in ipairs(out) do
      if dist(it.x, it.y, o.x, o.y) < apart then ok = false break end
    end
    if ok then
      out[#out + 1] = it
      if #out >= n then break end
    end
  end
  return out
end

local function key2(x, y) return string.format("%d,%d", math.floor(x * 10 + .5), math.floor(y * 10 + .5)) end

-- The points where bands cross, from the kept cells: the corners of
-- polygons that two cells share, and where two circles meet. Each is
-- owned by the first cell that has it: { x, y, owner }.
local function crossings(kept)
  local seen, out = {}, {}
  local function add(x, y, k)
    local key = key2(x, y)
    if seen[key] then
      if not seen[key].shared then seen[key].shared = true; out[#out + 1] = seen[key] end
    else
      seen[key] = { x = x, y = y, owner = k }
    end
  end
  local circles = {}
  for _, k in ipairs(kept) do
    local c = k.cell
    if c.circle then circles[#circles + 1] = k
    else
      for _, v in ipairs(c.tile or c.verts or {}) do add(v[1], v[2], k) end
    end
  end
  -- Circles about centres within two radii meet at two points; the lattice
  -- points, where every circle passes through its neighbours' centres, are
  -- found as the meeting of the pairs.
  for i = 1, #circles do
    local a = circles[i].cell.circle
    for j = i + 1, #circles do
      local b = circles[j].cell.circle
      local d = dist(a[1], a[2], b[1], b[2])
      if d > 1e-6 and d < a[3] + b[3] - 1e-6 and d > math.abs(a[3] - b[3]) + 1e-6 then
        local l = (a[3] ^ 2 - b[3] ^ 2 + d * d) / (2 * d)
        local h2 = a[3] ^ 2 - l * l
        if h2 > 0 then
          local h = sqrt(h2)
          local mx, my = a[1] + l * (b[1] - a[1]) / d, a[2] + l * (b[2] - a[2]) / d
          local ox, oy = -(b[2] - a[2]) / d * h, (b[1] - a[1]) / d * h
          for _, s in ipairs({ 1, -1 }) do
            local x, y = mx + s * ox, my + s * oy
            local key = key2(x, y)
            if seen[key] then
              if not seen[key].shared then seen[key].shared = true; out[#out + 1] = seen[key] end
            else
              seen[key] = { x = x, y = y, owner = circles[i], shared = true }
              out[#out + 1] = seen[key]
            end
          end
        end
      end
    end
  end
  -- Circle meetings are found for pairs only once.
  local uniq, list = {}, {}
  for _, c in ipairs(out) do
    local key = key2(c.x, c.y)
    if not uniq[key] then uniq[key] = true; list[#list + 1] = c end
  end
  return list
end

-- The typical distance between the centres of neighbouring cells, taken
-- over a sample of at most 300 of them.
local function spacing(list)
  local step = math.max(1, math.floor(#list / 300))
  local nn = {}
  for i = 1, #list, step do
    local c, best = list[i].cell, math.huge
    for j, o in ipairs(list) do
      if i ~= j then
        local d = dist(c.x, c.y, o.cell.x, o.cell.y)
        if d < best then best = d end
      end
    end
    nn[#nn + 1] = best
  end
  table.sort(nn)
  return nn[math.ceil(#nn / 2)] or 0
end

-- The cells of `list` within 1.5 spacings of cell k's centre.
local function near(list, k, med)
  local out = {}
  for _, o in ipairs(list) do
    if o ~= k and dist(k.cell.x, k.cell.y, o.cell.x, o.cell.y) < 1.5 * med then out[#out + 1] = o end
  end
  return out
end

local function shape_at(c, dx, dy, pad)
  if c.circle then return { circle = { c.circle[1] + dx, c.circle[2] + dy, c.circle[3] + pad } } end
  local P = {}
  for i, v in ipairs(c.verts) do P[i] = { v[1] + dx, v[2] + dy } end
  return { verts = P }
end

local function rect_dist(x, y, r)
  local dx, dy = math.max(r[1] - x, 0, x - r[3]), math.max(r[2] - y, 0, y - r[4])
  return sqrt(dx * dx + dy * dy)
end

-- The most neighbours (cells within 1.5 spacings) a cell of `list` has,
-- and each cell's count.
local function degrees(list, med)
  local out, top = {}, 0
  for _, k in ipairs(list) do
    local n = #near(list, k, med)
    out[k] = n
    if n > top then top = n end
  end
  return out, top
end

-- Choose the places, once the field is kept. `ctx`: kept, size, width,
-- text, W, top, hero, fits (pattern.lua's precondition), keep (the
-- rectangles the field keeps clear of), band (a perimeter band's, with its
-- strip for whole rows), core (whether a band's core is drawn), pt, rng,
-- warn. Returns the plan: at[k] for each kept cell with something of its
-- own, and `med`, the spacing of the cells. What is laid goes to the
-- page's report (S.report), in page coordinates.
function M.plan(S, ctx)
  local kept, p = ctx.kept, S.pattern
  local rng = ctx.rng:fork("pattern touches")
  local plan = { at = {}, S = S, size = ctx.size }
  local rep = S.report
  local keep = ctx.keep or {}
  local pt = ctx.pt
  local strip = ctx.band and ctx.band.strip
  local function page_xy(x, y)
    if pt.frame_fn then return pt.frame_fn(x, y) end
    return x, y
  end
  local function text_dist(x, y)
    local d = math.huge
    for _, r in ipairs(keep) do d = math.min(d, rect_dist(x, y, r)) end
    return d
  end
  local function at(k)
    plan.at[k] = plan.at[k] or {}
    return plan.at[k]
  end
  local whole = {}
  for _, k in ipairs(kept) do
    if k.a >= 1 and not k.turn and region(k.cell) then whole[#whole + 1] = k end
  end
  local med = spacing(kept)
  plan.med = med
  rep.spacing = med
  rep.deviants = rep.deviants or {}
  rep.at = rep.at or {}
  -- The loose plate first, so that a deviant is not the cell that leaves.
  -- Of the four strips of a band of whole rows one carries it, drawn by
  -- seed: one cell on the page.
  local taken = {}
  if S.loose and strip and strip.side ~= ctx.rng:fork("loose strip"):int(1, 4) then
    S.loose = false
  end
  if S.loose then
    -- A cell at the field's edge (few neighbours) that is no smaller than
    -- most: the small square star of stars_8_4 is not the plate to show.
    local areas = {}
    for _, k in ipairs(whole) do areas[#areas + 1] = area(k.cell) end
    table.sort(areas)
    local big = 0.8 * (areas[math.ceil(#areas / 2)] or 0)
    local edge, around = {}, {}
    for _, k in ipairs(whole) do
      if area(k.cell) >= big then
        local list = near(kept, k, med)
        if #list > 0 and #list <= 4 then edge[#edge + 1] = k; around[k] = list end
      end
    end
    for i = #edge, 2, -1 do
      local j = rng:int(1, i)
      edge[i], edge[j] = edge[j], edge[i]
    end
    -- The plate lies no nearer what the field keeps clear of than the
    -- field's own nearest cell does.
    local field = math.huge
    for _, k in ipairs(kept) do field = math.min(field, text_dist(k.cell.x, k.cell.y)) end
    local done
    for _, k in ipairs(edge) do
      local c = k.cell
      local mx, my = 0, 0
      for _, o in ipairs(around[k]) do mx, my = mx + o.cell.x, my + o.cell.y end
      local ux, uy = c.x - mx / #around[k], c.y - my / #around[k]
      local l = sqrt(ux * ux + uy * uy)
      if l > 1e-6 then
        ux, uy = ux / l, uy / l
        for _, f in ipairs({ 2.8, 2.3, 1.8, 1.4 }) do
          local dx, dy = ux * f * med, uy * f * med
          local nx, ny = c.x + dx, c.y + dy
          local ok = nx > med and nx < ctx.W - med and ny > med and ny < ctx.top - med and text_dist(nx, ny) >= field
          if ok then
            ok = ctx.fits("cell", { shape_at(c, dx, dy, 0) }, ctx.width / 2 + (c.pad or 0) + 0.2 * med)
          end
          if ok then
            for _, o in ipairs(kept) do
              if o ~= k and dist(nx, ny, o.cell.x, o.cell.y) < 0.85 * med then ok = false break end
            end
          end
          if ok then
            done = { k = k, dx = dx, dy = dy, turn = (rng:next() < 0.5 and -1 or 1) * 12 * pi / 180 }
            break
          end
        end
      end
      if done then break end
    end
    if done then
      taken[done.k] = true
      local c = done.k.cell
      local ax, ay, bx, by = c.x, c.y, c.x + done.dx, c.y + done.dy
      local len = dist(ax, ay, bx, by)
      -- The dotted path from the gap to the plate, along a shallow curve.
      local bend = (rng:next() < 0.5 and -1 or 1) * 0.22 * len
      local cx, cy = (ax + bx) / 2 - (by - ay) / len * bend, (ay + by) / 2 + (bx - ax) / len * bend
      local dots = {}
      local px, py, run, next_at = ax, ay, 0, 0.55 * med
      for i = 1, 240 do
        local t = i / 240
        local x = (1 - t) ^ 2 * ax + 2 * (1 - t) * t * cx + t * t * bx
        local y = (1 - t) ^ 2 * ay + 2 * (1 - t) * t * cy + t * t * by
        run = run + dist(px, py, x, y)
        px, py = x, y
        if run >= next_at and dist(x, y, bx, by) > 0.55 * med then
          if ctx.fits("cell", { { circle = { x, y, 0.3 } } }, 0) and text_dist(x, y) >= field - 0.3 * med then dots[#dots + 1] = { x, y } end
          next_at = next_at + 0.26 * med
        end
      end
      done.dots = dots
      at(done.k).loose = done
      local points = {}
      local x1, y1 = page_xy(bx, by)
      points[1] = { x1, y1 }
      for _, d in ipairs(dots) do
        local x, y = page_xy(d[1], d[2])
        points[#points + 1] = { x, y }
      end
      local gx, gy = page_xy(ax, ay)
      rep.loose = { x = gx, y = gy, to_x = x1, to_y = y1, dots = #dots, points = points }
    else
      ctx.warn(string.format("loose=on: no cell of %s at the field's edge has room outside it, clear of the text as the field is; none is loosened", p.name))
    end
  end
  -- Deviants: at most one on each side, a whole cell inside the field (not
  -- a loose cell at its edge: it has most of the neighbours a cell of the
  -- field has) and clear of the paper's edge. A side is a side of the
  -- text, of a perimeter band's inner rectangle, or the strip of a band of
  -- whole rows.
  if S.deviant then
    local deg, top = degrees(whole, med)
    -- No smaller than most: the small square star of stars_8_4 is no cell
    -- to turn.
    local areas = {}
    for _, k in ipairs(whole) do areas[#areas + 1] = area(k.cell) end
    table.sort(areas)
    local big = 0.8 * (areas[math.ceil(#areas / 2)] or 0)
    local by_side = {}
    local function side_of(c)
      if strip then
        if c.x > 2.5 * strip.w and c.x < ctx.W - 2.5 * strip.w and c.y > 0 and c.y < strip.w then return "strip" end
        return nil
      end
      local m = med
      if not (c.x > m and c.x < ctx.W - m and c.y > m and c.y < ctx.top - m) then return nil end
      local I = ctx.band and ctx.band.I
      if I then
        local out = { l = I[1] - c.x, r = c.x - I[3], b = I[2] - c.y, t = c.y - I[4] }
        local best, v = nil, 0
        for k, d in pairs(out) do if d > v then best, v = k, d end end
        return best
      end
      local t = ctx.text
      if c.x < t.x0 then return "l" elseif c.x > t.x1 then return "r"
      elseif c.y > t.y1 then return "t" elseif c.y < t.y0 then return "b" end
    end
    for _, k in ipairs(whole) do
      if deg[k] >= 0.6 * top and area(k.cell) >= big and not taken[k] then
        local s = side_of(k.cell)
        if s then
          by_side[s] = by_side[s] or {}
          table.insert(by_side[s], k)
        end
      end
    end
    local laid = 0
    for _, s in ipairs({ "l", "r", "t", "b", "strip" }) do
      local list = by_side[s]
      if list and #list > 0 then
        local k = list[rng:int(1, #list)]
        local c = k.cell
        local n = c.circle and 0 or #(c.tile or c.verts)
        at(k).deviant = { theta = n > 0 and pi / n or 0 }
        local x, y = page_xy(c.x, c.y)
        rep.deviants[#rep.deviants + 1] = { x = x, y = y, side = s }
        laid = laid + 1
      end
    end
    if laid == 0 then ctx.warn("deviant=on: no whole cell inside the field lies beside the text; none is turned") end
  end
  if S.herogold and not ctx.hero then ctx.warn("herogold=on: the page has no hero to paint in gold") end
  -- Gold.
  local g = S.gold
  local laid = 0
  if g == "cells" then
    local items = {}
    for _, k in ipairs(whole) do
      if not plan.at[k] then items[#items + 1] = { x = k.cell.x, y = k.cell.y, k = k } end
    end
    local n = math.max(M.MIN.cells, math.floor(M.SHARE.cells * #whole + .5))
    for _, it in ipairs(spread(rng:fork("cells"), items, n, M.APART.cells * med)) do
      at(it.k).gilt = true
      laid = laid + 1
      rep.at[#rep.at + 1] = { page_xy(it.x, it.y) }
    end
  elseif g == "knobs" then
    for _, k in ipairs(kept) do
      at(k).knob = true
      laid = laid + 1
      rep.at[#rep.at + 1] = { page_xy(k.cell.x, k.cell.y) }
    end
  elseif g == "crossings" then
    local all = {}
    for _, c in ipairs(crossings(whole)) do
      if not plan.at[c.owner] then all[#all + 1] = c end
    end
    local n = math.max(M.MIN.crossings, math.floor(M.SHARE.crossings * #all + .5))
    for _, c in ipairs(spread(rng:fork("crossings"), all, n, M.APART.crossings * med)) do
      local pl = at(c.owner)
      pl.glints = pl.glints or {}
      pl.glints[#pl.glints + 1] = { c.x, c.y }
      laid = laid + 1
      rep.at[#rep.at + 1] = { page_xy(c.x, c.y) }
    end
  elseif g == "core" then
    local roles = {}
    for _, r in ipairs(p.roles or {}) do roles[r] = true end
    local core = ctx.core or {}
    if not (roles.core or roles.accent) then
      ctx.warn(string.format("glint=core: %s paints no core down its bands, so the gold shows nowhere", p.name))
    elseif core.line then
      ctx.warn(string.format("glint=core: %s's bands are drawn as lines here, with no core, so the gold shows nowhere", p.name))
    elseif core.drawn == false then
      ctx.warn(string.format("glint=core: %s's band core is %.2f pt wide, under the %.1f pt it takes to be drawn, so the gold shows nowhere; a larger scale or bandwidth widens it",
        p.name, core.width or 0, K.CORE_MIN))
    else
      laid = #kept
    end
  end
  rep.places = (rep.places or 0) + laid
  rep.gold = g
  return plan
end

local function disc(x, y, r) return { { "o", x, y, r } } end

-- A four-pointed glint r long about (x, y).
local function glint(x, y, r)
  local w = 0.3 * r
  return K.path({ { x + r, y }, { x + w, y + w }, { x, y + r }, { x - w, y + w }, { x - r, y }, { x - w, y - w }, { x, y - r }, { x + w, y - w } })
end

-- A turn by theta about (ox, oy), then a move by (dx, dy).
local function turn(theta, ox, oy, dx, dy)
  local s, co = sin(theta), cos(theta)
  return function(x, y)
    local u, v = x - ox, y - oy
    return ox + dx + u * co - v * s, oy + dy + u * s + v * co
  end
end

-- How cell `c` is painted through its plan `pl`, for `ink`: { construct,
-- paint, enter, leave }. enter and leave set and clear the projection that
-- turns or moves the cell, round everything painted for it (its growth
-- included); the dotted path is painted without it.
function M.painters(plan, pl, c, ink, pt)
  local ink2 = ink
  if pl.deviant then
    ink2 = copy(ink)
    ink2.fill = { foil(ink.fill[1]) or ink.fill[1], foil(ink.fill[2]) or ink.fill[2] }
    ink2.band = foil(ink.band) or ink.band
  elseif pl.gilt then
    ink2 = copy(ink)
    ink2.fill = { ink.gold, ink.gold }
  end
  local project
  if pl.deviant then project = turn(pl.deviant.theta, c.x, c.y, 0, 0) end
  if pl.loose then project = turn(pl.loose.turn, c.x, c.y, pl.loose.dx, pl.loose.dy) end
  local prev
  local h = {}
  function h.enter()
    if not project then return end
    prev = pt.projection
    pt:project(function(x, y)
      x, y = project(x, y)
      if prev then return prev(x, y) end
      return x, y
    end)
  end
  function h.leave()
    if project then pt:project(prev) end
  end
  local med = plan.med
  function h.construct() c.construct(pt, c, ink2) end
  function h.paint()
    if pl.gilt then
      local path = region(c)
      if path then pt:fill(path, ink.gold, 1) end
    end
    c.paint(pt, c, ink2)
    if pl.loose then
      local r, circles = math.max(0.6, 0.055 * med), {}
      for _, d in ipairs(pl.loose.dots) do circles[#circles + 1] = disc(d[1], d[2], r) end
      if #circles > 0 then
        pt:project(prev)
        pt:fill(circles, ink.band, 1, { many = true })
        h.enter()
      end
    end
  end
  -- The knob and the glints lie over every cell, painted after them all.
  if pl.knob or pl.glints then
    function h.late()
      if pl.knob then
        pt:fill(disc(c.x, c.y, 0.16 * med), ink.gold, 1)
        pt:stroke(disc(c.x, c.y, 0.16 * med), ink.band, 0.3, 1)
      end
      for _, q in ipairs(pl.glints or {}) do
        pt:fill(glint(q[1], q[2], 0.42 * med), ink.gold, 1)
        pt:stroke(glint(q[1], q[2], 0.42 * med), ink.band, 0.3, 1)
      end
    end
  end
  return h
end

return M
