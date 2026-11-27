-- The pattern variants tools/pattern_roles.lua renders: each a \florasetup
-- key list laid over the page, rendered on paper and on the dark backdrop.
-- `slide` renders it on the 160 x 90 mm page too. A working list for
-- comparison sheets, not settings. A variant with a `set` belongs to a
-- prototype sheet (tools/pattern-proto.sh) and is rendered only when that
-- set is asked for.

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

-- The prototype sets (lua/flora/pattern_proto.lua's pattern_opts keys), one
-- variant per setting, laid out by tools/pattern-proto.sh.
local COLOURWAY = "colourway=original"

-- gold: where the gold lies, on the same field and hero (paper and dark).
local GOLD = { "off", "core", "cells", "knobs", "crossings", "hero" }
local GOLD_PATTERNS = { stars_8_4 = true, overlapping_circles = true, celtic_knot = true, asanoha = true }
for _, g in ipairs(GOLD) do
  variants[#variants + 1] = { name = "gold-" .. g, set = "gold", setup = COLOURWAY, opts = g ~= "off" and { gold = g } or nil,
    patterns = GOLD_PATTERNS, heroes = { "rosette" }, probe = true }
end

-- inventory: every pattern, today's field and each key once, on paper, for
-- the table of what each pattern takes (tools/pattern-proto.sh inventory).
local Patterns = require("flora.patterns")
local ALL = {}
for _, p in ipairs(Patterns.list) do ALL[p.name] = true end
for _, k in ipairs({ "off", "core", "cells", "knobs", "crossings", "deviant", "loose" }) do
  local opts
  if k == "deviant" or k == "loose" then opts = { [k] = true } elseif k ~= "off" then opts = { gold = k } end
  variants[#variants + 1] = { name = "inventory-" .. k, set = "inventory", setup = COLOURWAY, opts = opts, patterns = ALL,
    backdrops = { "light" }, probe = true }
end

-- deviant and loose: three seeds, off and on, on the 16:9 slide.
local SEEDS = { 11, 12, 13 }
local ONE_PATTERNS = { stars_8_4 = true, kikko = true }
for _, key in ipairs({ "deviant", "loose" }) do
  for _, seed in ipairs(SEEDS) do
    for _, on in ipairs({ "off", "on" }) do
      variants[#variants + 1] = { name = string.format("%s-%s-%d", key, on, seed), set = key, setup = COLOURWAY, seed = seed,
        opts = on == "on" and { [key] = true } or nil, patterns = ONE_PATTERNS, slide = true, backdrops = { "light" } }
    end
  end
end

-- perimeter: the same keys in a 12 mm band round the paper (the hero is
-- not drawn there).
local PERIMETER = { "off", "gold-core", "gold-cells", "gold-knobs", "gold-crossings", "deviant", "loose" }
for _, k in ipairs(PERIMETER) do
  local opts
  if k:match("^gold%-") then opts = { gold = k:sub(6) } elseif k ~= "off" then opts = { [k] = true } end
  variants[#variants + 1] = { name = "perimeter-" .. k, set = "perimeter", setup = COLOURWAY .. ", perimeterwidth=12",
    layout = "perimeter", keep_text = true, opts = opts, patterns = { stars_8_4 = true, asanoha = true }, backdrops = { "light" }, probe = true }
end

return { variants = variants }
