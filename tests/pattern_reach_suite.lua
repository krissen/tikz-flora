-- Nothing a pattern's cell paints lies nearer the text, the hero or the
-- paper's margin than the field keeps (tests/pattern_reach.lua measures
-- the paint itself), over every pattern x ground x edge x layout x outer
-- and hero x scale, and proof that the sweep fails when the field places
-- cells by their outline alone.
-- Split over tests/test_pattern_reach_1.lua .. _3.lua: each runs
-- run(part, parts), its share of the patterns (the sweep and its auto
-- ground on the dark backdrop) and of the mutations (tests/split.lua).
local H = dofile("tests/helper.lua")
local M = dofile("tests/pattern_reach.lua")
local Patterns = require("flora.patterns")
local Pattern = require("flora.pattern")

-- What each item weighs, in CPU seconds (just test-times, 2026-11): a
-- pattern's share of the sweep and of the dark one, and each mutation.
local GROUNDS = { "auto", "panel", "motif", "round", "cells", "on" }
local WEIGHTS = {
  { "pattern:asanoha", 30 }, { "pattern:celtic_knot", 18 }, { "pattern:greek_crosses", 25 }, { "pattern:hexagram_lattice", 22 },
  { "pattern:khatam", 21 }, { "pattern:kikko", 18 }, { "pattern:overlapping_circles", 7 }, { "pattern:penrose_rhombs", 24 },
  { "pattern:rosette_lattice", 44 }, { "pattern:seigaiha", 7 }, { "pattern:shippo", 8 }, { "pattern:sikku_kolam", 69 },
  { "pattern:stars_8_4", 41 }, { "pattern:truchet", 16 },
  { "mutant:outline-only", 99 }, { "mutant:panel-edge-to-edge", 26 },
}
for _, g in ipairs(GROUNDS) do WEIGHTS[#WEIGHTS + 1] = { "mutant:ground larger:" .. g, 19 } end

return function(part, parts)
local S = dofile("tests/split.lua").new(part, parts, WEIGHTS)

local verbose = os.getenv("FLORA_MATRIX_VERBOSE")
local mine, nmine = {}, 0
for _, p in ipairs(Patterns.list) do
  if S.mine("pattern:" .. p.name) then mine[p.name] = true; nmine = nmine + 1 end
end
local function owned(name) return mine[name] end
local cells, failures = M.run(owned)
if verbose then print(string.format("reach: %d cells, %d failures (part %d of %d)", #cells, #failures, part, parts)) end
S.check(H, #cells == nmine * #M.GROUNDS * #M.EDGES * 2 * #M.VARIANTS * 2, "reach cells: " .. #cells)
-- And auto on the dark backdrop, where it lays the ground as one panel.
do
  local grounds = M.GROUNDS
  M.GROUNDS, M.BACKDROP = { "auto" }, "dark"
  local dc, df = M.run(owned)
  M.GROUNDS, M.BACKDROP = grounds, nil
  if verbose then print(string.format("reach, auto on the dark backdrop: %d cells, %d failures", #dc, #df)) end
  for _, f in ipairs(df) do H.check(false, "dark: " .. f) end
end
-- At scale 3 the larger cells do not fit inside the small page's margin,
-- so some of those cells paint nothing; at scale 1 every cell paints.
local empty, empty1 = 0, 0
for _, c in ipairs(cells) do
  if c.points == 0 then
    empty = empty + 1
    if c.where:find("scale=1$") then empty1 = empty1 + 1; H.check(false, "reach cell painted nothing: " .. c.where) end
  end
end
if verbose then print(string.format("reach: %d cells paint nothing (%d at scale 1)", empty, empty1)) end
for _, f in ipairs(failures) do H.check(false, f) end

-- Each mutation below breaks how the field measures what it lays, and
-- runs with the precondition that measures each form again where it is
-- painted (Pattern.lays) waived; that precondition would otherwise leave
-- the mismeasured paint out, and tests/test_pattern_protect.lua proves it
-- form by form.
local function unchecked(fn, ...)
  local lays = Pattern.lays
  Pattern.lays = function() return true end
  local r = table.pack(pcall(fn, ...))
  Pattern.lays = lays
  return table.unpack(r, 1, r.n)
end

-- The field placing cells by their outline alone, as it did before their
-- ground and plates were counted: the ground squares of the dot grids
-- reach past their dots into the text.
if S.mine("mutant:outline-only") then
  local footprint = Pattern.footprint
  Pattern.footprint = function(c) return { c } end
  local ok, _, fs = unchecked(M.run, function(n) return n == "sikku_kolam" or n == "rosette_lattice" end)
  Pattern.footprint = footprint
  H.check(ok and #fs > 0, "the reach sweep missed cells placed by their outline alone")
  if verbose then print(string.format("mutation outline-only: %d failing cells", ok and #fs or -1)) end
end

-- The ground's panel as it was first drawn: its side of the page edge to
-- edge, under the hero and into the margin.
if S.mine("mutant:panel-edge-to-edge") then
  local panel_path = Pattern.panel_path
  Pattern.panel_path = function(f)
    local t, o = f.text, f.gap
    local x0, x1 = -2, f.W + 2
    if f.side and f.side.left and not f.side.right then x1 = t.x0 - o end
    if f.side and f.side.right and not f.side.left then x0 = t.x1 + o end
    return { { "m", x0, -2 }, { "l", x1, -2 }, { "l", x1, f.top + 2 }, { "l", x0, f.top + 2 }, { "z" } }
  end
  local ok2, _, fs2 = unchecked(M.run, function(n) return n == "asanoha" end)
  Pattern.panel_path = panel_path
  H.check(ok2 and #fs2 > 0, "the reach sweep missed a ground panel under the hero and in the margin")
  if verbose then print(string.format("mutation panel-edge-to-edge: %d failing cells", ok2 and #fs2 or -1)) end
end

-- Every way the ground is laid, a piece larger than the field measured:
-- each piece grown a third about its cell, the panel 8 pt past its edges.
-- Under ground=off nothing is laid, so there is nothing to grow.
do
  local edge_pieces = Pattern.edge_pieces
  local function grown(cmds, x, y, k)
    local out = {}
    for _, c in ipairs(cmds) do
      if type(c[1]) == "table" then out[#out + 1] = grown(c, x, y, k)
      elseif c[1] == "o" then out[#out + 1] = { "o", x + (c[2] - x) * k, y + (c[3] - y) * k, c[4] * k }
      else
        local d = { c[1] }
        for i = 2, #c, 2 do d[i], d[i + 1] = x + (c[i] - x) * k, y + (c[i + 1] - y) * k end
        out[#out + 1] = d
      end
    end
    return out
  end
  Pattern.edge_pieces = function(mode, f, info)
    local r = edge_pieces(mode, f, info)
    if r.panel then
      local p = {}
      for _, c in ipairs(r.panel) do
        if c[1] == "m" or c[1] == "l" then p[#p + 1] = { c[1], c[2] + (c[2] > f.W / 2 and 8 or -8), c[3] + (c[3] > f.top / 2 and 8 or -8) }
        else p[#p + 1] = c end
      end
      return { panel = p, drops = r.drops }
    end
    local piece = r.piece
    return { drops = r.drops, piece = function(k, path, colour)
      local q, col = piece(k, path, colour)
      if q then q = grown(q, k.cell.x, k.cell.y, 1.34) end
      return q, col
    end }
  end
  local grounds = M.GROUNDS
  for _, g in ipairs(GROUNDS) do
    if S.mine("mutant:ground larger:" .. g) then
    M.GROUNDS = { g }
    -- auto lays its ground (the panel) on a dark backdrop only.
    M.BACKDROP = g == "auto" and "dark" or nil
    local ok_larger, _, fs_larger = unchecked(M.run, function(n) return n == "asanoha" or n == "sikku_kolam" or n == "rosette_lattice" end)
    H.check(ok_larger and #fs_larger > 0, "the reach sweep missed a ground piece larger than measured under ground=" .. g)
    if verbose then print(string.format("mutation ground larger than measured, ground=%s: %d failing cells", g, ok_larger and #fs_larger or -1)) end
    end
  end
  M.GROUNDS = grounds
  M.BACKDROP = nil
  Pattern.edge_pieces = edge_pieces
end

S.finish(H)
H.done("pattern reach " .. part)
end
