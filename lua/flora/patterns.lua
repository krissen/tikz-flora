-- The geometric patterns a page can be filled with instead of flora
-- (pattern.lua lays them out). Each pattern is a module, listed in
-- MODULES, that returns its description:
--
--   name   the key it is weighed by in pattern={...}, the pattern's own
--          name where it has one (asanoha), else a plain description of
--          its geometry (stars_8_4)
--   title  a line for the guide
--   tags   groups it belongs to: its region or period, craft and
--          construction, never a religious tradition.
--          pattern={japanese=1} weighs every pattern tagged japanese, so
--          related patterns (or every symbol-like one, tagged symbol) can
--          be chosen together
--   opt_in  true for a pattern whose cell is a recognisable emblem. An
--          opt-in pattern is never picked through an ordinary group
--          (square, star, triangular, ...): its weight is its own
--          name's, else the weight given to the group `symbol`, else 0.
--   surface  true for a pattern whose filled finish is a surface of
--          fields (tiles, stars, petals) rather than line work: its bands
--          lie on its fields (tests/pattern_matrix.lua measures them so).
--   width, core, bands, line  its bands: full width in pt at scale=1, the
--          core's share of it, "strap" or "line", and the line's width;
--          lines_bands the character under the lines finish, if another
--   ground  for a pattern listing the ground role, the ground's lightness
--   roles  the colour roles it paints with (pattern.lua's M.roles: band,
--          core, a, b, accent, ground, and paper for a halo the page's own
--          colour); it paints with no other. A pattern listing ground
--          gives each cell's piece of it, the cell's `under` path or its
--          `tile`, which the field paints under every cell when the page's
--          roles turn the ground on. A cell that lies on its neighbours'
--          pieces and has none of its own says `rests = true`. A cell's
--          `plates`, {path, "a" or "b"} pairs, are fields that tile the
--          plane, painted with the ground.
--   scale  its cell size in pt at scale=1
--   cells(env) -> list of cells covering env's box {x0, y0, x1, y1} at
--          cell size env.size, drawing from env.rng. A cell is
--          { x, y, verts, paint = fn(pt, cell, ink), construct = fn(pt,
--          cell, ink) }: its centre, the outline its paint stays inside
--          (a polygon `verts`, or `circle = {x, y, r}` for a round cell),
--          and how it is painted, finished or as its construction lines
--          while it grows. Strokes may reach half a band beyond the
--          outline, and `pad` further where paint sticks out more. The
--          field measures the whole outline against the page's edges
--          and the text (pattern.lua). `ink` holds the colours, already
--          faded for the cell, and the band's character (pat_kit.lua's
--          K.band and K.fill paint with it). A cell built on a tiling keeps its tile
--          as `tile`; tiles meet edge to edge (tests/test_pattern.lua).
--          A cell drawn with a compass may give `sweep = {x, y, a0,
--          turn}`: the compass point and the angle (radians) it starts
--          at, turning counter-clockwise, or clockwise for turn = -1.
--          While the cell grows its construction lines show only inside
--          a wedge about that point that opens through a full turn
--          (progression.lua's wedge), so a circle about it is drawn as an
--          arc from a0; once that turn is done its paint is drawn the
--          same way in a second turn. A page that does not grow never
--          reads it.

local M = { list = {}, by_name = {}, tags = {} }

-- The roles a pattern may list.
M.ROLES = { band = true, core = true, a = true, b = true, accent = true, ground = true, paper = true }

local MODULES = {
  "flora.pat_stars", "flora.pat_asanoha", "flora.pat_kikko", "flora.pat_shippo", "flora.pat_seigaiha", "flora.pat_kolam", "flora.pat_circles", "flora.pat_truchet", "flora.pat_penrose", "flora.pat_celtic", "flora.pat_celtic_panels",
  "flora.pat_hexagram", "flora.pat_khatam", "flora.pat_crosses",
  "flora.pat_rosette",
}

function M.register(p)
  assert(p.name and p.title and p.tags and p.scale and p.cells and p.roles, "pattern needs name, title, tags, roles, scale and cells")
  for _, r in ipairs(p.roles) do assert(M.ROLES[r], p.name .. ": no role " .. tostring(r)) end
  assert(not M.by_name[p.name], "duplicate pattern " .. p.name)
  M.list[#M.list + 1] = p
  M.by_name[p.name] = p
  for _, t in ipairs(p.tags) do
    M.tags[t] = M.tags[t] or {}
    table.insert(M.tags[t], p.name)
  end
end

for _, m in ipairs(MODULES) do M.register(require(m)) end
table.sort(M.list, function(a, b) return a.name < b.name end)

-- Every name pattern={...} accepts: pattern names, then tags.
function M.known()
  local names, tags = {}, {}
  for _, p in ipairs(M.list) do names[#names + 1] = p.name end
  for t in pairs(M.tags) do if not M.by_name[t] then tags[#tags + 1] = t end end
  table.sort(tags)
  return names, tags
end

-- A pattern's weight under `weights` (name or tag -> weight): its own
-- weight when named, else the largest weight of its tags, else 0. An
-- opt-in pattern has only its own name's weight, else that of `symbol`.
function M.weight(weights, p)
  if weights[p.name] ~= nil then return weights[p.name] end
  if p.opt_in then return weights.symbol or 0 end
  local w = 0
  for _, t in ipairs(p.tags) do
    if weights[t] and weights[t] > w then w = weights[t] end
  end
  return w
end

-- The pattern for a page, drawn by weight from `rng`, or nil when every
-- weight is 0.
function M.pick(rng, weights)
  local total, ws = 0, {}
  for i, p in ipairs(M.list) do
    ws[i] = M.weight(weights, p)
    total = total + ws[i]
  end
  if total <= 0 then return nil end
  local u = rng:next() * total
  for i, p in ipairs(M.list) do
    u = u - ws[i]
    if u < 0 and ws[i] > 0 then return p end
  end
  for i = #M.list, 1, -1 do if ws[i] > 0 then return M.list[i] end end
end

return M
