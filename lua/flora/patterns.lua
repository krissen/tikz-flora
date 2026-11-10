-- The geometric patterns a page can be filled with instead of flora
-- (pattern.lua lays them out). Each pattern is a module, listed in
-- MODULES, that returns its description:
--
--   name   the key it is weighed by in pattern={...}, the pattern's own
--          name where it has one (asanoha), else a plain description of
--          its geometry (stars_8_4)
--   title  a line for the guide
--   tags   groups it belongs to: its tradition, craft and construction.
--          pattern={japanese=1} weighs every pattern tagged japanese, so
--          related patterns (or every symbol-like one, tagged symbol) can
--          be chosen together
--   scale  its cell size in pt at scale=1
--   width  its band width in pt at scale=1 (default: a sixth of scale)
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
--          faded for the cell. A cell built on a tiling keeps its tile
--          as `tile`; tiles meet edge to edge (tests/test_pattern.lua).

local M = { list = {}, by_name = {}, tags = {} }

local MODULES = {
  "flora.pat_stars", "flora.pat_asanoha", "flora.pat_kikko", "flora.pat_shippo", "flora.pat_seigaiha", "flora.pat_kolam",
}

function M.register(p)
  assert(p.name and p.title and p.tags and p.scale and p.cells, "pattern needs name, title, tags, scale and cells")
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
-- weight when named, else the largest weight of its tags, else 0.
function M.weight(weights, p)
  if weights[p.name] ~= nil then return weights[p.name] end
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
