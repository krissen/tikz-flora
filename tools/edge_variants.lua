-- The variants of the "where the pattern ends" and "the form carries"
-- study (tools/edge-sheets.sh lays them out): each a \florasetup line and
-- prototype options (pattern.lua's pattern_opts), rendered by
-- tools/pattern_roles.lua on the slide and the left page, on paper and on
-- the dark backdrop.

local variants = {}
local function add(name, setup, opts, patterns)
  local set = {}
  for _, p in ipairs(patterns) do set[p] = true end
  variants[#variants + 1] = { name = name, setup = setup, opts = opts, patterns = set, slide = true }
end

-- Where the ground and the fields end.
local EDGE = { "rosette_lattice", "sikku_kolam", "khatam", "asanoha" }
for _, cw in ipairs({ "tsuki-mi", "usu-zumi", "ember" }) do
  for _, m in ipairs({ "cells", "dark", "panel", "shape", "fade", "discs" }) do
    add("edge-" .. m .. "__" .. cw, "colourway=" .. cw .. ", ground=on", { ground_edge = m }, EDGE)
  end
end

-- What falls away as a unit.
local UNIT = { "sikku_kolam", "celtic_knot" }
add("unit-today__tsuki-mi", "colourway=tsuki-mi", {}, UNIT)
add("unit-units__tsuki-mi", "colourway=tsuki-mi", { units = true }, UNIT)
add("unit-closed__tsuki-mi", "colourway=tsuki-mi", { reweave = true }, UNIT)
add("unit-symmetric__tsuki-mi", "colourway=tsuki-mi", { reweave = true, symmetric = true }, UNIT)

-- The form carries.
local FORM = { "hexagram_lattice", "greek_crosses", "penrose_rhombs", "khatam" }
local LIGHT = { ["tsuki-mi"] = "fielda=ina-ho:0.84:0.3, fieldb=sui-gyoku:0.78:0.3", ember = "fielda=to-ro:0.84:0.3, fieldb=chiku-rin:0.78:0.3" }
for _, cw in ipairs({ "tsuki-mi", "ember" }) do
  add("form-today__" .. cw, "colourway=" .. cw, {}, FORM)
  add("form-lighter__" .. cw, "colourway=" .. cw .. ", patternpalette={" .. LIGHT[cw] .. "}", {}, FORM)
end

return { variants = variants }
