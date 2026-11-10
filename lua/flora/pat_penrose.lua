-- Penrose's rhomb tiling (P3), thick and thin rhombs that never repeat:
-- a wheel of ten Robinson triangles is deflated until its edges are the
-- cell size, and triangles sharing a base are joined into rhombs.

local K = require("flora.pat_kit")
local sqrt, cos, sin, pi = math.sqrt, math.cos, math.sin, math.pi
local PHI = (1 + sqrt(5)) / 2

local function paint(pt, c, ink)
  pt:fill(c.path, ink.fill[c.thick and 1 or 2], 1)
  pt:stroke(c.path, ink.band, ink.width, 1)
end

local function construct(pt, c, ink)
  pt:stroke(c.path, ink.line, 0.4, 1)
end

local function lerp(p, q, t) return { p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t } end
local function key(p) return string.format("%.2f,%.2f", p[1], p[2]) end

return {
  name = "penrose_rhombs",
  title = "Penrose rhombs (P3), thick and thin rhombs in a tiling that never repeats",
  tags = { "aperiodic", "rhombs" },
  scale = 16,
  width = 1.1,
  cells = function(env)
    local cx, cy = (env.x0 + env.x1) / 2, (env.y0 + env.y1) / 2
    local R = sqrt((env.x1 - env.x0) ^ 2 + (env.y1 - env.y0) ^ 2) / 2 * 1.15
    local depth = math.max(1, math.ceil(math.log(R / env.size) / math.log(PHI)))
    local tris = {}
    for i = 0, 9 do
      local b = { cx + R * cos((2 * i - 1) * pi / 10), cy + R * sin((2 * i - 1) * pi / 10) }
      local c = { cx + R * cos((2 * i + 1) * pi / 10), cy + R * sin((2 * i + 1) * pi / 10) }
      if i % 2 == 0 then b, c = c, b end
      tris[#tris + 1] = { 0, { cx, cy }, b, c }
    end
    local function visible(t)
      local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
      for k = 2, 4 do
        x0, y0 = math.min(x0, t[k][1]), math.min(y0, t[k][2])
        x1, y1 = math.max(x1, t[k][1]), math.max(y1, t[k][2])
      end
      local m = env.size * 2
      return x1 > env.x0 - m and x0 < env.x1 + m and y1 > env.y0 - m and y0 < env.y1 + m
    end
    for _ = 1, depth do
      local nx = {}
      for _, t in ipairs(tris) do
        local col, A, B, C = t[1], t[2], t[3], t[4]
        local kids
        if col == 0 then
          local P = lerp(A, B, 1 / PHI)
          kids = { { 0, C, P, B }, { 1, P, C, A } }
        else
          local Q, Rr = lerp(B, A, 1 / PHI), lerp(B, C, 1 / PHI)
          kids = { { 1, Rr, C, A }, { 1, Q, Rr, B }, { 0, Rr, Q, A } }
        end
        for _, k in ipairs(kids) do if visible(k) then nx[#nx + 1] = k end end
      end
      tris = nx
    end
    -- Two triangles of one colour sharing their base B-C make a rhomb.
    local half, out = {}, {}
    for _, t in ipairs(tris) do
      local a, b = key(t[3]), key(t[4])
      if a > b then a, b = b, a end
      local k = t[1] .. ":" .. a .. "|" .. b
      local o = half[k]
      if o then
        half[k] = nil
        local P = { t[2], t[3], o[2], t[4] }
        local x = (t[2][1] + o[2][1]) / 2
        local y = (t[2][2] + o[2][2]) / 2
        out[#out + 1] = { x = x, y = y, verts = P, tile = P, path = K.path(P), thick = t[1] == 1,
          paint = paint, construct = construct }
      else
        half[k] = t
      end
    end
    table.sort(out, function(p, q) if p.y ~= q.y then return p.y < q.y end return p.x < q.x end)
    return out
  end,
}
