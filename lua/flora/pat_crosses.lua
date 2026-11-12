-- Greek crosses that tile the plane by themselves: each cross is five unit
-- squares, and the lattice vectors are (2, 1) and (-1, 2) in units of an
-- arm's width, so the crosses meet edge to edge. Four colours colour them
-- so that no two crosses meeting have the same one. An emblem pattern:
-- opt-in (patterns.lua), picked only by its own name or by the group
-- `symbol`.

local K = require("flora.pat_kit")

local SHAPE = {
  { -0.5, -1.5 }, { 0.5, -1.5 }, { 0.5, -0.5 }, { 1.5, -0.5 }, { 1.5, 0.5 }, { 0.5, 0.5 },
  { 0.5, 1.5 }, { -0.5, 1.5 }, { -0.5, 0.5 }, { -1.5, 0.5 }, { -1.5, -0.5 }, { -0.5, -0.5 },
}

local function paint(pt, c, ink)
  local fills = { ink.fill[1], ink.fill[2], ink.accent, ink.core }
  pt:fill(c.path, fills[c.tone], 1)
  pt:stroke(c.path, ink.band, ink.width, 1)
end

local function construct(pt, c, ink)
  pt:stroke(c.path, ink.line, 0.4, 1)
end

return {
  name = "greek_crosses",
  title = "Greek crosses tiling the plane edge to edge, in four colours",
  tags = { "symbol", "cross", "square", "tiling" },
  roles = { "band", "a", "b", "accent", "core" },
  opt_in = true,
  scale = 36,
  width = 1.2,
  cells = function(env)
    local u = env.size / 3
    local lo_i, hi_i, lo_j, hi_j = math.huge, -math.huge, math.huge, -math.huge
    for _, q in ipairs({ { env.x0, env.y0 }, { env.x1, env.y0 }, { env.x1, env.y1 }, { env.x0, env.y1 } }) do
      local i, j = (2 * q[1] + q[2]) / (5 * u), (2 * q[2] - q[1]) / (5 * u)
      lo_i, hi_i = math.min(lo_i, i), math.max(hi_i, i)
      lo_j, hi_j = math.min(lo_j, j), math.max(hi_j, j)
    end
    local out = {}
    for i = math.floor(lo_i) - 2, math.ceil(hi_i) + 2 do
      for j = math.floor(lo_j) - 2, math.ceil(hi_j) + 2 do
        local cx, cy = (2 * i - j) * u, (i + 2 * j) * u
        if cx > env.x0 - 3 * u and cx < env.x1 + 3 * u and cy > env.y0 - 3 * u and cy < env.y1 + 3 * u then
          local P = {}
          for k, q in ipairs(SHAPE) do P[k] = { cx + q[1] * u, cy + q[2] * u } end
          out[#out + 1] = { x = cx, y = cy, verts = P, tile = P, path = K.path(P),
            tone = (i + 2 * j) % 4 + 1, paint = paint, construct = construct }
        end
      end
    end
    return out
  end,
}
