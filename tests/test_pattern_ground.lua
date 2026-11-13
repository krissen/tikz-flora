-- A cell that lays only its piece of the ground takes part in everything
-- a cell does: its growth time and its fading.
--
-- growth  pattern x ground (off, on) x edge x density (0.02, where
--         dissolve keeps no cell and only ground is laid, 0.3, 3) x
--         backdrop: every part a cell paints is born inside the growth
--         interval, [0, 1], and ends by 1.01 (END), and the last frame of growth (spec.grow just
--         under 1) is the finished page byte for byte
-- fade    pattern x ground x backdrop under edge=fade: every colour a
--         faded cell paints, as shown, lies between the colour the cell
--         paints whole and the page's actual colour (OKLab), and comes
--         nearer the page as the cell fades further (lower a). The pairs
--         come from painting the page twice, the second time with every
--         cell whole.
--
-- Then proof that each check fails when its fault is put back into
-- pattern.lua's source: growth time normalised over the kept cells only,
-- cells off the page born before the growth begins, and cells faded
-- toward the light paper on a dark ground.
local H = dofile("tests/helper.lua")
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Progression = require("flora.progression")
local Patterns = require("flora.patterns")
local Color = require("flora.color")
local Settings = require("flora.settings")

local verbose = os.getenv("FLORA_MATRIX_VERBOSE")
local CELL = { pattern_ground = true, pattern_line = true, pattern = true }

local function spec_of(name, setup, extra)
  local spec = { width = 300, height = 240, text = { x0 = 130, y0 = 30, x1 = 280, y1 = 210 }, seed = 7, layout = "left" }
  Settings.to_spec(Settings.parse("pattern=" .. name .. ", " .. setup), spec)
  for k, v in pairs(extra or {}) do spec[k] = v end
  return spec
end

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

-- Paint a page, recording each cell part's birth and duration, and each
-- colour a cell part paints as it is shown (Paint:ink, which a dark ground
-- turns off) with the part's anchor.
local function paint(spec)
  local parts, colours, kind, anchor = {}, {}, nil, nil
  local fill, stroke, part = Paint.fill, Paint.stroke, Progression.part
  local function rec(self, rgb)
    if self.group and self.group.tag == "pattern" and CELL[kind] then colours[#colours + 1] = { self:ink(rgb), anchor } end
  end
  Paint.fill = function(self, cmds, rgb, ...) rec(self, rgb); return fill(self, cmds, rgb, ...) end
  Paint.stroke = function(self, cmds, rgb, ...) rec(self, rgb); return stroke(self, cmds, rgb, ...) end
  Progression.part = function(pt, k, a, birth, duration, fn, ...)
    if CELL[k] then parts[#parts + 1] = { k, birth, duration } end
    return part(pt, k, a, birth, duration, function()
      local uk, ua = kind, anchor
      kind, anchor = k, a
      local ok, r = pcall(fn)
      kind, anchor = uk, ua
      if not ok then error(r, 0) end
      return r
    end, ...)
  end
  Paint.reset_resources()
  local ok, pt = pcall(Compose.page, spec)
  Paint.fill, Paint.stroke, Progression.part = fill, stroke, part
  if not ok then error(pt, 0) end
  return pt, parts, colours
end

local EDGES = { "dissolve", "cell", "fade", "border", "guilloche" }
local DENSITIES = { 0.02, 0.3, 3 }
-- The latest a cell part may end: the latest birth (0.88), the step to
-- its painting (0.05) and the painting itself (0.08), pattern.lua. The
-- progression stretches to its latest part (progression.lua), so one born
-- far later squeezes every other part to its first frames.
local END = 0.88 + 0.05 + 0.08

local function growth(filter)
  local cells, failures, ground_only, latest = 0, {}, 0, 0
  for _, p in ipairs(Patterns.list) do
    if not filter or filter(p.name) then
      for _, ground in ipairs({ "off", "on" }) do
        for _, edge in ipairs(EDGES) do
          for _, dens in ipairs(DENSITIES) do
            for _, bd in ipairs({ "light", "dark" }) do
              cells = cells + 1
              local setup = string.format("ground=%s, edge=%s, density=%s, backdrop=%s", ground, edge, dens, bd)
              local where = p.name .. " " .. setup
              local pt, parts = paint(spec_of(p.name, setup))
              if pt.pattern.cells == 0 and (pt.pattern.grounded or 0) > 0 then ground_only = ground_only + 1 end
              local bad = 0
              for _, q in ipairs(parts) do
                latest = math.max(latest, q[2] + q[3])
                if q[2] < 0 or q[2] > 1 or q[2] + q[3] > END + 1e-9 then bad = bad + 1 end
              end
              if bad > 0 then failures[#failures + 1] = string.format("%s: growth: %d parts outside [0, 1]", where, bad) end
              local last = select(1, paint(spec_of(p.name, setup, { grow = 0.9999 })))
              if last:body() ~= pt:body() then failures[#failures + 1] = where .. ": growth: the last frame is not the page" end
            end
          end
        end
      end
    end
  end
  return cells, failures, ground_only, latest
end

local function fade(filter)
  local cells, pairs_, failures = 0, 0, {}
  local Pattern = require("flora.pattern")
  for _, p in ipairs(Patterns.list) do
    if not filter or filter(p.name) then
      for _, ground in ipairs({ "off", "on" }) do
        for _, bd in ipairs({ "light", "dark" }) do
          cells = cells + 1
          local setup = string.format("ground=%s, edge=fade, density=2, backdrop=%s", ground, bd)
          local where = p.name .. " " .. setup
          local spec = spec_of(p.name, setup)
          local pt, _, faded = paint(spec)
          local a_of = {}
          for _, k in ipairs(pt.pattern.kept) do a_of[k.cell.x .. "," .. k.cell.y] = k.a end
          -- The same page with every cell whole.
          local cell_inks = Pattern.cell_inks
          Pattern.cell_inks = function(base, _, hero) return cell_inks(base, 1, hero) end
          local ok, err, _, whole = pcall(paint, spec)
          Pattern.cell_inks = cell_inks
          if not ok then error(err, 0) end
          if #whole ~= #faded then
            failures[#failures + 1] = where .. ": fade: the whole page paints " .. #whole .. " colours, the faded one " .. #faded
          else
            local page = Color.backdrop(spec.backdrop) or Paint.palette.paper
            local by, bad, near = {}, 0, 0
            for i, f in ipairs(faded) do
              local w, x = whole[i][1], f[1]
              local a = a_of[f[2][1] .. "," .. f[2][2]] or 1
              if a < 1 then
                pairs_ = pairs_ + 1
                local d_wp = de(w, page)
                if de(x, page) > d_wp + 1e-3 or de(x, w) > d_wp + 1e-3 then bad = bad + 1 end
                local key = string.format("%.4f,%.4f,%.4f", w[1], w[2], w[3])
                by[key] = by[key] or {}
                table.insert(by[key], { a, de(x, page) })
              end
            end
            for _, list in pairs(by) do
              table.sort(list, function(u, v) return u[1] < v[1] end)
              for i = 2, #list do if list[i][2] < list[i - 1][2] - 1e-3 then near = near + 1 end end
            end
            if bad > 0 then failures[#failures + 1] = string.format("%s: fade: %d colours not between the whole colour and the page", where, bad) end
            if near > 0 then failures[#failures + 1] = string.format("%s: fade: %d colours farther from the page than a less faded one", where, near) end
          end
        end
      end
    end
  end
  return cells, pairs_, failures
end

local gc, gf, ground_only, latest = growth()
H.check(gc == #Patterns.list * 2 * #EDGES * #DENSITIES * 2, "growth cells: " .. gc)
H.check(ground_only > 0, "no growth cell lays ground with no cell kept")
for _, f in ipairs(gf) do H.check(false, f) end
local fc, fp, ff = fade()
H.check(fc == #Patterns.list * 2 * 2, "fade cells: " .. fc)
H.check(fp > 0, "no faded colours were compared")
for _, f in ipairs(ff) do H.check(false, f) end
if verbose then
  print(string.format("growth: %d cells (%d lay ground with no cell kept), latest part ends at %.4f, %d failures", gc, ground_only, latest, #gf))
  print(string.format("fade: %d cells, %d faded colours compared, %d failures", fc, fp, #ff))
end

-- The faults put back into pattern.lua's source, one at a time.
local function mutated(old, new, check)
  local f = io.open("lua/flora/pattern.lua")
  local src = f:read("a")
  f:close()
  local i, j = src:find(old, 1, true)
  H.check(i ~= nil, "mutation: the line to put the fault back into is gone: " .. old)
  if not i then return nil end
  local real = package.loaded["flora.pattern"]
  package.loaded["flora.pattern"] = assert(load(src:sub(1, i - 1) .. new .. src:sub(j + 1), "@pattern.lua (mutated)"))()
  local ok, a, b, c = pcall(check)
  package.loaded["flora.pattern"] = real
  if not ok then error(a, 0) end
  return a, b, c
end
local some = function(n) return n == "asanoha" or n == "sikku_kolam" or n == "rosette_lattice" end

local _, f6 = mutated("for _, k in ipairs(grounded) do far = math.max(far, root(k.cell)) end",
  "for _, k in ipairs(kept) do far = math.max(far, root(k.cell)) end", function() return growth(some) end)
H.check(f6 and #f6 > 0, "the growth check missed growth time normalised over the kept cells only")
local _, _, f7 = mutated("local to = (not hero and base.fade) or pal.paper", "local to = pal.paper",
  function() return fade(some) end)
H.check(f7 and #f7 > 0, "the fade check missed cells faded toward the light paper on a dark ground")
-- A cell whose centre lies off the page born before the growth begins.
local _, early = mutated("if side and side.left and c.x < text.x0 then return math.max(0, c.x) end",
  "if side and side.left and c.x < text.x0 then return c.x end", function() return growth(function(n) return n == "truchet" end) end)
H.check(early and #early > 0, "the growth check missed cells born before the growth begins")
if verbose then
  print(string.format("mutation far-over-kept: %d failures", f6 and #f6 or -1))
  print(string.format("mutation fade-to-paper: %d failures", f7 and #f7 or -1))
  print(string.format("mutation born-before-start: %d failures", early and #early or -1))
end

H.done("pattern ground")
