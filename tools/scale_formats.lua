-- The page formats the pattern scale study (tools/pattern-scale.sh) bakes:
-- each a paper size and a one-sided text block, in mm, with the flora's
-- margin on the left. tools/pattern_scale.lua moves the text where each
-- layout puts it (pattern_roles.lua's place_text), so only the text
-- block's width and the narrower margin matter. A working list, not
-- settings.

return {
  -- A 16:9 slide, as beamer's aspectratio=169 sets it.
  { name = "slide169", label = "160 x 90 mm", w = 160, h = 90, left = 55, right = 8, top = 10, bottom = 8, font = "\\small" },
  -- A 4:3 slide, beamer's default paper.
  { name = "slide43", label = "128 x 96 mm (4:3)", w = 128, h = 96, left = 44, right = 7, top = 10, bottom = 8, font = "\\small" },
  -- A4 portrait with tex/lorem.tex's margins.
  { name = "a4", label = "A4", w = 210, h = 297, left = 56, right = 20, top = 42, bottom = 35, font = "" },
  -- A5 portrait, its margins in A4's proportions to its width.
  { name = "a5", label = "A5", w = 148, h = 210, left = 39, right = 14, top = 30, bottom = 25, font = "" },
}
