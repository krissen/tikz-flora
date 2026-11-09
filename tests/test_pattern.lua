-- Geometric patterns (patterns.lua, pattern.lua): the settings, the pick
-- by name and group, where the field may paint, what density and the
-- edge modes do, and growth.
local H = dofile("tests/helper.lua")
local Settings = require("flora.settings")
local Patterns = require("flora.patterns")
local Compose = require("flora.compose")
local Paint = require("flora.paint")
local P = require("flora.progression")
local Rng = require("flora.rng")

-- Settings.
local s = Settings.parse("pattern=asanoha, edge=fade, outer=margin, scale=1.5")
H.check(s.pattern.asanoha == 1 and s.edge == "fade" and s.outer == "margin" and s.scale == 1.5, "pattern keys parse")
s = Settings.parse("pattern={japanese=2, stars_8_4=0}")
H.check(s.pattern.japanese == 2 and s.pattern.stars_8_4 == 0, "pattern weights and groups parse")
for _, bad in ipairs({ "pattern=paisley", "pattern={asanoha=11}", "edge=soft", "outer=wrap", "scale=9" }) do
  H.check(not pcall(Settings.parse, bad), bad .. " was accepted")
end

-- Every pattern describes itself and covers a box with cells.
for _, p in ipairs(Patterns.list) do
  H.check(p.name:match("^[%l%d_]+$") and #p.title > 10 and #p.tags > 0, p.name .. ": name, title or tags")
  local cells = p.cells({ x0 = 0, y0 = 0, x1 = 120, y1 = 120, size = p.scale, rng = Rng.new(1) })
  H.check(#cells > 10, p.name .. ": too few cells")
  for _, c in ipairs(cells) do
    H.check(c.x and c.y and #c.verts >= 3 and c.paint and c.construct, p.name .. ": incomplete cell")
  end
end

-- The catalog lists every pattern with its groups.
local listed = {}
for _, e in ipairs(require("flora.catalog").build().patterns) do listed[e.name] = #e.tags > 0 end
for _, p in ipairs(Patterns.list) do H.check(listed[p.name], p.name .. ": missing from the catalog") end

-- Weights: a name overrides its groups; a group weighs its members.
local stars, asa = Patterns.by_name.stars_8_4, Patterns.by_name.asanoha
H.check(Patterns.weight({ japanese = 2 }, asa) == 2 and Patterns.weight({ japanese = 2 }, stars) == 0, "group weight")
H.check(Patterns.weight({ japanese = 2, asanoha = 0 }, asa) == 0, "a name overrides its group")
H.check(Patterns.pick(Rng.new(3), { islamic = 1 }) == stars, "group pick")
H.check(Patterns.pick(Rng.new(3), { asanoha = 0 }) == nil, "all-zero weights pick nothing")

-- A page.
local function page(opts)
  local sp = { width = 360, height = 270, text = { x0 = 120, y0 = 40, x1 = 330, y1 = 230 }, seed = 7,
    layout = "left", pattern = { stars_8_4 = 1 } }
  for k, v in pairs(opts or {}) do sp[k] = v end
  local seen = {}
  sp.probe = function(x, y, r) seen[#seen + 1] = { x, y, r or 0 } end
  Paint.reset_resources()
  local pt = Compose.page(sp)
  return pt, seen, sp
end

local pt, seen, sp = page()
H.check(pt.pattern and pt.pattern.name == "stars_8_4" and pt.pattern.cells > 20, "pattern page painted no cells")
local clear = true
for _, q in ipairs(seen) do
  if q[1] + q[3] > sp.text.x0 and q[2] + q[3] > sp.text.y0 and q[2] - q[3] < sp.text.y1 and q[1] - q[3] < sp.text.x1 then
    clear = false
  end
end
H.check(clear, "the pattern painted on the text")
H.check(pt:body() == select(1, page()):body(), "the same seed paints a different page")
H.check(pt:body() ~= select(1, page({ seed = 8 })):body(), "another seed paints the same page")

-- A pattern weighed to nothing leaves the page to flora.
local flora = page({ pattern = { stars_8_4 = 0 }, mix = { gyps = 0, cyme = 0, umbel = 0 } })
H.check(not flora.pattern and #flora.out > 0, "zero weights did not fall back to flora")

-- Density fills monotonically; 0 paints nothing.
local last = -1
for _, d in ipairs({ 0, 0.5, 1, 2, 5 }) do
  local n = page({ mix = { density = d } }).pattern.cells
  H.check(n >= last, "density " .. d .. " paints fewer cells than less density")
  if d == 0 then H.check(n == 0, "density 0 paints cells") end
  last = n
end

-- Edge modes: whole cells keep a hard edge (no fewer cells than
-- dissolve), fade pales cells instead of dropping them, border adds a frame.
local dissolve = page().pattern.cells
local cell = page({ pattern_edge = "cell" }).pattern.cells
local fade = page({ pattern_edge = "fade" })
H.check(cell >= dissolve * 0.6, "cell mode keeps too few cells")
H.check(fade.pattern.cells >= dissolve, "fade drops cells")
H.check(not fade:body():find(" gs ", 1, true), "fade painted translucent instead of mixing with paper")
local framed = false
for _, q in ipairs(select(2, page({ pattern_edge = "border" }))) do
  if math.abs(q[1] - (sp.text.x0 - 6)) < 0.01 and math.abs(q[2] - (sp.text.y0 - 6)) < 0.01 then framed = true end
end
H.check(framed, "border painted no frame round the text")

-- Outer edge: margin keeps every point on the page; bleed runs off it.
local function off_page(points)
  for _, q in ipairs(points) do
    if q[1] < 0 or q[2] < 0 or q[1] > 360 or q[2] > 270 then return true end
  end
  return false
end
H.check(off_page(select(2, page())), "bleed stays on the page")
H.check(not off_page(select(2, page({ pattern_outer = "margin" }))), "margin runs off the page")

-- Layout: a right margin pattern stays right of the text.
local _, right = page({ layout = "right", text = { x0 = 30, y0 = 40, x1 = 240, y1 = 230 } })
local ok = true
for _, q in ipairs(right) do if q[1] + q[3] < 240 and q[2] > 40 and q[2] < 230 then ok = false end end
H.check(ok, "a right-layout pattern painted left of the text")

-- Scale makes larger cells, so fewer of them.
H.check(page({ pattern_scale = 2 }).pattern.offered < page().pattern.offered, "scale 2 did not enlarge cells")

-- The palette paints the pattern: an ink for the leaves recolours the bands.
local plain = page():body()
local inked = page({ palette = { leaves = "kon-peki", blooms = "yu-yake" } }):body()
H.check(plain ~= inked, "the palette did not change the pattern's colours")

-- Growth: two parts per cell, the last frame the page painted at once.
for _, name in ipairs({ "stars_8_4", "asanoha" }) do
  local function spec()
    return { width = 360, height = 270, text = { x0 = 120, y0 = 40, x1 = 330, y1 = 230 }, seed = 7,
      layout = "left", pattern = { [name] = 1 } }
  end
  Paint.reset_resources()
  local ordinary = Compose.page(spec())
  Paint.reset_resources()
  local plan = P.plan(spec(), { resolution = 1 })
  H.check(plan.final:body() == ordinary:body(), name .. ": the grown page differs from the page")
  local lines, cells = 0, 0
  for _, part in ipairs(plan.parts) do
    if part.kind == "pattern_line" then lines = lines + 1 elseif part.kind == "pattern" then cells = cells + 1 end
  end
  H.check(cells == ordinary.pattern.cells and lines == cells, name .. ": parts per cell")
  local stages = P.stages(plan, 4)
  H.check(#stages == 4 and stages[4] == 1, name .. ": stages")
  local early = P.render(plan, 0.25)
  H.check(early and #early:body() < #plan.final:body(), name .. ": an early frame paints everything")
end

H.done("pattern")
