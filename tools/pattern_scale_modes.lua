-- Runs a test file with the pattern drawn at another size, to compare the
-- field scale with the scale key (the field scale's ORDER-style study of
-- the invariants; tools/pattern-scale-modes.sh runs it over the tests).
--
--   texlua tools/pattern_scale_modes.lua MODE TESTFILE
--
-- MODE is `field` (the field scale as the engine has it) or keyX (the
-- field scale off and every pattern page's scale key multiplied by X,
-- key0.5 say). Run from the repository root.

package.path = "./lua/?.lua;" .. package.path
local mode, file = arg[1], arg[2]
assert(mode and file, "usage: pattern_scale_modes.lua MODE TESTFILE")
local Pattern = require("flora.pattern")
local Settings = require("flora.settings")
if mode ~= "field" then
  local x = assert(tonumber(mode:match("^key([%d.]+)$")), "MODE is field or keyX")
  Pattern.FIELD_SCALE.enabled = false
  local paint = Pattern.paint
  local done = setmetatable({}, { __mode = "k" })
  Pattern.paint = function(spec, pt)
    if not done[spec] then
      done[spec] = true
      local k = Settings.SPEC.scale
      spec[k] = (spec[k] or 1) * x
    end
    return paint(spec, pt)
  end
end
dofile(file)
