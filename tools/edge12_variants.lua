-- The variants of ORDER #12's sheets (tools/edge12-sheets.sh): khatam's
-- stars and crosses, hexagram's star in one colour, the closed knot
-- panels, the two new heroes, and asanoha on a ground in thin gold lines.
-- Each a \florasetup line and prototype options, on the slide.

local variants = {}
local function add(name, setup, opts, patterns)
  local set = {}
  for _, p in ipairs(patterns) do set[p] = true end
  variants[#variants + 1] = { name = name, setup = setup, opts = opts, patterns = set, slide = true }
end
local PANEL = { reweave = false, units = true }
local function with(t, extra)
  local o = {}
  for k, v in pairs(t) do o[k] = v end
  for k, v in pairs(extra) do o[k] = v end
  return o
end
for _, cw in ipairs({ "tsuki-mi", "ember" }) do
  local c = "colourway=" .. cw
  -- A. khatam
  add("k12-today__" .. cw, c, {}, { "khatam" })
  for _, f in ipairs({ "two", "one", "paper", "dot" }) do add("k12-" .. f .. "__" .. cw, c, { khatam = f }, { "khatam" }) end
  -- B. hexagram, every star one colour
  for _, f in ipairs({ "star-thin", "plain", "rows", "three" }) do add("h12-" .. f .. "__" .. cw, c, { hexagram = f }, { "hexagram_lattice" }) end
  add("h12-lines__" .. cw, c .. ", finish=lines", { hexagram = "plain" }, { "hexagram_lattice" })
  -- C. the knot panels
  add("c12-today__" .. cw, c, {}, { "celtic_knot", "celtic_panels" })
  add("c12-one__" .. cw, c, with(PANEL, { knot = "one" }), { "celtic_knot", "celtic_panels" })
  add("c12-several__" .. cw, c, with(PANEL, { knot = "several" }), { "celtic_knot", "celtic_panels" })
  -- D. the heroes, each beside the one it is not to be taken for
  add("d12-guilloche__" .. cw, c .. ", hero=guilloche, outer=margin", {}, { "stars_8_4" })
  add("d12-turned__" .. cw, c .. ", hero=turned_circles, outer=margin", {}, { "stars_8_4" })
  add("d12-circles__" .. cw, c, {}, { "overlapping_circles" })
  add("d12-disc__" .. cw, c .. ", hero=circle_disc, outer=margin", {}, { "overlapping_circles" })
  -- E. asanoha
  add("e12-today__" .. cw, c, {}, { "asanoha" })
  add("e12-gold__" .. cw, c .. ", ground=panel, bands=line, bandwidth=0.5, patternpalette={band=gold}", {}, { "asanoha" })
end
return { variants = variants }
