-- layout=frame, the pattern as a band round the paper's edge
-- (pattern.lua's M.frame_band): its cells moved about the paper's centre
-- paint what they painted before, moved; the band keeps clear of the
-- text block, meets the paper alike on opposite sides and runs to the
-- paper's top under a top inset and a frame title; and the frame keys
-- leave every other layout as it was.
local H = dofile("tests/helper.lua")
local Patterns = require("flora.patterns")
local Pattern = require("flora.pattern")
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Rng = require("flora.rng")

-- The numbers in a painter's output, for comparing two drawings.
local function numbers(s)
  local out = {}
  for n in s:gmatch("-?%d+%.?%d*") do out[#out + 1] = tonumber(n) end
  return out
end

local function same(a, b, tol)
  if #a ~= #b then return false, string.format("%d numbers against %d", #a, #b) end
  for i = 1, #a do
    if math.abs(a[i] - b[i]) > tol then return false, string.format("number %d: %g against %g", i, a[i], b[i]) end
  end
  return true
end

-- Every cell of pattern p painted (its lines and the cell) with the map
-- `fn` on every coordinate.
local function paint_cells(p, cells, fn)
  local pt = Paint.new({ backend = "pdf" })
  local base = Pattern.role_inks(Rng.new(3), p, {})
  local ink = Pattern.band_ink(Pattern.cell_inks(base, 1), p, {}, 1, 1)
  pt:frame(fn)
  for _, c in ipairs(cells) do
    c.construct(pt, c, ink)
    c.paint(pt, c, ink)
  end
  pt:frame(nil)
  return pt:body()
end

local function env_of(p)
  return { x0 = -40, y0 = -30, x1 = 160, y1 = 120, size = p.scale, rng = Rng.new(7), opts = {}, style = {} }
end

local ox, oy = 37.25, -11.5
for _, p in ipairs(Patterns.list) do
  local moved = Pattern.shift_cells(p.cells(env_of(p)), ox, oy)
  local a = paint_cells(p, p.cells(env_of(p)), function(x, y) return x + ox, y + oy end)
  local b = paint_cells(p, moved, function(x, y) return x, y end)
  local ok, why = same(numbers(a), numbers(b), 2e-3)
  H.check(ok, p.name .. ": moved cells paint differently: " .. tostring(why))
  -- Moving one drawing leaves the module's own tables where they were.
  local c = paint_cells(p, p.cells(env_of(p)), function(x, y) return x + ox, y + oy end)
  H.check(a == c, p.name .. ": moving cells changed a later drawing")
end

-- A 16:9 slide, 160 x 90 mm, with 16 mm margins and a frame title under
-- the presentation theme's setup.
local MM = 72 / 25.4
local function slide(layout, extra)
  local W, Hh, m = 160 * MM, 90 * MM, 16 * MM
  local spec = {
    width = W, height = Hh, text = { x0 = m, y0 = m, x1 = W - m, y1 = Hh - m },
    lines = { { x0 = m, y0 = Hh - m - 14, x1 = m + 120, y1 = Hh - m } },
    header_y = Hh - m, header = "margin", frametitle = true, frametitle_height = 16, top_inset = 20,
    tune = { gesture = { header_clip = 1, header_gap = 12 } },
    seed = 11, layout = layout, pattern = "kikko", ornaments = {},
  }
  for k, v in pairs(extra or {}) do spec[k] = v end
  return spec
end

do
  local spec = slide("frame", { frame_width = 12 })
  local t = { x0 = spec.text.x0, y0 = spec.text.y0, x1 = spec.text.x1, y1 = spec.text.y1 }
  local W, Hh = spec.width, spec.height
  local pt = Compose.page(spec)
  local q = pt.pattern
  H.check(q.cells > 0, "frame: no cells")
  local L, R, B, T = math.huge, -math.huge, math.huge, -math.huge
  local top = 0
  for _, k in ipairs(q.kept) do
    local c = k.cell
    H.check(Pattern.clearance(c, { t.x0, t.y0, t.x1, t.y1 }) - q.reach >= 6 - 1e-6,
      string.format("frame: a cell at %.1f, %.1f lies nearer the text block than the gap", c.x, c.y))
    for _, v in ipairs(c.verts) do L, R, B, T = math.min(L, v[1]), math.max(R, v[1]), math.min(B, v[2]), math.max(T, v[2]) end
    if c.y > t.y1 and c.x > t.x0 and c.x < t.x1 then top = top + 1 end
  end
  H.check(top > 0, "frame: no band above the text under a top inset and a frame title")
  H.check(math.abs(L - (W - R)) < 1e-6, string.format("frame: left %.3f and right %.3f differ", L, W - R))
  H.check(math.abs(B - (Hh - T)) < 1e-6, string.format("frame: foot %.3f and top %.3f differ", B, Hh - T))
end

-- The repeats the whole rows are sized by: kikko's honeycomb repeats
-- every three sides along x and every sqrt(3) sides along y.
do
  local kikko
  for _, p in ipairs(Patterns.list) do if p.name == "kikko" then kikko = p end end
  local px, py = Pattern.periods(kikko)
  H.check(px and math.abs(px - 3 * kikko.scale) < 1e-3, "kikko's repeat along x: " .. tostring(px))
  H.check(py and math.abs(py - math.sqrt(3) * kikko.scale) < 1e-3, "kikko's repeat along y: " .. tostring(py))
end

-- frameinner=rows: a whole number of rows fills the band, each side's
-- cells lie wholly inside the band (asanoha's rows end in a straight
-- edge), and nothing comes nearer the text block than the gap.
do
  local spec = slide("frame", { frame_width = 12, frame_inner = "rows", pattern = "asanoha" })
  local t = { spec.text.x0, spec.text.y0, spec.text.x1, spec.text.y1 }
  local W, Hh = spec.width, spec.height
  local w = 12 * MM
  local pt = Compose.page(spec)
  local q = pt.pattern
  H.check(q.rows and q.rows >= 1, "rows: no row count")
  H.check(q.cover and q.cover > 0.999, "rows: asanoha's whole rows leave the inner repeat uncovered: " .. tostring(q.cover))
  local deepest = 0
  for _, k in ipairs(q.kept) do
    local c = k.cell
    H.check(Pattern.clearance(c, t) >= 6, string.format("rows: a cell at %.1f, %.1f lies nearer the text block than the gap", c.x, c.y))
    -- How far in from the nearest paper edge the cell reaches.
    for _, v in ipairs(c.verts) do
      local e = math.min(v[1], v[2], W - v[1], Hh - v[2])
      deepest = math.max(deepest, e)
    end
  end
  H.check(deepest <= w + 1e-3, string.format("rows: a cell reaches %.2f pt in, past the band's %.2f", deepest, w))
  H.check(deepest >= w - 1e-3, string.format("rows: the rows end %.2f pt in, short of the band's %.2f", deepest, w))
end

-- The frame keys change nothing on a page of another layout.
do
  local a = Compose.page(slide("surround")):body()
  local b = Compose.page(slide("surround", { frame_width = 8, frame_inner = "rows" })):body()
  H.check(a == b, "surround: the frame keys changed the page")
end

H.done("test_pattern_frame")
