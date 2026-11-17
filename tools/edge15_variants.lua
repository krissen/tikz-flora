-- The variants of ORDER #15's sheets (tools/edge15-sheets.sh): the knot
-- field running off the paper (ends=bleed) or closing inside it
-- (ends=closed) in every layout; the ground as cells and as a panel; khatam's and hexagram's defaults and
-- keys; gold on a ground; and tsuki-mi's contour on the dark backdrop at
-- three strengths. Each a \florasetup line and prototype options, on the
-- A4 page and the slide.

local variants = {}
local function add(name, setup, opts, patterns, layout, backdrops)
  local set = {}
  for _, p in ipairs(patterns) do set[p] = true end
  variants[#variants + 1] = { name = name, setup = setup, opts = opts, patterns = set, slide = true, layout = layout,
    backdrops = backdrops }
end
for _, cw in ipairs({ "tsuki-mi", "ember" }) do
  local c = "colourway=" .. cw
  for _, layout in ipairs({ "left", "right", "centered", "surround" }) do
    for _, m in ipairs({ "bleed", "inset" }) do
      add("k15-" .. m .. "-" .. layout .. "__" .. cw, c .. ", ends=" .. (m == "bleed" and "bleed" or "closed"), {}, { "celtic_knot" }, layout)
    end
  end
  for _, g in ipairs({ "cells", "panel" }) do
    add("g15-" .. g .. "__" .. cw, c .. ", ground=" .. g, {}, { "sikku_kolam", "asanoha", "rosette_lattice" })
  end
  add("s15-default__" .. cw, c, {}, { "khatam", "hexagram_lattice" })
  add("s15-split__" .. cw, c .. ", starfill=split", {}, { "khatam" })
  add("s15-paper__" .. cw, c .. ", gapfill=paper", {}, { "khatam", "hexagram_lattice" })
  add("s15-rows__" .. cw, c .. ", alternate=rows", {}, { "hexagram_lattice" })
  add("s15-three__" .. cw, c .. ", alternate=three", {}, { "hexagram_lattice" })
  add("e15-gold__" .. cw, c .. ", ground=panel, bands=line, bandwidth=0.5, patternpalette={band=gold}", {},
    { "asanoha", "seigaiha", "kikko" })
end
-- tsuki-mi's contour: today's band (chiku-rin at L 0.46) and two darker
-- bands on paper, which the dark backdrop repaints lighter.
for i, L in ipairs({ 0.46, 0.40, 0.34 }) do
  add("t15-k" .. (i - 1) .. "__tsuki-mi", "colourway=tsuki-mi, patternpalette={band=chiku-rin:" .. L .. ":0.1}", {},
    { "khatam", "hexagram_lattice" })
end
return { variants = variants }
