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

local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Settings = require("flora.settings")
local Patterns = require("flora.patterns")
local Pattern = require("flora.pattern")
local Color = require("flora.color")
local Inks = require("flora.inks")
local Rng = require("flora.rng")

local M = {}

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
  local rec = { fills = {}, strokes = {} }
  local fill, stroke = Paint.fill, Paint.stroke
  Paint.fill = function(self, cmds, rgb, ...)
    if self.group and self.group.tag == "pattern" then rec.fills[#rec.fills + 1] = rgb end
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

local function page(name, setup)
  local spec = { width = 300, height = 240, text = { x0 = 130, y0 = 30, x1 = 280, y1 = 210 }, seed = 7,
    layout = "left", pattern = { [name] = 1 }, pattern_edge = "cell" }
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

function M.run(floors, filter)
  local cells, failures = {}, {}
  local function fail(c, what, msg)
    failures[#failures + 1] = string.format("%s %s ground=%s %s %s: %s: %s", c.pattern, c.colourway, c.ground, c.backdrop, c.finish, what, msg)
  end
  for _, p in ipairs(Patterns.list) do
    for _, cw in ipairs(Inks.colourway_order) do
      for _, ground in ipairs({ "off", "on" }) do
      for _, finish in ipairs({ "filled", "lines" }) do
        if not filter or filter(p.name, cw, finish) then
          local seen = {}
          for _, bd in ipairs({ "light", "dark" }) do
            local spec = page(p.name, "colourway=" .. cw .. ", finish=" .. finish .. ", ground=" .. ground .. ", backdrop=" .. bd)
            local rec = paint(spec)
            local base = rec.pt.pattern.inks
            local c = { pattern = p.name, colourway = cw, backdrop = bd, finish = finish, ground = ground }
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
            -- ground
            if (rec.pt.pattern.holes or 0) > 0 then fail(c, "ground", rec.pt.pattern.holes .. " cells without their piece of the ground") end
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

return M
