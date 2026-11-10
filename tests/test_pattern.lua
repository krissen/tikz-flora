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

-- Patterns built on a tiling meet edge to edge: inside the box, every
-- tile edge's midpoint is the midpoint of exactly one other tile's edge,
-- so stars drawn from those midpoints join up.
for _, p in ipairs(Patterns.list) do
  local cells = p.cells({ x0 = 0, y0 = 0, x1 = 200, y1 = 200, size = p.scale, rng = Rng.new(1) })
  if cells[1].tile then
    local count, keys = {}, {}
    for _, c in ipairs(cells) do
      local T = c.tile
      for i = 1, #T do
        local a, b = T[i], T[i % #T + 1]
        local mx, my = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
        local k = string.format("%.1f,%.1f", mx, my)
        count[k] = (count[k] or 0) + 1
        if mx > 40 and mx < 160 and my > 40 and my < 160 then keys[#keys + 1] = k end
      end
    end
    local odd = 0
    for _, k in ipairs(keys) do if count[k] ~= 2 then odd = odd + 1 end end
    H.check(#keys > 20 and odd == 0, p.name .. ": " .. odd .. " tile edges inside the box are not shared by two tiles")
  end
end

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

-- No cell's paint comes near the text, measured along its whole outline,
-- for every pattern, scale, layout, edge and outer mode. Outlines are
-- sampled every half point, so an edge across a line of text is caught
-- even when all its corners clear it.
local function samples(c)
  local out = {}
  if c.circle then
    for k = 0, 127 do
      local a = 2 * math.pi * k / 128
      out[#out + 1] = { c.circle[1] + c.circle[3] * math.cos(a), c.circle[2] + c.circle[3] * math.sin(a) }
    end
    return out
  end
  local P = c.verts
  for i = 1, #P do
    local a, b = P[i], P[i % #P + 1]
    local n = math.max(1, math.ceil(math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) / 0.5))
    for k = 0, n - 1 do out[#out + 1] = { a[1] + (b[1] - a[1]) * k / n, a[2] + (b[2] - a[2]) * k / n } end
  end
  return out
end
local function covers(c, x, y)
  if c.circle then return (x - c.circle[1]) ^ 2 + (y - c.circle[2]) ^ 2 <= c.circle[3] ^ 2 end
  local inside, P, j = false, c.verts, #c.verts
  for i = 1, #P do
    local a, b = P[i], P[j]
    if (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then inside = not inside end
    j = i
  end
  return inside
end
local function rdist(x, y, r)
  local dx, dy = math.max(r[1] - x, 0, x - r[3]), math.max(r[2] - y, 0, y - r[4])
  return math.sqrt(dx * dx + dy * dy)
end
local lines = {}
for k = 0, 9 do lines[#lines + 1] = { x0 = 120, x1 = 330 - (k % 3) * 40, y0 = 210 - k * 17, y1 = 220 - k * 17 } end
local bad = 0
for _, p in ipairs(Patterns.list) do
  for _, scale in ipairs({ 1, 2.5, 4 }) do
    for _, layout in ipairs({ "right", "surround" }) do
      for _, edge in ipairs({ "cell", "dissolve", "fade", "border" }) do
        for _, outer in ipairs({ "bleed", "margin" }) do
          local pt = page({ pattern = { [p.name] = 1 }, pattern_scale = scale, layout = layout, pattern_edge = edge,
            pattern_outer = outer, mix = { density = 2 }, lines = layout == "surround" and lines or nil,
            text = layout == "right" and { x0 = 30, y0 = 40, x1 = 240, y1 = 230 } or { x0 = 120, y0 = 40, x1 = 330, y1 = 230 } })
          local info = pt.pattern
          local where = string.format("%s scale %s %s %s %s", p.name, scale, layout, edge, outer)
          for _, k in ipairs(info.kept) do
            local c = k.cell
            local reach = info.reach + (c.pad or 0)
            for _, q in ipairs(samples(c)) do
              for _, r in ipairs(info.avoid) do
                if rdist(q[1], q[2], r) - reach < info.gap - 1e-6 then bad = bad + 1; if bad < 4 then
                  io.stderr:write("near text: " .. where .. "\n") end end
              end
              if outer == "margin" and (q[1] - reach < 4 - 1e-6 or q[2] - reach < 4 - 1e-6
                  or q[1] + reach > 360 - 4 + 1e-6 or q[2] + reach > 270 - 4 + 1e-6) then
                bad = bad + 1; if bad < 4 then io.stderr:write("past the margin: " .. where .. "\n") end
              end
            end
            for _, r in ipairs(info.avoid) do
              for _, q in ipairs({ { r[1], r[2] }, { r[3], r[2] }, { r[3], r[4] }, { r[1], r[4] } }) do
                if covers(c, q[1], q[2]) then bad = bad + 1 end
              end
            end
          end
        end
      end
    end
  end
end
H.check(bad == 0, bad .. " cell outline samples too near the text or past the margin")

-- The reported case: a large asanoha triangle whose corners clear a line
-- of text while two of its edges cross it.
do
  local c = { verts = { { 156, 90 }, { 260, 90 }, { 208, 180 } } }
  H.check(require("flora.pattern").clearance(c, { 120, 130, 330, 140 }) == 0, "an edge across the text has clearance")
end

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

-- A "watch it grow" frame (spec.grow, as tools/grow-frame.sh renders)
-- paints more the later it is, nothing at 0, and the whole page at 1.
do
  local sizes = {}
  for _, g in ipairs({ 0, 0.3, 0.6, 0.9, 1 }) do sizes[#sizes + 1] = #page({ grow = g }):body() end
  H.check(sizes[1] < sizes[2] and sizes[2] < sizes[3] and sizes[3] < sizes[4], "spec.grow frames do not grow")
  H.check(page({ grow = 1 }):body() == page():body(), "spec.grow = 1 differs from the page")
  H.check(#page({ grow = 0 }).out <= 4, "spec.grow = 0 painted cells")
end

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
