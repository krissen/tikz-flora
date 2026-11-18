-- Sikku kolam, the Tamil threshold drawing of lines looped round a grid
-- of dots, drawn here as mirror curves: a line runs diagonally between
-- the dots and turns back wherever it meets a mirror on the edge between
-- two of them. The grid's border is all mirrors and the inner mirrors
-- are drawn at random, so every line closes into a loop. Each loop is a
-- cell, and so is each dot.

local K = require("flora.pat_kit")

local MIRRORS, PULL = 0.42, 0.22
-- Symmetric panels (env.opts.symmetric): SPAN dots a side, walled in, the
-- inner mirrors the same under the square's turns and reflections, one of
-- DESIGNS designs per panel.
local SPAN, DESIGNS = 4, 3

-- Whether (x, y) lies inside polygon P.
local function inside(x, y, P)
  local c, j = false, #P
  for i = 1, #P do
    local a, b = P[i], P[j]
    if (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then c = not c end
    j = i
  end
  return c
end

local function paint_loop(pt, c, ink)
  K.band(pt, c.path, ink)
end

local function paint_dot(pt, c, ink)
  K.fill(pt, c.path, ink.fill[1], ink, { outline = true })
end

local function construct(pt, c, ink)
  pt:stroke(c.path, ink.line, K.cline(ink), 1)
end

local function key(x, y) return string.format("%.1f,%.1f", x, y) end

return {
  name = "sikku_kolam",
  title = "Sikku kolam, lines looped round a grid of dots, as mirror curves",
  tags = { "kolam", "tamil", "south_indian", "dot_grid" },
  roles = { "band", "core", "a", "ground" },
  -- Its finishes beyond filled and lines (pattern.lua's finishes_of).
  finishes = { "lacquer" },
  -- A dark ground, as in the mock (t-10).
  ground = 0.31,
  -- The dots 16 pt apart: 9.4 across the reference field (pattern.lua's
  -- FIELD_SCALE), where 14 drew a fine 10.7. The band keeps its 1.6 pt, so
  -- it stays under the width at which its core would show (pat_kit.lua's
  -- CORE_MIN) and the lines keep their colour.
  scale = 16,
  width = 1.6, core = 0.45, bands = "strap",
  -- It can be drawn again with the field's edge as a wall (pattern.lua),
  -- and by default is, in symmetric panels (the ends and panels keys).
  reweave = true, ends = "closed", panels = "on",
  cells = function(env)
    local a = env.size
    local gx, gy = math.floor(env.x0 / a) - 1, math.floor(env.y0 / a) - 1
    local nx = math.ceil(env.x1 / a) + 1 - gx
    local ny = math.ceil(env.y1 / a) + 1 - gy
    local opts = env.opts or {}
    local mirror = {}
    for i = 0, nx do
      for j = 0, ny - 1 do mirror[key(i, j + .5)] = env.rng:next() < MIRRORS end
    end
    for i = 0, nx - 1 do
      for j = 0, ny do mirror[key(i + .5, j)] = env.rng:next() < MIRRORS end
    end
    if opts.symmetric then
      -- Designs for an SPAN-square panel, keyed by the edge's place in it,
      -- each edge drawn for its whole orbit.
      local designs = {}
      for d = 1, DESIGNS do
        local m, r = {}, env.rng:fork("kolam panel " .. d)
        local function edges(f)
          for i = 0, SPAN do for j = 0, SPAN - 1 do f(i, j + .5) end end
          for i = 0, SPAN - 1 do for j = 0, SPAN do f(i + .5, j) end end
        end
        edges(function(x, y)
          if m[key(x, y)] == nil then
            local v = r:next() < MIRRORS
            for _ = 1, 4 do
              m[key(x, y)] = v
              m[key(SPAN - x, y)] = v
              x, y = SPAN - y, x
            end
          end
        end)
        designs[d] = m
      end
      local off = math.floor(env.rng:next() * 997)
      local function panel_mirror(x, y)
        -- Panel walls along every SPAN-th grid line.
        local gxp, gyp = gx + x, gy + y
        local on_v = math.abs(x - math.floor(x + .5)) < 1e-6
        if (on_v and gxp % SPAN == 0) or (not on_v and gyp % SPAN == 0) then return true end
        local bi, bj = math.floor(gxp / SPAN), math.floor(gyp / SPAN)
        local d = designs[(bi * 73 + bj * 151 + off) % DESIGNS + 1]
        return d[key(gxp - bi * SPAN, gyp - bj * SPAN)] or false
      end
      for k in pairs(mirror) do mirror[k] = nil end
      setmetatable(mirror, { __index = function(_, k)
        local x, y = k:match("^(.-),(.-)$")
        return panel_mirror(tonumber(x), tonumber(y))
      end })
    end
    local function page(q) return { (gx + q[1]) * a, (gy + q[2]) * a } end
    -- Under a second drawing (pattern.lua's reweave) a dot the field
    -- dropped walls itself in: every edge beside it is a mirror.
    local blocked = env.blocked and function(x, y)
      local q = page({ x, y })
      return env.blocked(q[1], q[2])
    end
    local function beside(x, y)
      if math.abs(x - math.floor(x + .5)) < 1e-6 then return { x - .5, y }, { x + .5, y } end
      return { x, y - .5 }, { x, y + .5 }
    end
    local function is_mirror(x, y)
      if x < 1e-6 or y < 1e-6 or x > nx - 1e-6 or y > ny - 1e-6 then return true end
      if blocked then
        local p1, p2 = beside(x, y)
        if blocked(p1[1], p1[2]) or blocked(p2[1], p2[2]) then return true end
      end
      return mirror[key(x, y)]
    end
    local seen = {}
    local function seg(x, y, u, v)
      local p, q = key(x, y), key(u, v)
      if p > q then p, q = q, p end
      return p .. "|" .. q
    end
    local out, loops = {}, {}
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
          local free = not blocked
          repeat
            local ux, uy = x + dx / 2, y + dy / 2
            seen[seg(x, y, ux, uy)] = true
            x, y = ux, uy
            if blocked and not free then
              local p1, p2 = beside(x, y)
              free = not blocked(p1[1], p1[2]) or not blocked(p2[1], p2[2])
            end
            local vx, vy = x, y
            local on_vertical = math.abs(x - math.floor(x + .5)) < 1e-6
            if is_mirror(x, y) then
              if on_vertical then dx = -dx; vx = x + dx * PULL else dy = -dy; vy = y + dy * PULL end
            end
            local q = page({ vx, vy })
            pts[#pts + 1] = q
            cx, cy = cx + q[1], cy + q[2]
          until #pts > 4 * (nx + 1) * (ny + 1) or (x == sx and y == sy and dx == sdx and dy == sdy)
          -- A loop wholly among dropped dots is dropped with them.
          if free then
            local loop = { x = cx / #pts, y = cy / #pts, verts = pts, pad = a * 0.12, path = K.smooth(pts), rests = true,
              paint = paint_loop, construct = construct, group = "loop " .. (#loops + 1) }
            out[#out + 1] = loop
            loops[#loops + 1] = loop
          end
        end
      end
    end
    -- Each loop's extent, so a dot finds the smallest loop round it, the
    -- loop it belongs to.
    for _, l in ipairs(loops) do
      local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
      for _, q in ipairs(l.verts) do
        x0, y0, x1, y1 = math.min(x0, q[1]), math.min(y0, q[2]), math.max(x1, q[1]), math.max(y1, q[2])
      end
      l.box, l.area = { x0, y0, x1, y1 }, (x1 - x0) * (y1 - y0)
    end
    for i = 0, nx - 1 do
      for j = 0, ny - 1 do
        local q = page({ i + .5, j + .5 })
        if blocked and blocked(i + .5, j + .5) then goto next end
        local group
        if opts.units then
          local best = math.huge
          for _, l in ipairs(loops) do
            local b = l.box
            if l.area < best and q[1] > b[1] and q[1] < b[3] and q[2] > b[2] and q[2] < b[4] and inside(q[1], q[2], l.verts) then
              best, group = l.area, l.group
            end
          end
        end
        out[#out + 1] = { x = q[1], y = q[2], group = group, verts = K.ring(q[1], q[2], a * 0.08, 4), circle = { q[1], q[2], a * 0.08 },
          path = { { "o", q[1], q[2], a * 0.08 } }, paint = paint_dot, construct = paint_dot,
          -- At the field's edge (pattern.lua's shape edge) the ground rounds
          -- off about each dot.
          shape = { { "o", q[1], q[2], a * 0.62 } },
          -- The dot's square of the grid, for a ground under the field.
          under = K.path({ { q[1] - a / 2, q[2] - a / 2 }, { q[1] + a / 2, q[2] - a / 2 }, { q[1] + a / 2, q[2] + a / 2 }, { q[1] - a / 2, q[2] + a / 2 } }) }
        ::next::
      end
    end
    return out
  end,
}
