-- The pattern colour invariants, cell by cell over pattern x colourway x
-- ground (off, on) x backdrop x finish (tests/test_pattern_matrix.lua runs it; the floors are
-- set there). Each cell paints a small page and records every fill and
-- stroke inside the pattern's group, with the colour a module asked for
-- (before a dark backdrop repaints it).
--
--   M.run(floors, filter) -> cells, failures
--
-- A cell is { pattern, colourway, backdrop, finish, band_surface = OKLab
-- lightness difference of the band and what it lies on, ab = OKLab
-- distance of the two fields (or nil), ... }; a failure is a string naming
-- the cell and the invariant it breaks:
--
--   order     the bands keep their lightness order to a dark ground on
--             both backdrops, and without one the pattern's paper follows
--             the page on the dark backdrop
--   contrast  the band stands off the surface it lies most on (a filled
--             surface's field A, else the ground, else the page) by
--             floors.band (OKLab L); a band's lightness is set against it
--   vanish    the band stands off every surface it lies on (a surface's
--             fields and ground too) by floors.band_any, so it never
--             disappears into one
--   roles     every colour painted is one of the page's role colours (or
--             a mix of two), and the pattern lists every role it paints
--   fields    the two fields differ by floors.fields (OKLab distance)
--   legacy    the role defaults with full chroma and the old lightnesses
--             give the colours patterns had before roles
--   ground    every cell that lays the ground has its piece of it
--   nofill    the lines finish fills nothing
--   saturation  saturation 0 greys the fields and the ground in every
--             colourway, and more saturation never takes chroma away
--   tiling    khatam's stars meet tip to tip and the crosses fill the rest
--             of the plane, measured on the cells' own outlines
--   onecolour no hexagram star is painted in two colours: every fill that
--             lies inside a star has that star's one colour
--   onpanel   when the ground is one panel, everything the cells paint on
--             the paper lies on it
--   holes     no cell the field leaves out has every neighbour kept (the
--             page's edge is hard, edge=cell)
--   between   a plate that lies between cells runs along their outlines
--
-- M.knot(filter) runs the knot field (pat_celtic.lua's bleed and inset)
-- over both knot patterns x layout x mode x backdrop, holding it to
--   units     no strand ending loose inside the page

local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Settings = require("flora.settings")
local Patterns = require("flora.patterns")
local Pattern = require("flora.pattern")
local Color = require("flora.color")
local Inks = require("flora.inks")
local Rng = require("flora.rng")

local M = {}
local Units = dofile("tests/pattern_units.lua")
local Panel = dofile("tests/pattern_panel.lua")

-- How many of the kept cells have no kept cell near them: nearer than
-- 1.6 times the usual distance to a cell's nearest kept neighbour.
function M.isolated(kept)
  local cells = {}
  for _, k in ipairs(kept) do cells[#cells + 1] = k.cell end
  if #cells < 2 then return 0 end
  local info = Pattern.field_edges(cells, kept, {})
  return info.isolated
end

local function key(c) return string.format("%.4f,%.4f,%.4f", c[1], c[2], c[3]) end

local function lab(c)
  local L, Ch, h = Color.lch(c)
  local r = math.rad(h or 0)
  return L, Ch * math.cos(r), Ch * math.sin(r)
end
local function de(p, q)
  local a1, b1, c1 = lab(p)
  local a2, b2, c2 = lab(q)
  return math.sqrt((a1 - a2) ^ 2 + (b1 - b2) ^ 2 + (c1 - c2) ^ 2)
end

-- `c` is `p` mixed toward `q` (to within rounding).
local function between(c, p, q)
  local t, n = 0, 0
  for i = 1, 3 do
    local d = q[i] - p[i]
    if math.abs(d) > 1e-4 then t = t + (c[i] - p[i]) / d; n = n + 1 end
  end
  if n == 0 then return math.abs(c[1] - p[1]) < 1e-3 end
  t = t / n
  if t < -1e-3 or t > 1 + 1e-3 then return false end
  for i = 1, 3 do
    if math.abs(p[i] + (q[i] - p[i]) * t - c[i]) > 2e-3 then return false end
  end
  return true
end

-- Paint one page, recording the pattern group's paint calls.
local function paint(spec)
  local rec = { fills = {}, strokes = {}, fillpaths = {} }
  local fill, stroke = Paint.fill, Paint.stroke
  Paint.fill = function(self, cmds, rgb, ...)
    if self.group and self.group.tag == "pattern" then
      rec.fills[#rec.fills + 1] = rgb
      rec.fillpaths[#rec.fillpaths + 1] = { cmds = cmds, rgb = rgb }
    end
    return fill(self, cmds, rgb, ...)
  end
  Paint.stroke = function(self, cmds, rgb, ...)
    if self.group and self.group.tag == "pattern" then rec.strokes[#rec.strokes + 1] = rgb end
    return stroke(self, cmds, rgb, ...)
  end
  Paint.reset_resources()
  local ok, pt = pcall(Compose.page, spec)
  Paint.fill, Paint.stroke = fill, stroke
  if not ok then error(pt, 0) end
  rec.pt = pt
  return rec
end

local function page(name, setup, layout)
  local spec = { width = 300, height = 240, text = { x0 = 130, y0 = 30, x1 = 280, y1 = 210 }, seed = 7,
    layout = layout or "left", pattern = { [name] = 1 }, pattern_edge = "cell" }
  Settings.to_spec(Settings.merge(Settings.from_spec(spec), Settings.parse(setup)), spec)
  return spec
end

-- The role colours of a page, by role, as role_inks gives them.
local function role_colours(base)
  return { band = base.band, core = base.core, a = base.fill1, b = base.fill2, accent = base.accent,
    ground = base.ground, line = base.line, dark = base.dark, paper = Paint.palette.paper,
    band0 = base.band0, line0 = base.line0 }
end

local ROLE_OF = { band = "band", band0 = "band", line = "band", line0 = "band", core = "core", a = "a", b = "b",
  accent = "accent", ground = "ground", dark = "ground", paper = "paper", page = "paper" }

-- The points of a path of moves and lines (K.path's).
local function points(cmds)
  local P = {}
  for _, c in ipairs(cmds) do
    if c[1] == "m" or c[1] == "l" then P[#P + 1] = { c[2], c[3] } end
  end
  return P
end
local function area(P)
  local s = 0
  for i = 1, #P do
    local p, q = P[i], P[i % #P + 1]
    s = s + p[1] * q[2] - q[1] * p[2]
  end
  return math.abs(s) / 2
end
local function inside(P, x, y)
  local hit = false
  for i = 1, #P do
    local p, q = P[i], P[i % #P + 1]
    if (p[2] > y) ~= (q[2] > y) and x < p[1] + (y - p[2]) / (q[2] - p[2]) * (q[1] - p[1]) then hit = not hit end
  end
  return hit
end

-- khatam's tiling, on its own cells: four stars about a cross, and the
-- cross between them. The stars and the cross fill the period's square
-- exactly (their areas sum to a squared, as they cannot overlap where
-- every cross corner is a star's corner), and each star's tip is its
-- neighbour's.
function M.tiling(p, a)
  a = a or 28
  local cells = p.cells({ x0 = 0, y0 = 0, x1 = 3 * a, y1 = 3 * a, size = a, style = {} })
  local at = {}
  for _, c in ipairs(cells) do at[string.format("%.3f,%.3f", c.x, c.y)] = c end
  local function cell(x, y) return at[string.format("%.3f,%.3f", x, y)] end
  local c00, c10, c01, c11 = cell(a, a), cell(2 * a, a), cell(a, 2 * a), cell(2 * a, 2 * a)
  if not (c00 and c10 and c01 and c11) then return "the cells do not stand on the lattice" end
  local cross
  for _, pl in ipairs(c00.plates or {}) do if pl.between then cross = points(pl[1]) end end
  if not cross then return "no cross between the stars" end
  local star = points(c00.star)
  local sum = area(star) + area(cross)
  if math.abs(sum - a * a) > 1e-6 * a * a then
    return string.format("a star and a cross cover %.4f of the period's square", sum / (a * a))
  end
  local corners = {}
  for _, c in ipairs({ c00, c10, c01, c11 }) do for _, q in ipairs(points(c.star)) do corners[#corners + 1] = q end end
  for _, q in ipairs(cross) do
    local near = math.huge
    for _, r in ipairs(corners) do near = math.min(near, math.sqrt((q[1] - r[1]) ^ 2 + (q[2] - r[2]) ^ 2)) end
    if near > 1e-6 * a then return string.format("a corner of the cross lies %.3f pt from every star", near) end
  end
  local tip = { a + a / 2, a }
  local function has(c) for _, q in ipairs(points(c.star)) do if math.abs(q[1] - tip[1]) + math.abs(q[2] - tip[2]) < 1e-6 * a then return true end end end
  if not (has(c00) and has(c10)) then return "two neighbouring stars do not meet tip to tip" end
  return nil
end

-- The cells of the drawing the field left out though every neighbour of
-- theirs is kept, on the page. Neighbours are as M.isolated's.
function M.holes(info)
  local all, keptat = info.all or {}, {}
  for _, k in ipairs(info.kept) do keptat[k.cell] = true end
  if #all < 2 then return 0 end
  local nd = Pattern.field_edges(all, {}, {}).nd
  local n = 0
  for _, c in ipairs(all) do
    if not keptat[c] and info.onpage and info.onpage[c] then
      local nb, kept = 0, 0
      for _, o in ipairs(all) do
        if o ~= c and (o.x - c.x) ^ 2 + (o.y - c.y) ^ 2 <= nd * nd then
          nb = nb + 1
          if keptat[o] then kept = kept + 1 end
        end
      end
      if nb >= 3 and kept == nb then n = n + 1 end
    end
  end
  return n
end

-- The plates laid between cells whose edges do not each lie on an edge of
-- one of the cells they lie between.
local function on_segment(q, a, b, eps)
  local dx, dy = b[1] - a[1], b[2] - a[2]
  local L2 = dx * dx + dy * dy
  local t = L2 > 0 and ((q[1] - a[1]) * dx + (q[2] - a[2]) * dy) / L2 or 0
  if t < -eps or t > 1 + eps then return false end
  local px, py = a[1] + t * dx, a[2] + t * dy
  return (q[1] - px) ^ 2 + (q[2] - py) ^ 2 <= eps * eps
end
function M.between(info)
  local at = {}
  for _, k in ipairs(info.kept) do at[Pattern.cell_key(k.cell)] = k.cell end
  local bad = 0
  for _, k in ipairs(info.kept) do
    for _, pl in ipairs(k.cell.plates or {}) do
      local cells = {}
      for _, q in ipairs(pl.between or {}) do cells[#cells + 1] = at[Pattern.cell_key({ x = q[1], y = q[2] })] end
      -- Only the plates the field lays: every cell they lie between kept.
      if pl.between and #cells == #pl.between then
        local P = points(pl[1])
        local ok = true
        for i = 1, #P do
          local p1, p2 = P[i], P[i % #P + 1]
          local found = false
          for _, c in ipairs(cells) do
            local V = c.verts
            for j = 1, #V do
              local a, b = V[j], V[j % #V + 1]
              if on_segment(p1, a, b, 1e-6) and on_segment(p2, a, b, 1e-6) then found = true end
            end
          end
          if not found then ok = false end
        end
        if not ok then bad = bad + 1 end
      end
    end
  end
  return bad
end

-- Fills inside each kept star of more than one colour (hexagram).
local function colours_per_star(kept, fillpaths)
  local bad = 0
  for _, k in ipairs(kept) do
    local P = k.cell.verts
    local seen, n = {}, 0
    for _, f in ipairs(fillpaths) do
      local Q = points(f.cmds)
      if #Q > 0 then
        local cx, cy = 0, 0
        for _, q in ipairs(Q) do cx, cy = cx + q[1], cy + q[2] end
        cx, cy = cx / #Q, cy / #Q
        if inside(P, cx, cy) then
          local kk = key(f.rgb)
          if not seen[kk] then seen[kk] = true; n = n + 1 end
        end
      end
    end
    if n > 1 then bad = bad + 1 end
  end
  return bad
end

function M.run(floors, filter)
  local cells, failures = {}, {}
  local function fail(c, what, msg)
    failures[#failures + 1] = string.format("%s %s ground=%s %s %s: %s: %s", c.pattern, c.colourway, c.ground, c.backdrop, c.finish, what, msg)
  end
  for _, p in ipairs(Patterns.list) do
    for _, cw in ipairs(Inks.colourway_order) do
      for _, ground in ipairs({ "auto", "panel", "cells" }) do
      for _, finish in ipairs({ "filled", "lines" }) do
        if not filter or filter(p.name, cw, finish) then
          local seen = {}
          for _, bd in ipairs({ "light", "dark" }) do
            local spec = page(p.name, "colourway=" .. cw .. ", finish=" .. finish .. ", ground=" .. ground .. ", backdrop=" .. bd)
            local rec = paint(spec)
            local base = rec.pt.pattern.inks
            local c = { pattern = p.name, colourway = cw, backdrop = bd, finish = finish, ground = ground }
            c.kept = #rec.pt.pattern.kept
            cells[#cells + 1] = c
            local roles = role_colours(base)
            -- The page's own colour, for a halo that parts two strands.
            roles.page = Color.backdrop(spec.backdrop)
            local declared = { paper = true }
            for _, r in ipairs(p.roles) do declared[r] = true end
            -- roles
            local all = {}
            for _, x in ipairs(rec.fills) do all[#all + 1] = x end
            for _, x in ipairs(rec.strokes) do all[#all + 1] = x end
            local bad, undeclared = 0, {}
            for _, x in ipairs(all) do
              local hit = false
              for name, rc in pairs(roles) do
                if rc and key(rc) == key(x) then
                  hit = true
                  if not declared[ROLE_OF[name]] and not (name == "paper" or name == "line" or name == "line0") then
                    undeclared[ROLE_OF[name]] = true
                  end
                end
              end
              if not hit then
                for _, p1 in pairs(roles) do
                  for _, p2 in pairs(roles) do
                    if not hit and p1 and p2 and between(x, p1, p2) then hit = true end
                  end
                end
              end
              if not hit then bad = bad + 1 end
            end
            if bad > 0 then fail(c, "roles", bad .. " colours that are no role's") end
            for r in pairs(undeclared) do
              -- The same colour may stand for two roles (core and paper);
              -- only a role no declared role shares its colour with counts.
              local shared = false
              for name, rc in pairs(roles) do
                if rc and declared[ROLE_OF[name]] and roles[r] and key(rc) == key(roles[r]) then shared = true end
              end
              if not shared then fail(c, "roles", "paints with the undeclared role " .. r) end
            end
            -- nofill
            if finish == "lines" and #rec.fills > 0 then fail(c, "nofill", #rec.fills .. " fills under the lines finish") end
            -- tiling
            if p.name == "khatam" then
              local why = M.tiling(p)
              if why then fail(c, "tiling", why) end
            end
            -- onecolour
            if p.name == "hexagram_lattice" and finish == "filled" then
              local bad = colours_per_star(rec.pt.pattern.kept, rec.fillpaths)
              if bad > 0 then fail(c, "onecolour", bad .. " stars painted in more than one colour") end
            end
            -- ground
            if (rec.pt.pattern.holes or 0) > 0 then fail(c, "ground", rec.pt.pattern.holes .. " cells without their piece of the ground") end
            -- edge: the ground ends as its key says: none on paper under
            -- auto, one panel under panel (and auto on a dark backdrop).
            local gfills = 0
            if base.ground then for _, x in ipairs(rec.fills) do if key(x) == key(base.ground) then gfills = gfills + 1 end end end
            local has_ground = false
            for _, r in ipairs(p.roles) do if r == "ground" then has_ground = true end end
            if has_ground and finish == "filled" then
              if ground == "auto" and bd == "light" and base.ground then fail(c, "edge", "a ground on paper under ground=auto") end
              if (ground == "panel" or (ground == "auto" and bd == "dark")) and gfills ~= 1 then
                fail(c, "edge", gfills .. " pieces of ground where one panel belongs")
              end
            end
            -- units: no kolam dot without its loop, no celtic strand ending
            -- loose inside the page (truchet's tiles are not closed, and
            -- not held to it).
            if p.name == "sikku_kolam" or p.name:match("^celtic") then
              local lone, open = Units.count(rec.pt.pattern.kept, { 3, 3, spec.width - 3, spec.height - 3 })
              c.lone, c.open = lone, open
              if lone > 0 then fail(c, "units", lone .. " dots without their loop") end
              if open > 0 then fail(c, "units", open .. " line ends meeting no other") end
            end
            -- onpanel: with the ground as one panel, all the cells paint
            -- lies on it (as far as it lies on the paper).
            if finish == "filled" and base.ground and (ground == "panel" or (ground == "auto" and bd == "dark")) then
              local _, res = Panel.check_page(spec)
              c.off_panel = res.worst
              if res.cells > 0 then fail(c, "onpanel", string.format("%d cells paint up to %.2f pt off the panel", res.cells, res.worst)) end
            end
            -- holes: a cell the field left out with every neighbour kept.
            -- The matrix's page has a hard edge (edge=cell), where only the
            -- text, the hero and the page leave cells out, and none of those
            -- leaves out a cell whose neighbours all stand.
            if finish == "filled" then
              local h = M.holes(rec.pt.pattern)
              c.holes = h
              if h > 0 then fail(c, "holes", h .. " cells left out with every neighbour kept") end
            end
            -- between: a plate that lies between cells runs along their
            -- outlines, so it is never nearer anything than they are
            -- (pattern.lua's footprint leaves it out).
            local bad_between = M.between(rec.pt.pattern)
            if bad_between > 0 then fail(c, "between", bad_between .. " plates between cells that leave their outlines") end
            -- fragments: kept cells with no kept neighbour.
            local iso = M.isolated(rec.pt.pattern.kept)
            c.isolated = #rec.pt.pattern.kept > 0 and iso / #rec.pt.pattern.kept or 0
            if floors.isolated and c.isolated > floors.isolated then
              fail(c, "fragments", string.format("%.1f %% of the cells stand alone", 100 * c.isolated))
            end
            -- contrast: the band against what it lies on, as shown
            local back = Color.backdrop(spec.backdrop)
            local function shown(rgb)
              if not back or base.lit or rgb == Paint.palette.gold then return rgb end
              return Color.on_ground(rgb, back, Paint.palette.paper)
            end
            -- The surfaces a band lies on, the one it lies most on first:
            -- a filled surface's fields (field A first) and its ground, a
            -- line pattern's ground, else the page.
            local on = {}
            if finish == "filled" and p.surface then
              if declared.a and base.fill1 then on[#on + 1] = { "field A", shown(base.fill1) } end
              if declared.b and base.fill2 then on[#on + 1] = { "field B", shown(base.fill2) } end
            end
            if base.ground then on[#on + 1] = { "ground", shown(base.ground) }
            elseif #on == 0 then on[#on + 1] = { "page", back or Paint.palette.paper } end
            local Lb = Color.lightness(shown(base.band))
            local function off(s) return math.abs(Lb - Color.lightness(s[2])) end
            -- contrast: against the surface it lies most on
            c.band_surface, c.band_on = off(on[1]), on[1][1]
            if floors.band and c.band_surface < floors.band then
              fail(c, "contrast", string.format("band and %s differ by %.3f in L", c.band_on, c.band_surface))
            end
            -- vanish: against every surface it lies on
            c.band_any, c.band_any_on = math.huge, nil
            for _, s in ipairs(on) do
              if off(s) < c.band_any then c.band_any, c.band_any_on = off(s), s[1] end
            end
            if floors.band_any and c.band_any < floors.band_any then
              fail(c, "vanish", string.format("band and %s differ by %.3f in L", c.band_any_on, c.band_any))
            end
            -- fields
            local uses_a, uses_b = declared.a, declared.b
            if finish == "filled" and uses_a and uses_b then
              c.ab = de(base.fill1, base.fill2)
              if floors.fields and c.ab < floors.fields then fail(c, "fields", string.format("fields A and B differ by %.3f", c.ab)) end
            end
            seen[bd] = { base = base, rec = rec, spec = spec, shown = shown }
          end
          -- order, across the two backdrops
          local L, D = seen.light, seen.dark
          local c = cells[#cells]
          if L and D then
            -- A dark ground keeps its order to the bands on both backdrops.
            if L.base.ground and D.base.ground and Color.lightness(L.base.ground) < 0.5 then
              local s1 = Color.lightness(L.shown(L.base.band)) - Color.lightness(L.shown(L.base.ground))
              local s2 = Color.lightness(D.shown(D.base.band)) - Color.lightness(D.shown(D.base.ground))
              if s1 * s2 <= 0 then fail(c, "order", "the band and the dark ground swap their lightness order on the dark backdrop") end
            end
            -- Without a dark ground the pattern's paper follows the page:
            -- it is repainted on the dark backdrop with every other ink.
            if not (D.base.ground and Color.lightness(D.base.ground) < 0.5) and D.base.lit then
              fail(c, "order", "the pattern's paper does not follow the dark page")
            end
          end
        end
      end
      end
    end
  end
  -- legacy: full chroma and the old lightnesses give the old colours
  local Tune = require("flora.tune")
  local legacy = { a = { L = 0.74, sat = false, share = 1 }, b = { L = 0.66, sat = false, share = 1 } }
  for _, cw in ipairs({ "ember", "autumn", "plum" }) do
    local pal = Settings.parse("colourway=" .. cw).palette
    require("flora.mix").with_palette(pal, function()
      local rng = Rng.new(5):fork("pattern inks")
      local base = Pattern.role_inks(rng, Patterns.by_name.stars_8_4, { pattern_roles = legacy })
      local tp = Tune.color.palette
      local function old(part, Lv)
        return Color.ink_rgb(Color.ink_for(rng:fork("ink " .. part), tp[part]), Lv, 1)
      end
      local want = { band = old("leaves", 0.22), fill1 = old("blooms", 0.74), fill2 = old("sprays", 0.66) }
      for k, v in pairs(want) do
        if key(v) ~= key(base[k]) then failures[#failures + 1] = cw .. ": legacy: " .. k .. " is not the colour it was" end
      end
    end)
  end
  -- saturation: in every colourway the fields and the ground (and the
  -- dark ground it gives a motif) lose their chroma at saturation 0 and
  -- gain it monotonically from 0 through the default to 1, whatever share
  -- the colourway's palette gives them.
  local ROLES = { fill1 = "field A", fill2 = "field B", ground = "ground", dark = "dark ground" }
  local sat_cells = 0
  for _, cw in ipairs(Inks.colourway_order) do
    local by = {}
    for _, s in ipairs({ 0, 0.5, 1 }) do
      local spec = page("rosette_lattice", "colourway=" .. cw .. ", ground=on, saturation=" .. s)
      require("flora.mix").with_palette(spec.palette, function()
        by[s] = Pattern.role_inks(Rng.new(5):fork("pattern inks"), Patterns.by_name.rosette_lattice, spec)
      end)
    end
    for k, label in pairs(ROLES) do
      local c0, ch, c1 = by[0][k], by[0.5][k], by[1][k]
      sat_cells = sat_cells + 1
      if c0 and ch and c1 then
        local _, C0 = Color.lch(c0)
        local _, Ch = Color.lch(ch)
        local _, C1 = Color.lch(c1)
        if C0 > 2e-3 then failures[#failures + 1] = string.format("%s: saturation: %s keeps chroma %.4f at saturation 0", cw, label, C0) end
        if not (C0 <= Ch + 1e-6 and Ch <= C1 + 1e-6 and C1 > C0) then
          failures[#failures + 1] = string.format("%s: saturation: %s chroma %.4f, %.4f, %.4f at 0, 0.5, 1 is not monotone", cw, label, C0, Ch, C1)
        end
      else
        failures[#failures + 1] = string.format("%s: saturation: %s missing", cw, label)
      end
    end
  end
  M.saturation_cells = sat_cells
  return cells, failures
end

-- The knot as one panel over its field (pat_celtic.lua's field panel,
-- celtic_knot's default under ends=closed, and ends=bleed): no strand ends
-- loose inside the page, in any layout. Under bleed the plait is cut by the
-- paper's edge, which the count leaves out (3 pt of it).
function M.knot(filter)
  local cells, failures = {}, {}
  for _, name in ipairs({ "celtic_knot" }) do
    for _, layout in ipairs({ "left", "right", "centered", "surround" }) do
      for _, mode in ipairs({ "closed", "bleed" }) do
        for _, bd in ipairs({ "light", "dark" }) do
          if not filter or filter(name, layout, mode) then
            local spec = page(name, "colourway=tsuki-mi, ends=" .. mode .. ", backdrop=" .. bd, layout)
            local rec = paint(spec)
            local lone, open = Units.count(rec.pt.pattern.kept, { 3, 3, spec.width - 3, spec.height - 3 })
            local c = { pattern = name, layout = layout, mode = mode, backdrop = bd, kept = #rec.pt.pattern.kept, open = open }
            cells[#cells + 1] = c
            if open > 0 or lone > 0 then
              failures[#failures + 1] = string.format("%s %s %s %s: units: %d line ends meeting no other", name, layout, mode, bd, open)
            end
            if c.kept == 0 and layout ~= "right" then
              failures[#failures + 1] = string.format("%s %s %s %s: units: no cell kept", name, layout, mode, bd)
            end
          end
        end
      end
    end
  end
  return cells, failures
end

-- finish=lacquer over every pattern x colourway (tsuki-mi, ember,
-- usu-zumi) x backdrop. On a pattern with a ground: the ground is one
-- panel (one fill of the ground's colour), the band is gold (before a dark
-- ground lights it), the bands are lines at half width, and a ground the
-- page sets itself goes before the panel. On a pattern without one: the
-- page is the filled page byte for byte, and it says why. Returns cells,
-- failures.
function M.lacquer(filter)
  local cells, failures = {}, {}
  for _, p in ipairs(Patterns.list) do
    if not filter or filter(p.name) then
      for _, cw in ipairs({ "tsuki-mi", "ember", "usu-zumi" }) do
        for _, bd in ipairs({ "light", "dark" }) do
          local where = string.format("%s %s %s", p.name, cw, bd)
          local spec = page(p.name, "colourway=" .. cw .. ", finish=lacquer, backdrop=" .. bd)
          local rec = paint(spec)
          local info = rec.pt.pattern
          local base = info.inks
          cells[#cells + 1] = { pattern = p.name, colourway = cw, backdrop = bd }
          if Pattern.has_ground(p) then
            local eff = Pattern.finish_spec(spec, p)
            local gf = 0
            if base.ground then for _, x in ipairs(rec.fills) do if key(x) == key(base.ground) then gf = gf + 1 end end end
            if not base.ground or gf ~= 1 then failures[#failures + 1] = where .. ": lacquer: " .. gf .. " ground fills where one panel belongs" end
            if key(base.band0) ~= key(Paint.palette.gold) then failures[#failures + 1] = where .. ": lacquer: the band is not gold" end
            if eff.pattern_bands ~= "line" or eff.pattern_bandwidth ~= 0.5 then failures[#failures + 1] = where .. ": lacquer: the bands are not lines at half width" end
            if info.warnings then failures[#failures + 1] = where .. ": lacquer: a warning on a pattern with a ground" end
            -- A ground the page sets goes before the panel.
            local own = paint(page(p.name, "colourway=" .. cw .. ", finish=lacquer, ground=cells, backdrop=" .. bd))
            local gf2 = 0
            local g2 = own.pt.pattern.inks.ground
            if g2 then for _, x in ipairs(own.fills) do if key(x) == key(g2) then gf2 = gf2 + 1 end end end
            if gf2 <= 1 then failures[#failures + 1] = where .. ": lacquer: ground=cells set on the page lost to the panel" end
          else
            local filled = paint(page(p.name, "colourway=" .. cw .. ", finish=filled, backdrop=" .. bd))
            if rec.pt:body() ~= filled.pt:body() then failures[#failures + 1] = where .. ": lacquer: a pattern without a ground is not its filled page" end
            if not (info.warnings and info.warnings[1]) then failures[#failures + 1] = where .. ": lacquer: no warning on a pattern without a ground" end
          end
        end
      end
    end
  end
  return cells, failures
end

-- Each alias of `expect` (alias -> pattern) against its pattern, on the
-- matrix's page, light and dark, named in the spec's pattern weights and in
-- a setup line. Returns the pages compared and those that differ.
function M.aliases(expect)
  local n, bad = 0, {}
  for alias, target in pairs(expect) do
    for _, bd in ipairs({ "light", "dark" }) do
      local want = paint(page(target, "colourway=tsuki-mi, backdrop=" .. bd)).pt:body()
      local raw = paint(page(alias, "colourway=tsuki-mi, backdrop=" .. bd)).pt:body()
      local line = paint(page(target, "pattern=" .. alias .. ", colourway=tsuki-mi, backdrop=" .. bd)).pt:body()
      for _, got in ipairs({ { "spec", raw }, { "setup line", line } }) do
        n = n + 1
        if got[2] ~= want then bad[#bad + 1] = string.format("%s (%s, %s) does not paint as %s", alias, got[1], bd, target) end
      end
    end
  end
  return n, bad
end

return M
