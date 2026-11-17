-- Large leaves: rounded acanthus lobes, simple small leaves, and the
-- blade-shaped corridor a placed leaf keeps clear.
package.path = "./lua/?.lua;" .. package.path
local H = dofile("tests/helper.lua")
local Rng = require("flora.rng")
local Space = require("flora.space")
local L = require("flora.leaf")

-- Acanthus lobes have rounded shoulders: just either side of each crest
-- the margin is nearly level, where a spiky lobe would still be climbing
-- or falling steeply. Slopes are in crest heights per lobe length.
do
  local teeth, depth = 4, 0.6
  local lobe = 1 / teeth
  for k = 2, 3 do
    local lo, hi = k * lobe, (k + 1) * lobe
    local best, at = -1, lo
    for i = 0, 400 do
      local t = lo + (hi - lo) * i / 400
      local m = L.margin("acanthus", t, teeth, depth)
      if m > best then best, at = m, t end
    end
    local h = 0.02 * lobe
    for _, side in ipairs({ -1, 1 }) do
      local slope = (best - L.margin("acanthus", at + side * h, teeth, depth)) / depth / 0.02
      H.check(slope < 1, string.format("lobe %d is pointed: slope %.2f %s its crest", k, slope,
        side < 0 and "before" or "after"))
    end
    -- And the lobe is still a lobe: its recess cuts most of the depth.
    local low = math.huge
    for i = 0, 400 do low = math.min(low, L.margin("acanthus", lo + (hi - lo) * i / 400, teeth, depth)) end
    H.check(best - low > 0.8 * depth, string.format("lobe %d only %.2f deep", k, best - low))
  end
end

-- Small leaves stay smooth-edged. Large ones follow the reference's kinds:
-- feathers most often, then lance and acanthus leaves, never the serrate
-- blade it does not have; lobed leaves mix deep and light lobing.
do
  local deep, light, kinds = 0, 0, {}
  local lobes = { acanthus = { 3, 6 }, feather = { 5, 8 } }
  for seed = 1, 300 do
    local small = L.options(Rng.new(seed), 40, 1.2)
    H.check(small.margin == "entire", string.format("seed %d: small leaf has a %s margin", seed, small.margin))
    local o = L.options(Rng.new(seed), 110, 1.2)
    kinds[o.margin] = (kinds[o.margin] or 0) + 1
    local range = lobes[o.margin]
    if range then
      if o.depth >= 0.5 then deep = deep + 1 else light = light + 1 end
      H.check(o.teeth >= range[1] and o.teeth <= range[2],
        string.format("seed %d: %s with %d lobes a side", seed, o.margin, o.teeth))
    end
  end
  H.check(deep > 60 and light > 60, string.format("lobing not mixed: %d deep, %d light", deep, light))
  H.check(not kinds.serrate, "a serrate leaf, which the reference does not have")
  H.check((kinds.feather or 0) > (kinds.entire or 0) and (kinds.feather or 0) > (kinds.acanthus or 0),
    "feathers are not the most common large leaf")
end

-- Feathers: lobed on the outer side of their arch, lightly or not at all on
-- the inner side, with every lobe leaning toward the tip, and an outline
-- that never crosses itself however far the lobes sweep.
local function crosses(poly)
  local function orient(a, b, c) return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]) end
  local n = #poly
  for i = 1, n do
    local a, b = poly[i], poly[i % n + 1]
    for j = i + 2, n do
      if not (i == 1 and j == n) then
        local c, d = poly[j], poly[j % n + 1]
        if orient(a, b, c) * orient(a, b, d) < 0 and orient(c, d, a) * orient(c, d, b) < 0 then return i, j end
      end
    end
  end
end

do
  local found = 0
  for seed = 1, 400 do
    local r = Rng.new(seed)
    local ang = seed % 2 == 0 and 1.2 or 1.9
    local o = L.options(r, 110, ang)
    if o.margin == "feather" then
      found = found + 1
      local out, spine, left, right = L.outline(r, o)
      local i, j = crosses(out)
      H.check(not i, string.format("seed %d: feather outline crosses itself (edges %d, %d)", seed, i or 0, j or 0))
      -- How much each side's edge rises and falls against the smooth blade
      -- (its total variation, in blade half-widths), and how far its points
      -- lean forward along the midrib.
      local function stray(side)
        local wobble, lean, prev = 0, 0, nil
        for k = 2, #spine - 1 do
          local tx, ty = spine[k + 1][1] - spine[k - 1][1], spine[k + 1][2] - spine[k - 1][2]
          local tl = math.sqrt(tx * tx + ty * ty)
          local dx, dy = side[k][1] - spine[k][1], side[k][2] - spine[k][2]
          local w = o.width * L.profile(o, (k - 1) / (#spine - 1))
          local rel = math.sqrt(dx * dx + dy * dy) / math.max(w, 1e-9)
          if prev then wobble = wobble + math.abs(rel - prev) end
          prev = rel
          lean = lean + (dx * tx + dy * ty) / tl
        end
        return wobble, lean
      end
      local outer, inner = o.sides == "right" and right or left, o.sides == "right" and left or right
      local od, ol = stray(outer)
      local id = stray(inner)
      -- The inner side is lobed to at most 0.45 of the outer depth; jitter in
      -- the blade adds wobble to both.
      H.check(od > 1.6 * id, string.format("seed %d: outer side wobbles %.2f, inner %.2f", seed, od, id))
      H.check(ol > 0, string.format("seed %d: outer lobes lean back toward the base (%.1f)", seed, ol))
    end
  end
  H.check(found > 100, "too few feathers to test: " .. found)
end

-- A corridor with per-point radii keeps each point's own width: the wide
-- middle is reserved, the narrow stalk leaves its neighbours free.
do
  local g = Space.new(200, 200, 1)
  g:open(0, 0, 200, 200)
  local pts = { { 50, 20 }, { 50, 40 }, { 50, 60 }, { 50, 80 }, { 50, 100 } }
  g:reserve_line(pts, { 2, 6, 14, 6, 2 })
  H.check(not g:free(62, 60), "wide middle of the corridor left free")
  H.check(g:free(58, 20), "narrow stalk reserved at the middle's width")
  H.check(not g:free(50, 40), "corridor skipped a point")
end

-- Leaf joints (Grow.joint, L.attach). A leaf at the stem's silhouette
-- starts just off the stem's edge on its own side; one in front of or
-- behind the stem starts at its centre; all three occur. The stem drawn
-- over a leaf behind it spans the whole blade, so it never stops short
-- inside it.
do
  local Grow = require("flora.grow")
  local stem = { pts = {}, t = 0.5, width = function() return 2.4 end }
  for i = 0, 60 do stem.pts[#stem.pts + 1] = { 100, i * 5 } end
  local p = { 100, 150 }
  local seen = { front = 0, side = 0, back = 0 }
  for seed = 1, 120 do
    local side = seed % 2 == 0 and 1 or -1
    local ang = math.pi / 2 - side * 0.9
    local at, base = Grow.joint(Rng.new(seed), p, ang, 70, stem)
    if math.abs(at.f) < L.FRONT then
      seen.side = seen.side + 1
      local off = base[1] - p[1]
      H.check(math.abs(math.abs(off) - (1.2 + 3)) < 0.01 and off * side > 0,
        string.format("seed %d: silhouette leaf heading %s starts at x offset %.2f", seed, side > 0 and "right" or "left", off))
    else
      seen[at.f > 0 and "front" or "back"] = seen[at.f > 0 and "front" or "back"] + 1
      H.check(base == p, string.format("seed %d: leaf in front or behind moved off the stem", seed))
    end
    local lo, hi = math.huge, -math.huge
    for _, q in ipairs(at.seg) do lo, hi = math.min(lo, q[2]), math.max(hi, q[2]) end
    H.check(lo <= p[2] - 70 and hi >= p[2] + 70, string.format("seed %d: stem overlay spans only %.0f..%.0f", seed, lo, hi))
  end
  for k, n in pairs(seen) do H.check(n >= 20, string.format("only %d of 120 joints %s", n, k)) end
end

-- L.attach paints only inside the blade, except a silhouette leaf's stalk,
-- which stays on the line from the stem to the blade.
do
  local Paint = require("flora.paint")
  local G = require("flora.geom")
  for seed = 1, 30 do
    local f = ({ 0.8, 0, -0.8 })[seed % 3 + 1]
    local p, base = { 100, 100 }, { 100, 100 }
    if math.abs(f) < L.FRONT then base = { 104.2, 100 } end
    local seg = {}
    for i = -20, 20 do seg[#seg + 1] = { 100, 100 + i * 4 } end
    local function run(attach)
      local pt = Paint.new({ backend = "pdf" })
      local pts = {}
      pt.probe = function(x, y, r) pts[#pts + 1] = { x, y, r } end
      local r = Rng.new(seed)
      local o = L.options(r, 60, 0.4)
      o.attach = attach
      L.leaf(pt, r, base[1], base[2], 0.4, o)
      return pts
    end
    local plain = run(nil)
    local joined = run({ f = f, p = p, seg = seg, w = 2.4 })
    -- Clipped paint is not probed, but the clip path (the blade's own
    -- outline, painted already) is.
    local known = {}
    for _, q in ipairs(plain) do known[string.format("%.2f,%.2f", q[1], q[2])] = true end
    local a, b = p, G.polar(base, 0.4, 3)
    local function off_stalk(q)
      local dx, dy = b[1] - a[1], b[2] - a[2]
      local t = G.clamp(((q[1] - a[1]) * dx + (q[2] - a[2]) * dy) / (dx * dx + dy * dy), 0, 1)
      return G.dist(q, { a[1] + t * dx, a[2] + t * dy })
    end
    local worst = ""
    for i = #plain + 1, #joined do
      local q = joined[i]
      if not known[string.format("%.2f,%.2f", q[1], q[2])] and off_stalk(q) > 1.5 then
        worst = string.format("(%.1f, %.1f)", q[1], q[2])
      end
    end
    H.check(worst == "", string.format("seed %d (f %.1f): joint paints off the blade and stalk at %s", seed, f, worst))
  end
end

-- The halo follows the blade's outline except near its base: no halo point
-- lies within 0.18 of the leaf's length of the base (it would cut the stem
-- at the joint), and the halo still covers most of the outline.
do
  local G = require("flora.geom")
  for seed = 1, 30 do
    local r = Rng.new(seed)
    local o = L.options(r, 70, 0.6)
    local poly, spine = L.outline(r, o)
    local base = spine[1]
    local covered, near = 0, nil
    for _, run in ipairs(L.halo_runs(poly, base, o.len)) do
      for _, q in ipairs(run) do
        covered = covered + 1
        if G.dist(q, base) <= o.len * 0.18 then near = q end
      end
    end
    H.check(not near, string.format("seed %d: halo reaches the base", seed))
    H.check(covered >= #poly * 0.7, string.format("seed %d: halo covers %d of %d outline points", seed, covered, #poly))
  end
end

H.done("leaf")
