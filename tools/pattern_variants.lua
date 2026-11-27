-- The pattern variants tools/pattern_roles.lua renders: each a \florasetup
-- key list laid over the page, rendered on paper and on the dark backdrop.
-- `slide` renders it on the 160 x 90 mm page too. A working list for
-- comparison sheets, not settings. A variant with a `set` belongs to a
-- touches sheet (tools/pattern-touches.sh) and is rendered only when that
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

-- The touch sets (lua/flora/pattern_touches.lua's settings), one variant per
-- setting, laid out by tools/pattern-touches.sh.
local COLOURWAY = "colourway=original"

-- gold: where the gold lies, on the same field and hero (paper and dark).
local GLINTS = { off = "", on = ", glint=on", core = ", glint=core", cells = ", glint=cells", knobs = ", glint=knobs" }
local GLINT_ORDER = { "off", "on", "core", "cells", "knobs" }
local GOLD_PATTERNS = { stars_8_4 = true, overlapping_circles = true, celtic_knot = true, asanoha = true }
for _, g in ipairs(GLINT_ORDER) do
  variants[#variants + 1] = { name = "gold-" .. g, set = "gold", setup = COLOURWAY .. GLINTS[g],
    patterns = GOLD_PATTERNS, heroes = { "rosette" }, probe = true }
end
variants[#variants + 1] = { name = "gold-hero", set = "gold", setup = COLOURWAY .. ", herogilding=on",
  patterns = GOLD_PATTERNS, heroes = { "rosette" }, probe = true }

-- inventory: every pattern, today's field and each key once, on paper, for
-- the table of what each pattern takes (tools/pattern-touches.sh inventory).
local Patterns = require("flora.patterns")
local ALL = {}
for _, p in ipairs(Patterns.list) do ALL[p.name] = true end
for _, k in ipairs({ "off", "on", "core", "cells", "knobs", "deviant", "stray" }) do
  local extra = ""
  if k == "deviant" or k == "stray" then extra = ", " .. k .. "=on" else extra = GLINTS[k] end
  variants[#variants + 1] = { name = "inventory-" .. k, set = "inventory", setup = COLOURWAY .. extra, patterns = ALL,
    backdrops = { "light" }, probe = true }
end

-- deviant (off, on, 3) and stray (off, on): three seeds, on the 16:9 slide.
local SEEDS = { 11, 12, 13 }
local ONE_PATTERNS = { stars_8_4 = true, kikko = true }
for _, key in ipairs({ "deviant", "stray" }) do
  for _, seed in ipairs(SEEDS) do
    for _, on in ipairs(key == "deviant" and { "off", "on", "3" } or { "off", "on" }) do
      variants[#variants + 1] = { name = string.format("%s-%s-%d", key, on, seed), set = key,
        setup = COLOURWAY .. (on ~= "off" and (", " .. key .. "=" .. on) or ""), seed = seed,
        patterns = ONE_PATTERNS, slide = true, backdrops = { "light" } }
    end
  end
end

-- perimeter: the keys in a 12 mm band round the paper, a corner and a side
-- in close-up (the hero is not drawn there).
local PERIMETER = { off = "", glint = ", glint=on", knobs = ", glint=knobs", cells = ", glint=cells", deviant = ", deviant=on", deviant3 = ", deviant=3", stray = ", stray=on" }
local PERIMETER_ORDER = { "off", "glint", "knobs", "cells", "deviant", "deviant3", "stray" }
for _, k in ipairs(PERIMETER_ORDER) do
  variants[#variants + 1] = { name = "perimeter-" .. k, set = "perimeter", setup = COLOURWAY .. ", perimeterwidth=12" .. PERIMETER[k],
    layout = "perimeter", keep_text = true, patterns = { stars_8_4 = true, asanoha = true }, backdrops = { "light" }, probe = true }
end

return { variants = variants }
