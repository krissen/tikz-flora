-- The perimeter band's invariant matrix (tests/test_pattern_perimeter.lua): every
-- pattern x band width x paper x edge (each value and none) x backdrop, on
-- a page with a frame title, the theme's top inset and header clip, and a
-- reservation in the top band. M.run returns the cells swept and every
-- failure, each named by its invariant:
--
--   text      nothing is painted in the text block or a reservation: every
--             kept cell keeps the gap from them, or (edge=border) the band
--             is cut round each of them, grown by the gap
--   width     the band is as wide on all four sides: every side has cells,
--             none reaches past the band (past the margin under dissolve),
--             and edge=border cuts it along the band's own inner rectangle
--   gaps      the cells meet the paper alike on opposite sides
--   straight  edge=border's cut is the inner rectangle itself, and whole
--             rows of a pattern whose rows end straight cover the band's
--             innermost repeat
--   rows      whole rows fill the band: the innermost cell on every side
--             ends on its inner edge
--   top       the band runs above the text under the frame title and the
--             reservation
--   warn      each warning the page should give comes once, and no other
--
-- Sizes are as users get them: the papers in mm, the bands in mm.

package.path = "./lua/?.lua;" .. package.path
local Patterns = require("flora.patterns")
local Pattern = require("flora.pattern")
local Compose = require("flora.compose")
local Band = require("flora.band")
local Paint = require("flora.paint")

local M = {}

local MM = 72 / 25.4
local GAP = 6
M.PAPERS = { { "16:9", 160, 90 }, { "4:3", 128, 96 }, { "A4", 210, 297 } }
M.WIDTHS = { 8, 12, 18 }
M.EDGES = { false, "border", "cell", "fade", "dissolve", Band.ROWS }
M.BACKDROPS = { "light", "dark" }

-- The patterns whose whole rows end in a straight edge (their band's own
-- edge), and how much of the innermost repeat their whole cells cover.
M.STRAIGHT_ROWS = { asanoha = 0.999, stars_8_4 = 0.9 }

-- The page: the text block `w` + 4 mm in from every edge, a frame title
-- in it, the theme's top inset and header clip, and a reservation in the
-- top band's right half.
function M.spec(pattern, wmm, paper, edge, backdrop)
  local W, H = paper[2] * MM, paper[3] * MM
  local m = (wmm + 4) * MM
  local t = { x0 = m, y0 = m, x1 = W - m, y1 = H - m }
  local spec = {
    width = W, height = H, text = t,
    lines = { { x0 = t.x0, y0 = t.y1 - 16, x1 = t.x0 + 140, y1 = t.y1 } },
    header_y = t.y1, header = "margin", frametitle = true, frametitle_height = 16, top_inset = 20,
    tune = { gesture = { header_clip = 1, header_gap = 12 } },
    reserve = { { W - 40 * MM, H - wmm * MM / 2, W - 10 * MM, H } },
    seed = 11, layout = Band.LAYOUT, pattern = pattern, perimeter_width = wmm, ornaments = {},
    backdrop = backdrop == "dark" and "dark" or nil,
  }
  if edge then spec.pattern_edge = edge end
  return spec
end

-- The warnings the page should give, as patterns of their text.
function M.expected(p, wmm, edge)
  local out = {}
  local e = edge or Band.default_edge(p.name)
  local narrowest = Band.NARROWEST[p.name]
  if narrowest and wmm < narrowest then out[#out + 1] = "does not carry a perimeter band" end
  local px = Pattern.periods(p)
  if e == Band.ROWS and not p.field_panel then
    local plan = Pattern.row_plan({}, p, wmm * MM)
    if not (px and plan) then out[#out + 1] = "no repeat to lay in whole rows"
    elseif plan.below then out[#out + 1] = "smaller than its floor" end
  end
  if e == Band.ROWS and p.field_panel and wmm < 12 then out[#out + 1] = "no closed panel fits" end
  return out
end

local function bbox(P)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, v in ipairs(P) do x0, y0, x1, y1 = math.min(x0, v[1]), math.min(y0, v[2]), math.max(x1, v[1]), math.max(y1, v[2]) end
  return x0, y0, x1, y1
end

local function same_rect(a, b, tol)
  for i = 1, 4 do if math.abs(a[i] - b[i]) > tol then return false end end
  return true
end

-- Checks one page; returns its failures as { invariant, text }.
function M.check(p, wmm, paper, edge, backdrop)
  local spec = M.spec(p.name, wmm, paper, edge, backdrop)
  local W, H = spec.width, spec.height
  local t = { spec.text.x0, spec.text.y0, spec.text.x1, spec.text.y1 }
  local keep = { t }
  for _, r in ipairs(spec.reserve) do keep[#keep + 1] = r end
  local w = wmm * MM
  Paint.reset_resources()
  local pt = Compose.page(spec)
  local q = pt.pattern
  local fails = {}
  local function fail(inv, msg) fails[#fails + 1] = { inv, msg } end
  local band = q.band or { inner = q.inner, w = q.w }
  local inner = band.inner
  -- text
  if inner == "rule" then
    for _, r in ipairs(keep) do
      local want = { r[1] - GAP, r[2] - GAP, r[3] + GAP, r[4] + GAP }
      local found = false
      for _, h in ipairs(band.cuts or {}) do if same_rect(h, want, 1e-6) then found = true end end
      if not found then fail("text", "the band is not cut round a kept rectangle") end
    end
  else
    for _, k in ipairs(q.kept) do
      for _, r in ipairs(keep) do
        if Pattern.clearance(k.cell, r) - (q.reach or 0) < GAP - 1e-3 then
          fail("text", string.format("a cell at %.1f, %.1f lies %.2f pt from a kept rectangle", k.cell.x, k.cell.y, Pattern.clearance(k.cell, r)))
          break
        end
      end
    end
  end
  -- width, gaps, rows, top
  local L, R, B, T = math.huge, -math.huge, math.huge, -math.huge
  local inmost = { l = -math.huge, r = -math.huge, b = -math.huge, t = -math.huge }
  local count = { l = 0, r = 0, b = 0, t = 0 }
  local top = 0
  for _, k in ipairs(q.kept) do
    local c = k.cell
    local x0, y0, x1, y1 = bbox(c.verts)
    L, R, B, T = math.min(L, x0), math.max(R, x1), math.min(B, y0), math.max(T, y1)
    if c.x < w and c.y > w and c.y < H - w then count.l = count.l + 1; inmost.l = math.max(inmost.l, x1) end
    if c.x > W - w and c.y > w and c.y < H - w then count.r = count.r + 1; inmost.r = math.max(inmost.r, W - x0) end
    if c.y < w and c.x > w and c.x < W - w then count.b = count.b + 1; inmost.b = math.max(inmost.b, y1) end
    if c.y > H - w and c.x > w and c.x < W - w then count.t = count.t + 1; inmost.t = math.max(inmost.t, H - y0) end
    if c.y > t[4] and c.x > t[1] and c.x < t[3] then top = top + 1 end
  end
  if inner ~= "panel" then
    for side, n in pairs(count) do
      if n == 0 then fail("width", "no cells on side " .. side) end
    end
  end
  -- No cell reaches into the inner rectangle (whole rows touch it; under
  -- dissolve the cells may reach into the margin, which "text" holds).
  if inner == "cells" or inner == "fade" or inner == "rows" then
    local I = { w, w, W - w, H - w }
    local slack = inner == "rows" and 1e-3 or 0
    local Ii = { I[1] + slack, I[2] + slack, I[3] - slack, I[4] - slack }
    for _, k in ipairs(q.kept) do
      local d = Pattern.clearance(k.cell, Ii)
      if d <= 0 or (inner ~= "rows" and d < (q.reach or 0) - 1e-3) then
        fail("width", string.format("a cell at %.1f, %.1f reaches into the band's inner rectangle", k.cell.x, k.cell.y))
        break
      end
    end
  end
  if inner == "rule" then
    local I = { w, w, W - w, H - w }
    if not (band.cuts and band.cuts[1] and same_rect(band.cuts[1], I, 1e-6)) then
      fail("width", "edge=border does not cut the band along its inner rectangle")
      fail("straight", "edge=border's cut is not the inner rectangle")
    end
  end
  -- penrose_rhombs has no repeat and no centre to be laid about alike.
  if p.name ~= "penrose_rhombs" then
    if math.abs(L - (W - R)) > 1e-3 then fail("gaps", string.format("left %.3f and right %.3f differ", L, W - R)) end
    if math.abs(B - (H - T)) > 1e-3 then fail("gaps", string.format("foot %.3f and top %.3f differ", B, H - T)) end
  end
  if inner == "rows" then
    local need = M.STRAIGHT_ROWS[p.name]
    if need and (q.cover or 0) < need then fail("straight", string.format("whole rows cover %.2f of the innermost repeat", q.cover or 0)) end
    if need then
      for side, v in pairs(inmost) do
        if math.abs(v - w) > 1e-3 then fail("rows", string.format("side %s's rows end %.3f pt in, not on the band's %.3f", side, v, w)) end
      end
    end
  end
  if top == 0 then fail("top", "no cells above the text under the frame title") end
  -- warn
  local got = pt.pattern_warnings or {}
  local want = M.expected(p, wmm, edge)
  for _, pat in ipairs(want) do
    local n = 0
    for _, g in ipairs(got) do if g:find(pat, 1, true) then n = n + 1 end end
    if n ~= 1 then fail("warn", string.format("'%s' given %d times", pat, n)) end
  end
  for _, g in ipairs(got) do
    local known = false
    for _, pat in ipairs(want) do if g:find(pat, 1, true) then known = true end end
    if not known then fail("warn", "unexpected warning: " .. g) end
  end
  return fails
end

-- The sweep, over `opts` (lists that narrow it: patterns, widths, papers,
-- edges, backdrops). Returns the cells swept and the failures, each
-- { invariant, where, text }.
function M.run(opts)
  opts = opts or {}
  local cells, failures = 0, {}
  for _, p in ipairs(Patterns.list) do
    if not opts.patterns or opts.patterns[p.name] then
      for _, wmm in ipairs(opts.widths or M.WIDTHS) do
        for _, paper in ipairs(opts.papers or M.PAPERS) do
          for _, edge in ipairs(opts.edges or M.EDGES) do
            for _, bd in ipairs(opts.backdrops or M.BACKDROPS) do
              cells = cells + 1
              local where = string.format("%s %g mm %s edge=%s %s", p.name, wmm, paper[1], tostring(edge or "(none)"), bd)
              for _, f in ipairs(M.check(p, wmm, paper, edge, bd)) do
                failures[#failures + 1] = { f[1], where, f[2] }
              end
            end
          end
        end
      end
    end
  end
  return cells, failures
end

return M
