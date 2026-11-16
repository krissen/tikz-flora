-- The variants of ORDER #13's sheets (tools/edge13-sheets.sh): the knot
-- field as one panel, running off the paper (bleed) or closing inside it
-- (inset), in every layout; khatam's and hexagram's new defaults and their
-- keys; asanoha in gold on a ground. Each a \florasetup line and prototype
-- options, on the A4 page and the slide.

local variants = {}
local function add(name, setup, opts, patterns, layout)
  local set = {}
  for _, p in ipairs(patterns) do set[p] = true end
  variants[#variants + 1] = { name = name, setup = setup, opts = opts, patterns = set, slide = true, layout = layout }
end
for _, cw in ipairs({ "tsuki-mi", "ember" }) do
  local c = "colourway=" .. cw
  for _, layout in ipairs({ "left", "right", "centered", "surround" }) do
    for _, m in ipairs({ "bleed", "inset" }) do
      add("k13-" .. m .. "-" .. layout .. "__" .. cw, c, { knot = m, reweave = false }, { "celtic_knot" }, layout)
    end
  end
  add("s13-default__" .. cw, c, {}, { "khatam", "hexagram_lattice" })
  add("s13-split__" .. cw, c .. ", figure=split", {}, { "khatam" })
  add("s13-paper__" .. cw, c .. ", gaps=paper", {}, { "khatam", "hexagram_lattice" })
  add("s13-rows__" .. cw, c .. ", alternate=rows", {}, { "hexagram_lattice" })
  add("s13-three__" .. cw, c .. ", alternate=three", {}, { "hexagram_lattice" })
  add("e13-gold__" .. cw, c .. ", ground=panel, bands=line, bandwidth=0.5, patternpalette={band=gold}", {},
    { "asanoha", "seigaiha", "kikko" })
end
return { variants = variants }
