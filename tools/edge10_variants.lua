-- The variants of ORDER #10's sheets (tools/edge10-sheets.sh): before and
-- after the ground, ends and panels keys, hexagram's star, and how
-- khatam's field ends. Each a \florasetup line and prototype options.

local variants = {}
local function add(name, setup, opts, patterns)
  local set = {}
  for _, p in ipairs(patterns) do set[p] = true end
  variants[#variants + 1] = { name = name, setup = setup, opts = opts, patterns = set, slide = true }
end
local AC = { "rosette_lattice", "sikku_kolam", "asanoha", "celtic_knot", "celtic_panels" }
for _, cw in ipairs({ "tsuki-mi", "ember" }) do
  add("before__" .. cw, "colourway=" .. cw .. ", ground=cells, ends=cut, panels=off", {}, AC)
  add("after__" .. cw, "colourway=" .. cw, {}, AC)
  for _, f in ipairs({ "today", "star", "interlace", "weave", "mock", "outline" }) do
    add("hex-" .. f .. "__" .. cw, "colourway=" .. cw, { hexagram = f ~= "today" and f or nil }, { "hexagram_lattice" })
  end
  for _, e in ipairs({ "cells", "shape", "panel", "inner", "fade" }) do
    add("khatam2-" .. e .. "__" .. cw, "colourway=" .. cw, { field_edge = e }, { "khatam" })
  end
end
return { variants = variants }
