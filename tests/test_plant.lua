local H = dofile("tests/helper.lua")
local Rng = require("flora.rng")
local G = require("flora.geom")
local Layout = require("flora.layout")
local Plant = require("flora.plant")
local Tune = require("flora.tune")

-- Heading change per pt between consecutive steps of a polyline.
local function curvatures(pts)
  local out = {}
  for i = 2, #pts - 1 do
    local a, b = G.angle(pts[i - 1], pts[i]), G.angle(pts[i], pts[i + 1])
    local d = (G.dist(pts[i - 1], pts[i]) + G.dist(pts[i], pts[i + 1])) / 2
    out[#out + 1] = math.abs(G.turn(b, a)) / math.max(d, 1e-9)
  end
  return out
end

local function dist_to(pts, q)
  local best = math.huge
  for _, p in ipairs(pts) do best = math.min(best, G.dist(p, q)) end
  return best
end

-- Pursuit: it reaches a target behind its start heading by turning, never
-- tighter than kmax, and its curvature changes by at most dk per pt.
do
  local kmax, dk = 1 / 20, 1 / 400
  local pts = G.pursue({ 0, 0 }, 0, function(q)
    if G.dist(q, { -40, 60 }) < 2 then return nil end
    return { -40, 60 }
  end, { len = 400, kmax = kmax, dk = dk, step = 1 })
  H.check(G.dist(pts[#pts], { -40, 60 }) < 3, "pursuit reaches its target")
  local ks = curvatures(pts)
  local worst, jump = 0, 0
  for i, k in ipairs(ks) do
    worst = math.max(worst, k)
    if i > 1 then jump = math.max(jump, math.abs(k - ks[i - 1])) end
  end
  H.check(worst <= kmax * 1.02, string.format("pursuit bends tighter than kmax: %.4f", worst))
  H.check(jump <= dk * 1.5, string.format("pursuit curvature jumps: %.5f", jump))
end

-- The plant: the main stem starts at the root on the foot and ends at the
-- hero; every long shoot starts on the main stem; the main stem's grown
-- part never bends tighter than its limit; stems bend around the
-- cartouche's box.
for seed = 1, 6 do
  local spec = H.page(seed)
  local _, m = Layout.region(spec)
  local mw = m.x1 - m.x0
  local R = G.clamp(mw * Tune.compose.hero, 28, 80)
  local hero = { m.x0 + mw * 0.5, spec.header_y - R * 0.55, R }
  -- The cartouche's box, placed as compose.lua places it: at the first
  -- quiet stretch, against the outer edge.
  local gest = Layout.gesture(Rng.new(seed):fork("gesture"), m, hero)
  local py = gest.quiet[1]
  local pw, ph = Layout.cartouche_size(mw)
  local box = { m.x0, py - ph / 2 - 3, m.x0 + pw + 5, py + ph / 2 + 3 }
  local strands = Layout.strands(Rng.new(seed):fork("strands"), m, hero, spec.width, gest, box)
  local main = strands[1]
  H.check(main.main, "first strand is the main stem")
  local p0 = main.pts[1]
  H.check(math.abs(p0[1] - spec.width * Tune.plant.root) < 2 and p0[2] < m.y0 + 12,
    string.format("seed %d main stem not rooted at the foot's right end: %.0f, %.0f", seed, p0[1], p0[2]))
  local tip = main.pts[#main.pts]
  H.check(G.dist(tip, hero) < hero[3] * 0.4, string.format("seed %d main stem ends %.0f pt from the hero", seed, G.dist(tip, hero)))
  local longs = 0
  for k = 2, #strands do
    if strands[k].kind == "long" then longs = longs + 1 end
  end
  H.check(longs == Tune.plant.long_shoots, string.format("seed %d grew %d long shoots", seed, longs))
  -- Long shoots climb toward the hero instead of stopping partway up, so
  -- the margin under the hero is not left to the main stem alone.
  local top = -math.huge
  for k = 2, #strands do
    if strands[k].kind == "long" then top = math.max(top, strands[k].tip[1][2]) end
  end
  H.check(hero[2] - top < hero[3] * 2.2,
    string.format("seed %d highest long shoot ends %.0f pt below the hero (radius %.0f)", seed, hero[2] - top, hero[3]))
  -- No shoot ends bare: each hands its tip to compose for a leaf or spray.
  for k = 2, #strands do
    local st = strands[k]
    H.check(st.tip and G.dist(st.tip[1], st.pts[#st.pts]) < 1e-9, string.format("seed %d shoot %d has no tip", seed, k))
  end
  for k = 2, #strands do
    H.check(dist_to(main.pts, strands[k].pts[1]) < 1.5, string.format("seed %d shoot %d does not leave the main stem", seed, k))
  end
  -- The final link to the hero is a Bezier, so only the grown part (below
  -- the hero's pull) is held to the pursuit limit.
  local grown = {}
  for _, p in ipairs(main.pts) do
    if p[2] < hero[2] - hero[3] * 2.6 then grown[#grown + 1] = p end
  end
  local worst = 0
  for _, k in ipairs(curvatures(grown)) do worst = math.max(worst, k) end
  H.check(worst <= 1.05 / Tune.plant.bend_radius, string.format("seed %d main stem bends to radius %.0f pt", seed, 1 / worst))
  for k, st in ipairs(strands) do
    for _, p in ipairs(st.pts) do
      if p[2] > box[2] and p[2] < box[4] and p[1] <= box[3] then
        H.check(false, string.format("seed %d stem %d enters the cartouche box at %.0f, %.0f", seed, k, p[1], p[2]))
        break
      end
    end
  end
end

-- Forks: a parent keeps sqrt(w^2 - c^2) beyond a fork (the pipe model) and
-- the narrowing does not reach back below the fork.
do
  local st = Plant.stem({ { 0, 0 }, { 0, 100 } }, 3, 3)
  local w = Plant.fork(st, 0.5, 1.8, 0)
  H.check(math.abs(w - 3) < 1e-9, "parent width at the fork")
  H.check(math.abs(Plant.width_at(st, 40) - 3) < 1e-9, "fork narrows the stem below it")
  H.check(math.abs(Plant.width_at(st, 70) - math.sqrt(9 - 1.8 * 1.8)) < 1e-6,
    string.format("pipe model width %.3f", Plant.width_at(st, 70)))
end

-- The density follows the reference's profile: crowded just under the hero
-- and along the foot, calmer at the bows in between, and calmest in the
-- quiet stretches. A gesture with every cluster equal (flat profile) fails.
for seed = 1, 6 do
  local spec = H.page(seed)
  local _, m = Layout.region(spec)
  local mw = m.x1 - m.x0
  local R = G.clamp(mw * Tune.compose.hero, 28, 80)
  local hero = { m.x0 + mw * 0.5, spec.header_y - R * 0.55, R }
  local gest = Layout.gesture(Rng.new(seed):fork("gesture"), m, hero)
  local top = gest.density(hero[1], hero[2] - R * 1.5)
  local foot = gest.density(m.x0 + mw * 0.4, m.y0 + 30)
  -- The bow nearest mid-height; one near the hero shares its crowd.
  local mid, nb = (hero[2] + m.y0) / 2, gest.bows[1]
  for _, b in ipairs(gest.bows) do if math.abs(b.y - mid) < math.abs(nb.y - mid) then nb = b end end
  local bow = gest.density(gest.edge + nb.amp * 0.7, nb.y)
  local calm = gest.density(gest.edge, gest.quiet[1])
  H.check(top > bow + 0.1 and foot > bow + 0.1,
    string.format("seed %d: ends (%.2f top, %.2f foot) not denser than the bows (%.2f)", seed, top, foot, bow))
  H.check(bow > calm, string.format("seed %d: bows (%.2f) no denser than the quiet stretch (%.2f)", seed, bow, calm))
end

H.done("plant")
