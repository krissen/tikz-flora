-- The pattern variants tools/pattern_roles.lua renders: each a \florasetup
-- key list laid over the page, rendered on paper and on the dark backdrop.
-- `slide` renders it on the 160 x 90 mm page too. A working list for
-- comparison sheets, not settings.

local Inks = require("flora.inks")

local variants = {}
local function add(name, setup, slide) variants[#variants + 1] = { name = name, setup = setup, slide = slide } end

-- Every colourway as it is, filled and as lines.
for _, cw in ipairs(Inks.colourway_order) do
  add(cw, "colourway=" .. cw, true)
  add(cw .. "-lines", "colourway=" .. cw .. ", finish=lines", true)
end

-- The lines finish with each band character and a wider band, on the
-- original colourway.
add("lines-line", "colourway=original, finish=lines, bands=line")
add("lines-strap", "colourway=original, finish=lines, bands=strap")
add("lines-line-1.5", "colourway=original, finish=lines, bands=line, bandwidth=1.5")
add("lines-strap-1.5", "colourway=original, finish=lines, bands=strap, bandwidth=1.5")

return { variants = variants }
