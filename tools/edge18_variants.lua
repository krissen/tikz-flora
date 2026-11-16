-- The variants of ORDER #18's sheets (tools/edge18-sheets.sh): every value
-- of ground on the patterns that have one; celtic_knot's field panel under
-- ends=closed (the default) and ends=bleed in every layout; and
-- finish=lacquer in three colourways. Each a \florasetup line, on the A4
-- page and the slide.

local variants = {}
local function add(name, setup, patterns, layout)
  local set = {}
  for _, p in ipairs(patterns) do set[p] = true end
  variants[#variants + 1] = { name = name, setup = setup, opts = {}, patterns = set, slide = true, layout = layout }
end
local GROUND = { "sikku_kolam", "asanoha", "rosette_lattice" }
for _, g in ipairs({ "auto", "off", "panel", "motif", "round", "cells" }) do
  add("g18-" .. g .. "__tsuki-mi", "colourway=tsuki-mi, ground=" .. g, GROUND)
end
for _, layout in ipairs({ "left", "right", "centered", "surround" }) do
  for _, e in ipairs({ "closed", "bleed" }) do
    add("f18-" .. e .. "-" .. layout .. "__tsuki-mi", "colourway=tsuki-mi, ends=" .. e, { "celtic_knot" }, layout)
  end
end
for _, cw in ipairs({ "tsuki-mi", "ember", "usu-zumi" }) do
  add("l18__" .. cw, "colourway=" .. cw .. ", finish=lacquer", GROUND)
end
return { variants = variants }
