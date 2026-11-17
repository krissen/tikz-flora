-- The field scale's invariants (pattern.lua's M.FIELD_SCALE), over every
-- pattern x page format x layout, for tests/test_pattern_matrix.lua:
--
--   periods   a field holds the same number of the pattern's cells across
--             its governing strip on every page, whatever the strip's
--             width, while the factor lies between the floor and the
--             ceiling: strip / size is the reference strip over the
--             pattern's own size on every page. Two formats with the same
--             strip give the same size.
--   bounds    below the floor (Pattern.factor_floor) the factor is the
--             floor, above the ceiling the ceiling.
--   reference a page whose governing strip is the reference is drawn
--             exactly as with the field scale off (the engine before it):
--             the same PDF, byte for byte.
--
-- M.run() returns the cells measured and the failures, as strings.

local Patterns = require("flora.patterns")
local Pattern = require("flora.pattern")
local Compose = require("flora.compose")
local Paint = require("flora.paint")
local Pdf = require("flora.pdfout")

local M = {}

-- The floor and the ceiling as the engine sets them when this file loads:
-- the checks' expectation, kept apart from the engine they check.
local FACTOR_FLOOR, CEIL = Pattern.factor_floor, Pattern.FIELD_SCALE.ceil

-- Page formats in pt (width, height), each with a text block placed for
-- the layout so that the governing strip is `strip` wide: the one strip
-- beside the text for left and right, both strips for centered, and for
-- surround the side strips with the top and foot narrower.
M.FORMATS = { { "slide", 455.24, 256.07 }, { "a4", 597.51, 845.04 }, { "a5", 421.10, 597.51 } }
M.LAYOUTS = { "left", "right", "centered", "surround" }
local GAP = 6

function M.spec(fmt, layout, strip, pattern, seed)
  local W, H = fmt[2], fmt[3]
  local m = strip + GAP
  local x0, x1
  if layout == "left" then x0, x1 = m, W - 20
  elseif layout == "right" then x0, x1 = 20, W - m
  else x0, x1 = m, W - m end
  -- The top and the foot are narrower than the sides under surround.
  local v = layout == "surround" and math.min(m * 0.5, 30) or 30
  local text = { x0 = x0, y0 = v, x1 = x1, y1 = H - v }
  return { width = W, height = H, text = text, lines = { { x0 = x0, y0 = v, x1 = x1, y1 = H - v } }, seed = seed or 7,
    layout = layout, pattern = { [pattern] = 1 } }
end

local function draw(spec)
  Paint.reset_resources()
  local pt = Compose.page(spec)
  return pt, Pdf.encode(pt, spec.width, spec.height)
end

-- The ratios of the governing strip to the reference the checks run over:
-- below the default floor, between it and the ceiling, and above it.
M.RATIOS = { 0.45, 0.7, 1, 1.3 }

function M.run(only)
  local FS = Pattern.FIELD_SCALE
  local cells, fails = {}, {}
  for _, p in ipairs(Patterns.list) do
    if not only or only[p.name] then
      local want = FS.ref / p.scale
      for _, fmt in ipairs(M.FORMATS) do
        for _, layout in ipairs(M.LAYOUTS) do
          for _, r in ipairs(M.RATIOS) do
            local spec = M.spec(fmt, layout, r * FS.ref, p.name)
            local pt = draw(spec)
            local P = pt.pattern
            if not P then
              fails[#fails + 1] = string.format("%s %s %s %.2f: no pattern painted", p.name, fmt[1], layout, r)
            else
              local lo = FACTOR_FLOOR(spec, p)
              local hi = CEIL or math.huge
              local across = r * FS.ref / P.size
              cells[#cells + 1] = { pattern = p.name, format = fmt[1], layout = layout, ratio = r, across = across,
                factor = P.factor }
              if r >= lo and r <= hi and math.abs(across - want) > 1e-9 * want then
                fails[#fails + 1] = string.format("%s %s %s %.2f: periods: %.4f cells across the strip, not %.4f",
                  p.name, fmt[1], layout, r, across, want)
              end
              local bound = (r < lo and lo) or (r > hi and hi) or nil
              if bound and math.abs(P.factor - bound) > 1e-9 then
                fails[#fails + 1] = string.format("%s %s %s %.2f: bounds: factor %.4f, not %.4f",
                  p.name, fmt[1], layout, r, P.factor, bound)
              end
            end
          end
        end
      end
      -- The reference page, with the field scale on and off.
      local spec = M.spec(M.FORMATS[1], "left", FS.ref, p.name)
      local _, on = draw(spec)
      local was = FS.enabled
      FS.enabled = false
      local _, off = draw(M.spec(M.FORMATS[1], "left", FS.ref, p.name))
      FS.enabled = was
      if on ~= off then
        fails[#fails + 1] = p.name .. ": reference: the reference page is drawn otherwise with the field scale on"
      end
    end
  end
  return cells, fails
end

return M
