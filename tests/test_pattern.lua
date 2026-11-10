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
s = Settings.parse("hero=rose, edge=guilloche")
H.check(s.hero == "rose" and s.edge == "guilloche" and Settings.to_spec(s, {}).pattern_hero == "rose", "hero and guilloche parse")
for _, bad in ipairs({ "pattern=paisley", "pattern={asanoha=11}", "edge=soft", "outer=wrap", "scale=9", "hero=sun" }) do
  H.check(not pcall(Settings.parse, bad), bad .. " was accepted")
end

-- A later pattern setting replaces the earlier one; none returns to flora.
do
  local a = Settings.parse("pattern=asanoha")
  local b = Settings.merge(a, Settings.parse("pattern=stars_8_4"))
  H.check(b.pattern.stars_8_4 == 1 and b.pattern.asanoha == nil, "pattern settings merged instead of replacing")
  local c = Settings.merge(a, Settings.parse("pattern=none"))
  H.check(next(c.pattern) == nil, "pattern=none kept a pattern")
  local m = Settings.merge(Settings.parse("mix={gyps=2}"), Settings.parse("mix={cyme=0}"))
  H.check(m.mix.gyps == 2 and m.mix.cyme == 0, "mix stopped merging")
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

-- Penrose rhombs have the cell size for their edge, at every size.
do
  local pen = Patterns.by_name.penrose_rhombs
  for _, size in ipairs({ 16, 20, 22, 24 }) do
    local cells = pen.cells({ x0 = 0, y0 = 0, x1 = 360, y1 = 270, size = size, rng = Rng.new(2) })
    local a, b = cells[1].tile[1], cells[1].tile[2]
    local edge = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
    H.check(math.abs(edge - size) < 1e-6, string.format("penrose edge %.2f for size %d", edge, size))
  end
end

-- Weights: a name overrides its groups; a group weighs its members.
local stars, asa = Patterns.by_name.stars_8_4, Patterns.by_name.asanoha
H.check(Patterns.weight({ japanese = 2 }, asa) == 2 and Patterns.weight({ japanese = 2 }, stars) == 0, "group weight")
H.check(Patterns.weight({ japanese = 2, asanoha = 0 }, asa) == 0, "a name overrides its group")
H.check(Patterns.pick(Rng.new(3), { girih = 1 }) == stars, "group pick")
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
      for _, edge in ipairs({ "cell", "dissolve", "fade", "border", "guilloche" }) do
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

-- A border on a whole-page layout keeps the field off the whole framed
-- text block, even where a short page leaves it without lines.
do
  local short = { { x0 = 120, x1 = 330, y0 = 210, y1 = 220 }, { x0 = 120, x1 = 300, y0 = 193, y1 = 203 } }
  local pt = page({ layout = "surround", lines = short, pattern_edge = "border", mix = { density = 3 } })
  local Pat = require("flora.pattern")
  local frame = { 120 - 6, 40 - 6, 330 + 6, 230 + 6 }
  local inside = 0
  for _, k in ipairs(pt.pattern.kept) do if Pat.clearance(k.cell, frame) == 0 then inside = inside + 1 end end
  H.check(inside == 0, inside .. " cells inside or across the border frame")
end

-- Margin cells stay whole below the header clip (header=body) and a top
-- inset. Paint inside a clip is not probed, so the kept cells are measured.
do
  local function highest(pt)
    local y = -math.huge
    for _, k in ipairs(pt.pattern.kept) do
      local c, reach = k.cell, pt.pattern.reach + (k.cell.pad or 0)
      if c.circle then y = math.max(y, c.circle[2] + c.circle[3] + reach)
      else for _, q in ipairs(c.verts) do y = math.max(y, q[2] + reach) end end
    end
    return y
  end
  local pt = page({ pattern_outer = "margin", header = "body", body_top = 200 })
  H.check(#pt.pattern.kept > 0 and highest(pt) <= 200 + 1e-6, "margin-mode cells reach above the header clip")
  pt = page({ pattern_outer = "margin", tune = { gesture = { top_inset = 40 } } })
  H.check(#pt.pattern.kept > 0 and highest(pt) <= 270 - 40 + 1e-6, "margin-mode cells reach into the top inset")
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
for _, entry in ipairs(Patterns.list) do
  local name = entry.name
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

-- Celtic knotwork: every crossing has exactly one over strand, and a
-- strand alternates over and under along its whole length, for the weave
-- and for panels of mirrors; every strand closes; a cell's curves stay
-- inside its square and pad.
do
  local engine = Patterns.by_name.celtic_knot.engine
  local function check(label, inner, nx, ny)
    local loops = engine.trace(nx, ny, inner)
    local at = {}
    local crossings = 0
    for _, pts in ipairs(loops) do
      local last, first, n = nil, nil, 0
      for _, p in ipairs(pts) do
        local k = p.X .. "," .. p.Y
        at[k] = at[k] or { passes = 0, over = 0, cross = p.cross }
        at[k].passes = at[k].passes + 1
        if p.over then at[k].over = at[k].over + 1 end
        if p.cross then
          n = n + 1
          if last ~= nil then H.check(p.over ~= last, label .. ": two over or two under in a row at " .. k) end
          last, first = p.over, first == nil and p.over or first
        end
      end
      if n > 0 then H.check(n % 2 == 0 and last ~= first, label .. ": a strand does not close over/under") end
    end
    for k, v in pairs(at) do
      if v.cross then
        crossings = crossings + 1
        H.check(v.passes == 2 and v.over == 1, label .. ": crossing " .. k .. " has " .. v.over .. " over of " .. v.passes)
      end
    end
    H.check(crossings > 20, label .. ": too few crossings (" .. crossings .. ")")
  end
  check("weave", nil, 12, 9)
  for seed = 1, 6 do
    local rng, memo = Rng.new(seed), {}
    check("panels " .. seed, function(X, Y)
      local k = X * 1000 + Y
      if memo[k] == nil then memo[k] = rng:next() < 0.25 end
      return memo[k]
    end, 8, 8)
  end
  -- A cell's curves, as the field builds them, stay inside its square.
  for _, name in ipairs({ "celtic_knot", "celtic_panels" }) do
    local p = Patterns.by_name[name]
    for _, size in ipairs({ p.scale, p.scale * 2.5 }) do
      local cells = p.cells({ x0 = 0, y0 = 0, x1 = 200, y1 = 160, size = size, rng = Rng.new(2) })
      local reach = size * 0.1
      local bad = 0
      for _, c in ipairs(cells) do
        local lo, hi = c.x - size / 4 - reach, c.x + size / 4 + reach
        local lo2, hi2 = c.y - size / 4 - reach, c.y + size / 4 + reach
        for _, piece in ipairs(c.lines) do
          for _, cmd in ipairs(piece) do
            for i = 2, #cmd, 2 do
              if cmd[i] < lo or cmd[i] > hi or cmd[i + 1] < lo2 or cmd[i + 1] > hi2 then bad = bad + 1 end
            end
          end
        end
      end
      H.check(bad == 0, name .. ": " .. bad .. " curve points outside their cell's square and pad at size " .. size)
    end
  end
end

-- Emblem patterns are opt-in: only their own name or the group symbol
-- picks them, never an ordinary group.
do
  local emblems = { hexagram_lattice = true, khatam = true, greek_crosses = true }
  local function picks(weights)
    local got = {}
    for seed = 1, 60 do
      local p = Patterns.pick(Rng.new(seed), weights)
      got[p and p.name or "none"] = true
    end
    return got
  end
  for name in pairs(emblems) do H.check(Patterns.by_name[name] and Patterns.by_name[name].opt_in, name .. ": not opt-in") end
  for _, group in ipairs({ "square", "star", "triangular", "lattice", "tiling", "cross" }) do
    for name in pairs(picks({ [group] = 1 })) do
      H.check(not emblems[name], "pattern={" .. group .. "=1} picked the emblem " .. name)
    end
  end
  local only = picks({ symbol = 1 })
  local n = 0
  for name in pairs(only) do n = n + 1; H.check(emblems[name], "pattern={symbol=1} picked " .. name) end
  H.check(n == 3, "pattern={symbol=1} did not reach all three emblems (" .. n .. ")")
  H.check(picks({ khatam = 1 }).khatam and next(picks({ khatam = 1 }), "khatam") == nil, "pattern=khatam did not pick only khatam")
  H.check(Patterns.weight({ symbol = 2, khatam = 0 }, Patterns.by_name.khatam) == 0, "a name overrides symbol")
  H.check(Patterns.weight({ square = 3, star = 3 }, Patterns.by_name.khatam) == 0, "an ordinary group weighed an emblem")
  H.check(Patterns.weight({ symbol = 2 }, Patterns.by_name.asanoha) == 0, "symbol weighed an ordinary pattern")
  for _, e in ipairs(require("flora.catalog").build().patterns) do
    H.check(e.opt_in == (emblems[e.name] or false), e.name .. ": catalog opt_in")
  end
end

-- Compass growth: a circle pattern's construction lines are drawn as a
-- compass turns about each circle's centre, then its bands in a second turn.
-- `wedges` finds the wedge clips in a frame's body: the compass point,
-- how far it has turned (a fraction of a turn) and the line that follows.
local function wedges(body)
  local out, lines = {}, {}
  for l in (body .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  for i, l in ipairs(lines) do
    local path = l:match("^q (.-) h W n$")
    if path and path:find(" l ", 1, true) and path:find(" c", 1, true) then
      local nums = {}
      for v in path:gmatch("%-?[%d%.]+") do nums[#nums + 1] = tonumber(v) end
      local cx, cy = nums[1], nums[2]
      local turn, prev = 0, math.atan(nums[4] - cy, nums[3] - cx)
      for j = 5, #nums, 6 do
        local a = math.atan(nums[j + 5] - cy, nums[j + 4] - cx)
        local d = (a - prev + math.pi) % (2 * math.pi) - math.pi
        turn, prev = turn + math.abs(d), a
      end
      out[#out + 1] = { x = cx, y = cy, f = turn / (2 * math.pi), next = lines[i + 1] }
    end
  end
  return out
end

-- The wedge opens through the fraction of a turn it is given, either way.
do
  local s = {}
  for _, c in ipairs(P.wedge(10, 20, 5, 0.3, 0.6, -1)) do
    for k = 2, #c do s[#s + 1] = string.format("%.4f", c[k]) end
    if c[1] ~= "z" then s[#s + 1] = c[1] end
  end
  local w = wedges("q " .. table.concat(s, " ") .. " h W n")
  H.check(#w == 1 and math.abs(w[1].f - 0.6) < 1e-3 and w[1].x == 10 and w[1].y == 20, "wedge opens the wrong angle")
end

for _, name in ipairs({ "overlapping_circles", "shippo", "seigaiha" }) do
  local function spec(extra)
    local s = { width = 360, height = 270, text = { x0 = 120, y0 = 40, x1 = 330, y1 = 230 }, seed = 7,
      layout = "left", pattern = { [name] = 1 } }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
  end
  for _, c in ipairs(Patterns.by_name[name].cells({ x0 = 0, y0 = 0, x1 = 60, y1 = 60, size = 16, rng = Rng.new(1) })) do
    H.check(c.sweep and c.sweep[1] == c.circle[1] and c.sweep[2] == c.circle[2], name .. ": a circle without its compass point")
  end

  -- Progression: every cell's lines and bands are swept, the bands
  -- after the lines.
  Paint.reset_resources()
  local plan = P.plan(spec(), { resolution = 1 })
  local swept_parts, forms, swept = {}, {}, { pattern_line = 0, pattern = 0 }
  for i, part in ipairs(plan.parts) do
    if swept[part.kind] then
      swept[part.kind] = swept[part.kind] + (part.sweep and 1 or 0)
      if part.form then swept_parts[#swept_parts + 1] = part; forms[part.form] = part end
    end
    if part.kind == "pattern_line" then
      local cell = plan.parts[i + 1]
      H.check(cell.kind == "pattern" and cell.birth >= part.birth + part.duration - 1e-12,
        name .. ": a cell is painted before its compass turn is done")
    end
  end
  local cells = plan.final.pattern.cells
  H.check(cells > 20 and swept.pattern_line == cells and swept.pattern == cells, name .. ": lines or bands not swept")
  -- Every swept part is done by 0.97, as every cell was before it swept.
  local late = 0
  for _, part in ipairs(plan.parts) do
    if part.sweep and part.birth + part.duration > 0.97 + 1e-9 then late = late + 1 end
  end
  H.check(late == 0, name .. ": " .. late .. " swept parts end after 0.97")

  -- How far each swept part is drawn in a frame: 0 before, the wedge's
  -- turn while it opens, 1 after.
  local function drawn(body)
    local out = {}
    for _, part in ipairs(swept_parts) do
      out[part] = body:find("/" .. part.form .. " Do", 1, true) and 1 or 0
    end
    for _, w in ipairs(wedges(body)) do
      local form = w.next and w.next:match("^/(%S+) Do$")
      if forms[form] then out[forms[form]] = w.f end
    end
    return out
  end
  local before, partial = {}, {}
  for _, t in ipairs({ 0.05, 0.15, 0.25, 0.35, 0.5, 0.65, 0.75, 0.9, 0.97 }) do
    local now = drawn(P.render(plan, t):body())
    for part, f in pairs(now) do
      H.check(f + 1e-3 >= (before[part] or 0), string.format("%s: a compass turned back at t = %.2f", name, t))
      if t == 0.5 and f > 0.02 and f < 0.98 then partial[part.kind] = true end
    end
    before = now
  end
  H.check(partial.pattern_line, name .. ": a half-grown frame holds no partial construction arc")
  H.check(partial.pattern, name .. ": a half-grown frame holds no partial band")

  -- spec.grow frames: partial arcs while growing, turning only forward,
  -- and the page grows. A cell's compass first turns once for its lines
  -- (the thin construction stroke follows the wedge), then once for its
  -- bands: its progress is the line's turn, or 1 and the band's.
  local last, sizes, seen = {}, {}, {}
  for _, g in ipairs({ 0.2, 0.4, 0.5, 0.6, 0.8 }) do
    Paint.reset_resources()
    local body = Compose.page(spec({ grow = g })):body()
    sizes[#sizes + 1] = #body
    local now = {}
    for _, w in ipairs(wedges(body)) do
      local key = string.format("%.2f,%.2f", w.x, w.y)
      local band = not w.next:find(" 0.40 w ", 1, true)
      local p = (band and 1 or 0) + w.f
      H.check(not now[key] or now[key] < 1 and p > 1, name .. ": a spec.grow cell swept twice at once")
      now[key] = p
      H.check(w.f > 0 and w.f < 1, name .. ": a spec.grow wedge outside the turn")
      H.check(not last[key] or p + 1e-3 >= last[key], name .. ": a spec.grow compass turned back")
      seen[band and "band" or "line"] = true
    end
    last = now
  end
  H.check(seen.line and seen.band, name .. ": spec.grow drew no partial line or band")
  for i = 2, #sizes do H.check(sizes[i] > sizes[i - 1], name .. ": spec.grow frames do not grow") end
  -- From 0.97 on, a spec.grow frame is the finished page: no compass is
  -- still turning, so the last frames of a sequence do not jump.
  Paint.reset_resources()
  local finished = Compose.page(spec()):body()
  for _, g in ipairs({ 0.97, 0.999 }) do
    Paint.reset_resources()
    local body = Compose.page(spec({ grow = g })):body()
    H.check(#wedges(body) == 0 and body == finished, string.format("%s: the spec.grow frame at %s is not the page", name, g))
  end
end

-- The hero (pattern_hero.lua). Every point a motif paints, Bezier control
-- points and stroke widths included, lies inside its disc; a curve stays
-- inside its control points, so this bounds the paint itself.
local Pat, Hero = require("flora.pattern"), require("flora.pattern_hero")
local function reach_of(cmds, width, f)
  for _, c in ipairs(cmds) do
    if type(c[1]) == "table" then reach_of(c, width, f)
    elseif c[1] == "o" then f(c[2], c[3], c[4] + width / 2)
    elseif c[1] ~= "z" then for i = 2, #c, 2 do f(c[i], c[i + 1], width / 2) end
    end
  end
end
local function hero_extent(d)
  local far = 0
  local probe = Paint.new({ backend = "pdf" })
  local function at(x, y, r) far = math.max(far, math.sqrt((x - d[1]) ^ 2 + (y - d[2]) ^ 2) + r) end
  probe.fill = function(_, cmds) reach_of(cmds, 0, at) end
  probe.stroke = function(_, cmds, _, w) reach_of(cmds, w, at) end
  local ink = { band = { 0, 0, 0 }, core = { 1, 1, 1 }, accent = { 1, 1, 0 }, line = { .5, .5, .5 }, fill = { { 1, 0, 0 }, { 0, 0, 1 } }, width = 1.5 }
  local rings = Hero.rings(d, ink)
  local last = 0
  for _, ring in ipairs(rings) do
    far = 0; ring.construct(probe); ring.paint(probe)
    H.check(far <= ring.r + 1e-6, d.name .. ": a ring paints beyond its radius")
    H.check(ring.r >= last - 1e-6, d.name .. ": rings do not run outward")
    last = ring.r
  end
  return last, #rings
end
for _, name in ipairs({ "rosette", "phyllotaxis", "rose", "guilloche" }) do
  for _, R in ipairs({ 24, 60, 135 }) do
    local outer = hero_extent({ 100, 100, R, name = name })
    H.check(outer <= R + 1e-6, name .. " paints beyond its disc")
  end
end

-- No cell enters the hero's disc, and the disc keeps the gap from the
-- text, for every hero on every pattern (opt-in ones by name), layout and
-- edge; a hero sits on the top corner of the field's side.
do
  local bad, placed = 0, 0
  for _, entry in ipairs(Patterns.list) do
    local pname = entry.name
    for _, name in ipairs({ "rosette", "phyllotaxis", "rose", "guilloche" }) do
      for _, layout in ipairs({ "left", "right", "surround", "split" }) do
        for _, edge in ipairs({ "dissolve", "cell", "guilloche" }) do
          local right = layout == "right" or layout == "split"
          local pt = page({ pattern = { [pname] = 1 }, pattern_hero = name, layout = layout, pattern_edge = edge,
            page = 1, mix = { density = 3 }, lines = layout == "surround" and lines or nil,
            text = right and { x0 = 30, y0 = 40, x1 = 240, y1 = 230 } or { x0 = 120, y0 = 40, x1 = 330, y1 = 230 } })
          local info, d = pt.pattern, pt.pattern.hero
          local where = string.format("%s %s %s %s", pname, name, layout, edge)
          if not d then bad = bad + 1; io.stderr:write("no hero: " .. where .. "\n") else
            placed = placed + 1
            H.check(d[2] == 270 and d[1] == ((layout == "left") and 0 or 360), where .. ": hero off its corner")
            for _, r in ipairs(info.avoid) do
              if rdist(d[1], d[2], r) - d[3] < info.gap - 1e-6 then bad = bad + 1; io.stderr:write("hero near text: " .. where .. "\n") end
            end
            for _, k in ipairs(info.kept) do
              local c = k.cell
              local reach = info.reach + (c.pad or 0)
              if covers(c, d[1], d[2]) then bad = bad + 1 end
              for _, q in ipairs(samples(c)) do
                if math.sqrt((q[1] - d[1]) ^ 2 + (q[2] - d[2]) ^ 2) - d[3] - reach < 6 - 1e-6 then
                  bad = bad + 1; if bad < 4 then io.stderr:write("in the hero: " .. where .. "\n") end
                end
              end
            end
          end
        end
      end
    end
  end
  H.check(bad == 0 and placed == 48 * #Patterns.list, bad .. " hero placements or cells too near the hero or text")
end

-- A corner with no room for a hero gets none, and the page is as without.
do
  local cramped = { pattern_hero = "rose", text = { x0 = 20, y0 = 40, x1 = 330, y1 = 260 } }
  H.check(page(cramped).pattern.hero == nil, "a hero squeezed into a cramped corner")
  cramped.pattern_hero = nil
  local a = page(cramped):body()
  cramped.pattern_hero = "rose"
  H.check(page(cramped):body() == a, "a page without room for its hero differs from one without")
end

-- A page without a hero, or hero=none, is the page as it was; a hero
-- changes it and still keeps its paint off the text.
do
  local plain = page():body()
  H.check(page({ pattern_hero = "none" }):body() == plain, "hero=none changed the page")
  local pt, seen = page({ pattern_hero = "rosette" })
  H.check(pt:body() ~= plain and pt.pattern.hero, "a hero left the page unchanged")
  local ok = true
  for _, q in ipairs(seen) do
    if q[1] + q[3] > sp.text.x0 and q[2] + q[3] > sp.text.y0 and q[2] - q[3] < sp.text.y1 and q[1] - q[3] < sp.text.x1 then ok = false end
  end
  H.check(ok, "a hero page painted on the text")
end

-- A hero grows: its rings as parts from the centre out, the last frame the
-- page, its rings born early and done by 0.6, beside cells swept by a
-- compass too; spec.grow
-- frames grow monotonically and end at the page.
for _, name in ipairs({ "rosette", "phyllotaxis", "rose", "guilloche" }) do
  for _, case in ipairs({ { "stars_8_4", "dissolve" }, { "overlapping_circles", "guilloche" }, { "celtic_knot", "dissolve" } }) do
    local pname, edge = case[1], case[2]
    local function spec()
      return { width = 360, height = 270, text = { x0 = 120, y0 = 40, x1 = 330, y1 = 230 }, seed = 7,
        layout = "left", pattern = { [pname] = 1 }, pattern_hero = name, pattern_edge = edge }
    end
    Paint.reset_resources()
    local ordinary = Compose.page(spec())
    Paint.reset_resources()
    local plan = P.plan(spec(), { resolution = 1 })
    H.check(plan.final:body() == ordinary:body(), name .. " " .. pname .. ": the grown hero page differs from the page")
    -- The hero's rings are born and done inside the growth, beside cells
    -- swept by a compass too.
    for _, part in ipairs(plan.parts) do
      if part.kind:find("^pattern_hero") then
        H.check(part.birth >= 0.02 - 1e-9 and part.birth + part.duration <= 0.6, name .. " " .. pname .. ": a hero ring outside its time")
      end
    end
    local births, cells = {}, 0
    for _, part in ipairs(plan.parts) do
      if part.kind == "pattern_hero" then births[#births + 1] = part.birth end
      if part.kind == "pattern" then cells = cells + 1 end
    end
    local _, n = hero_extent(ordinary.pattern.hero)
    H.check(#births == n and cells == ordinary.pattern.cells, name .. ": parts per ring")
    for i = 2, #births do H.check(births[i] > births[i - 1], name .. ": rings born out of order") end
    local sizes = {}
    for _, g in ipairs({ 0, 0.05, 0.2, 0.4, 0.6, 0.8, 0.95 }) do
      local s = spec(); s.grow = g
      Paint.reset_resources()
      sizes[#sizes + 1] = #Compose.page(s):body()
    end
    for i = 2, #sizes do H.check(sizes[i] > sizes[i - 1], name .. " " .. edge .. ": spec.grow frames do not grow") end
    local s = spec(); s.grow = 1
    Paint.reset_resources()
    H.check(Compose.page(s):body() == ordinary:body(), name .. ": spec.grow = 1 differs from the page")
  end
end

-- The guilloche band lies between the text and the field: every point of
-- it, strokes included, at least 2pt from the text block and 2pt short
-- of the gap the cells keep, at several block sizes and strand widths.
do
  for _, t in ipairs({ { x0 = 120, y0 = 40, x1 = 330, y1 = 230 }, { x0 = 30, y0 = 40, x1 = 240, y1 = 230 }, { x0 = 50, y0 = 50, x1 = 70, y1 = 60 } }) do
    for _, w in ipairs({ 0.6, 1.6 }) do
      local b = Hero.band(t, 9, 4, w)
      local near, far = math.huge, 0
      local function at(x, y, r)
        local d = rdist(x, y, { t.x0, t.y0, t.x1, t.y1 })
        near = math.min(near, d - r); far = math.max(far, d + r)
      end
      reach_of(b.strands[1], w, at); reach_of(b.strands[-1], w, at)
      for _, c in ipairs(b.crossings) do
        reach_of(c.piece, w, at)
        -- The clip covers the crossing: both strands, outlines included.
        H.check(c.clip >= 2 * w, string.format("a crossing's clip of %.2f is too small for strands %.1f wide", c.clip, w))
      end
      reach_of(b.dots, 0.35, at)
      reach_of(b.rules, 0.5, at)
      H.check(#b.crossings % 2 == 0 and #b.crossings >= 4, "the band's crossings do not alternate round it")
      H.check(near >= 2 and far <= 18 - 2, string.format("guilloche band from %.2f to %.2f of the text", near, far))
    end
  end
  -- No strand stroke ends where it can be seen: in the emitted stream,
  -- every stroke at a strand's width is closed, or lies inside a clip disc
  -- with both its ends, caps included, outside the disc. So no outline's
  -- round cap can fall across the other strokes of a strand at an eye.
  for _, t in ipairs({ { x0 = 120, y0 = 40, x1 = 330, y1 = 230 }, { x0 = 50, y0 = 50, x1 = 70, y1 = 60 } }) do
    for _, w in ipairs({ 1.6, 1.0 }) do
      local pb = Paint.new({ backend = "pdf" })
      local ink = { band = { 0, 0, 0.2 }, core = { 1, 1, 1 }, accent = { 1, 0.8, 0 }, line = { .5, .5, .5 },
        fill = { { 0.9, 0.1, 0.1 }, { 0.1, 0.1, 0.9 } }, width = w }
      local b = Hero.paint_band(pb, t, 9, 4, ink)
      local function nums(str) local out = {} for v in str:gmatch("%-?[%d%.]+") do out[#out + 1] = tonumber(v) end return out end
      local clip, closed, pieces, seams = nil, 0, 0, 0
      for _, line in ipairs(pb.out) do
        if line:find(" W n$") then
          local n = nums(line:match("^q (.*) W n$"))
          local cx, cy = 0, 0
          for j = 7, 25, 6 do cx, cy = cx + n[j] / 4, cy + n[j + 1] / 4 end
          clip = { cx, cy, math.sqrt((n[1] - cx) ^ 2 + (n[2] - cy) ^ 2) }
        elseif line == "Q" then clip = nil
        elseif line:find(" S Q$") then
          local width = tonumber(line:match("([%d%.]+) w "))
          local strand = math.abs(width - w * 72 / 72.27) < 0.02 or math.abs(width - 0.55 * w * 72 / 72.27) < 0.02
          if strand then
            local path = line:match(" 1 j (.*) S Q$")
            if path:find(" h$") then closed = closed + 1
            else
              local n = nums(path)
              local ends = { { n[1], n[2] }, { n[#n - 1], n[#n] } }
              local hidden = clip ~= nil
              for _, e in ipairs(ends) do
                if hidden and math.sqrt((e[1] - clip[1]) ^ 2 + (e[2] - clip[2]) ^ 2) < clip[3] + width / 2 then hidden = false end
              end
              if hidden then pieces = pieces + 1 else seams = seams + 1 end
            end
          end
        end
      end
      H.check(seams == 0, seams .. " strand strokes end in sight on the guilloche band")
      H.check(closed == 4 and pieces == #b.crossings, string.format("guilloche band: %d closed strand strokes, %d clipped pieces for %d crossings", closed, pieces, #b.crossings))
    end
  end
  -- The page paints it: a strand point 9 +- 4 out from the text's bottom.
  local _, seen2 = page({ pattern_edge = "guilloche" })
  local banded = false
  for _, q in ipairs(seen2) do
    local d = rdist(q[1], q[2], { sp.text.x0, sp.text.y0, sp.text.x1, sp.text.y1 })
    if q[2] < sp.text.y0 and d > 4.9 and d < 13.1 then banded = true end
  end
  H.check(banded, "edge=guilloche painted no band round the text")
end

H.done("pattern")
