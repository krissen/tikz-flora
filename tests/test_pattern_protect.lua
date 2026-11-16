-- Nothing a pattern paints comes within the field's gap of the text, its
-- lines or a reservation, measured as overlap of the paint itself
-- (tests/pattern_protect.lua).
local H = dofile("tests/helper.lua")
local M = dofile("tests/pattern_protect.lua")

-- Four whole stars round a cross, and a reservation inside the cross only:
-- every star clears it by more than the gap, the cross does not.
do
  local spec = { width = 400, height = 400, text = { x0 = 20, y0 = 350, x1 = 380, y1 = 390 }, seed = 7, layout = "surround",
    pattern = { khatam = 1 }, pattern_scale = 4, pattern_edge = "cell", mix = { density = 10 }, reserve = { { 164, 164, 172, 172 } },
    lines = { { x0 = 20, y0 = 380, x1 = 100, y1 = 390 } } }
  local pt, o = M.overlaps(spec)
  local stars = 0
  for _, k in ipairs(pt.pattern.kept) do
    local c = k.cell
    if (c.x == 112 or c.x == 224) and (c.y == 112 or c.y == 224) then stars = stars + 1 end
  end
  H.check(stars == 4, "the four stars round the cross stand: " .. stars)
  H.check(#o == 0, "a plate between cells keeps clear of a reservation inside it: " .. #o .. " overlaps")
end

H.done("pattern protect")
