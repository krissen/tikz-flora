-- Counting a pattern's units at the field's edge (tests/pattern_matrix.lua,
-- tools/unit_measure.lua), on pattern.lua's kept cells:
--
--   M.count(kept, box) -> lone, open
--
-- lone: kolam dots with no kept loop round them; open: line ends (the
-- first and last point of every piece a cell draws: celtic's c.lines,
-- truchet's c.arcs) that meet no other end, inside box {x0, y0, x1, y1}
-- (the page: a line running off the paper ends there by design).

local M = {}

local function inside(x, y, P)
  local c, j = false, #P
  for i = 1, #P do
    local a, b = P[i], P[j]
    if (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then c = not c end
    j = i
  end
  return c
end

local function ends(path)
  local first = path[1]
  local last = path[#path]
  local lx, ly = last[#last - 1], last[#last]
  return { first[2], first[3] }, { lx, ly }
end

function M.count(kept, box)
  local loops, dots, pieces = {}, {}, {}
  for _, k in ipairs(kept) do
    local c = k.cell
    if c.rests and c.verts and c.path and not c.circle then loops[#loops + 1] = c end
    if c.circle and c.paint and c.under then dots[#dots + 1] = c end
    for _, p in ipairs(c.lines or c.arcs or {}) do pieces[#pieces + 1] = p end
  end
  for _, l in ipairs(loops) do
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, q in ipairs(l.verts) do x0, y0, x1, y1 = math.min(x0, q[1]), math.min(y0, q[2]), math.max(x1, q[1]), math.max(y1, q[2]) end
    l._box = { x0, y0, x1, y1 }
  end
  local lone = 0
  for _, d in ipairs(dots) do
    local found = false
    for _, l in ipairs(loops) do
      local b = l._box
      if d.x > b[1] and d.x < b[3] and d.y > b[2] and d.y < b[4] and inside(d.x, d.y, l.verts) then found = true; break end
    end
    if not found then lone = lone + 1 end
  end
  local count = {}
  local function key(q) return string.format("%.1f,%.1f", q[1], q[2]) end
  for _, p in ipairs(pieces) do
    local a, b = ends(p)
    count[key(a)] = (count[key(a)] or 0) + 1
    count[key(b)] = (count[key(b)] or 0) + 1
  end
  local open = 0
  for k, n in pairs(count) do
    local x, y = k:match("^(.-),(.-)$")
    x, y = tonumber(x), tonumber(y)
    local inbox = not box or (x > box[1] and x < box[3] and y > box[2] and y < box[4])
    if n % 2 == 1 and inbox then open = open + 1 end
  end
  return lone, open
end

return M
