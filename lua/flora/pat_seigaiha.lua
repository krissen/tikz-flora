-- Seigaiha, "blue sea waves": rows of fans of concentric rings, each row
-- set half a fan along and laid over the row above, so only the fans'
-- upper halves show. Cells are given top row first, so later rows cover
-- earlier ones as the field paints them in order. A fan's compass starts
-- at its left and turns clockwise, over the crest that shows first.

local K = require("flora.pat_kit")

local RINGS = { 1, 0.78, 0.56, 0.34 }

-- Each fan is the paper, to cover the row behind it, ruled with its rings;
-- only its innermost disc is coloured, and the ring outside that is drawn
-- in the second field.
-- Under the lines finish nothing covers the rows behind, so a fan's rings
-- are clipped to leave out the three fans in front of it.
local function paint(pt, c, ink)
  local clips = 0
  if ink.lines then
    local r, big = c.r, 4 * c.r
    for _, q in ipairs({ { c.x - r, c.y - r / 2 }, { c.x + r, c.y - r / 2 }, { c.x, c.y - r } }) do
      local box = { { "m", c.x - big, c.y - big }, { "l", c.x + big, c.y - big }, { "l", c.x + big, c.y + big }, { "l", c.x - big, c.y + big }, { "z" } }
      for _, s in ipairs(K.circle_cw(q[1], q[2], r)) do box[#box + 1] = s end
      pt:clip_begin(box)
      clips = clips + 1
    end
  end
  K.fill(pt, { { "o", c.x, c.y, c.r } }, ink.core, ink)
  for k, f in ipairs(RINGS) do
    local disc = { { "o", c.x, c.y, c.r * f } }
    if k == #RINGS then K.fill(pt, disc, ink.fill[1], ink) end
    if k == #RINGS - 1 and not ink.lines then
      pt:stroke(disc, ink.fill[2], ink.width * 0.55, 1)
    else
      K.band(pt, disc, ink, { core = false, w = k == 1 and 1 or 0.55 })
    end
  end
  for _ = 1, clips do pt:clip_end() end
end

local function construct(pt, c, ink)
  pt:stroke({ { "o", c.x, c.y, c.r } }, ink.line, 0.4, 1)
end

return {
  name = "seigaiha",
  title = "Seigaiha (blue sea waves), overlapping fans of concentric rings",
  tags = { "japanese", "circles", "wave" },
  roles = { "band", "core", "a", "b" },
  surface = true,
  scale = 20,
  width = 1.2, bands = "strap",
  cells = function(env)
    local r = env.size
    local dx, dy = 2 * r, r / 2
    local out = {}
    for j = math.ceil(env.y1 / dy) + 2, math.floor(env.y0 / dy) - 2, -1 do
      for i = math.floor(env.x0 / dx) - 1, math.ceil(env.x1 / dx) + 1 do
        local x, y = i * dx + (j % 2) * r, j * dy
        out[#out + 1] = { x = x, y = y, r = r, verts = K.ring(x, y, r), circle = { x, y, r }, under = { { "o", x, y, r } },
          sweep = { x, y, math.pi, -1 }, paint = paint, construct = construct }
      end
    end
    return out
  end,
}
