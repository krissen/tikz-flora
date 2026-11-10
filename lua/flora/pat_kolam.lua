-- Sikku kolam, the Tamil threshold drawing of lines looped round a grid
-- of dots, drawn here as mirror curves: a line runs diagonally between
-- the dots and turns back wherever it meets a mirror on the edge between
-- two of them. The grid's border is all mirrors and the inner mirrors
-- are drawn at random, so every line closes into a loop. Each loop is a
-- cell, and so is each dot.

local K = require("flora.pat_kit")

local MIRRORS, PULL = 0.42, 0.22

local function paint_loop(pt, c, ink)
  pt:stroke(c.path, ink.band, ink.width, 1)
  pt:stroke(c.path, ink.core, ink.width * 0.45, 1)
end

local function paint_dot(pt, c, ink)
  pt:fill(c.path, ink.fill[1], 1)
end

local function construct(pt, c, ink)
  pt:stroke(c.path, ink.line, 0.4, 1)
end

local function key(x, y) return string.format("%.1f,%.1f", x, y) end

return {
  name = "sikku_kolam",
  title = "Sikku kolam, lines looped round a grid of dots, as mirror curves",
  tags = { "kolam", "tamil", "south_indian", "dot_grid" },
  scale = 14,
  width = 1.6,
  cells = function(env)
    local a = env.size
    local gx, gy = math.floor(env.x0 / a) - 1, math.floor(env.y0 / a) - 1
    local nx = math.ceil(env.x1 / a) + 1 - gx
    local ny = math.ceil(env.y1 / a) + 1 - gy
    local mirror = {}
    for i = 0, nx do
      for j = 0, ny - 1 do mirror[key(i, j + .5)] = env.rng:next() < MIRRORS end
    end
    for i = 0, nx - 1 do
      for j = 0, ny do mirror[key(i + .5, j)] = env.rng:next() < MIRRORS end
    end
    local function is_mirror(x, y)
      if x < 1e-6 or y < 1e-6 or x > nx - 1e-6 or y > ny - 1e-6 then return true end
      return mirror[key(x, y)]
    end
    local seen = {}
    local function seg(x, y, u, v)
      local p, q = key(x, y), key(u, v)
      if p > q then p, q = q, p end
      return p .. "|" .. q
    end
    local out = {}
    local function page(q) return { (gx + q[1]) * a, (gy + q[2]) * a } end
    local starts = {}
    for i = 0, nx do for j = 0, ny - 1 do starts[#starts + 1] = { i, j + .5 } end end
    for i = 0, nx - 1 do for j = 0, ny do starts[#starts + 1] = { i + .5, j } end end
    for _, s0 in ipairs(starts) do
      for _, d0 in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
        local x, y, dx, dy = s0[1], s0[2], d0[1], d0[2]
        local nx1, ny1 = x + dx / 2, y + dy / 2
        if nx1 >= 0 and ny1 >= 0 and nx1 <= nx and ny1 <= ny and not seen[seg(x, y, nx1, ny1)] then
          local pts, sx, sy, sdx, sdy = {}, x, y, dx, dy
          local cx, cy = 0, 0
          repeat
            local ux, uy = x + dx / 2, y + dy / 2
            seen[seg(x, y, ux, uy)] = true
            x, y = ux, uy
            local vx, vy = x, y
            local on_vertical = math.abs(x - math.floor(x + .5)) < 1e-6
            if is_mirror(x, y) then
              if on_vertical then dx = -dx; vx = x + dx * PULL else dy = -dy; vy = y + dy * PULL end
            end
            local q = page({ vx, vy })
            pts[#pts + 1] = q
            cx, cy = cx + q[1], cy + q[2]
          until #pts > 4 * (nx + 1) * (ny + 1) or (x == sx and y == sy and dx == sdx and dy == sdy)
          out[#out + 1] = { x = cx / #pts, y = cy / #pts, verts = pts, pad = a * 0.12, path = K.smooth(pts),
            paint = paint_loop, construct = construct }
        end
      end
    end
    for i = 0, nx - 1 do
      for j = 0, ny - 1 do
        local q = page({ i + .5, j + .5 })
        out[#out + 1] = { x = q[1], y = q[2], verts = K.ring(q[1], q[2], a * 0.08, 4), circle = { q[1], q[2], a * 0.08 },
          path = { { "o", q[1], q[2], a * 0.08 } }, paint = paint_dot, construct = paint_dot }
      end
    end
    return out
  end,
}
