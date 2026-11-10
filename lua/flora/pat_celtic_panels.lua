-- Celtic knot panels: the interlace of pat_celtic.lua in groups. Walls of
-- mirrors run along every SPAN-th grid line in both directions, cutting the
-- field into square panels, and inside each panel a few more mirrors are
-- set so the panel's strands knot together. The inner mirrors are
-- symmetric under the square's turns and reflections, as a knot panel is,
-- and a handful of such designs are dealt out over the panels at random.

local Celtic = require("flora.pat_celtic")

local SPAN, DESIGNS, MIRRORS = 6, 3, 0.2

-- One design: which inner edges of an n by n panel hold a mirror, keyed by
-- the edge's doubled coordinates. Each edge is drawn for its whole orbit
-- under the square's symmetries.
local function design(n, rng)
  local m = {}
  local function key(x, y) return math.floor(x * 2 + 0.5) * 1000 + math.floor(y * 2 + 0.5) end
  for i = 1, n - 1 do
    for j = 0, n - 1 do
      for _, q in ipairs({ { i, j + .5 }, { j + .5, i } }) do
        if m[key(q[1], q[2])] == nil then
          local v = rng:next() < MIRRORS
          local x, y = q[1], q[2]
          for _ = 1, 4 do
            m[key(x, y)] = v
            m[key(n - x, y)] = v
            x, y = n - y, x
          end
        end
      end
    end
  end
  return m, key
end

local function inner_for(gx, gy, nx, ny, rng)
  local designs, key = {}, nil
  for k = 1, DESIGNS do designs[k], key = design(SPAN, rng:fork("panel " .. k)) end
  local offset = math.floor(rng:next() * 997)
  return function(X, Y)
    local x, y = gx + X / 2, gy + Y / 2
    if X % 2 == 0 then
      if x % SPAN == 0 then return true end
    elseif y % SPAN == 0 then
      return true
    end
    local bi, bj = math.floor(x / SPAN), math.floor(y / SPAN)
    local d = designs[(bi * 73 + bj * 151 + offset) % DESIGNS + 1]
    return d[key(x - bi * SPAN, y - bj * SPAN)] or false
  end
end

return {
  name = "celtic_panels",
  title = "Celtic knot panels, symmetric mirror curves in square groups with alternating crossings",
  tags = { "celtic", "insular", "interlace", "knot", "panel" },
  scale = Celtic.scale,
  width = Celtic.width,
  cells = function(env) return Celtic.engine.cells_with(env, inner_for) end,
}
