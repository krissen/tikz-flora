-- What falls away at the field's edge, counted on the pattern's own units
-- (pattern.lua's kept cells), for sikku_kolam, celtic_knot, celtic_panels
-- and truchet: dots with no loop round them (kolam), line ends that meet
-- no other (celtic, truchet), for each edge mode, under SETUP.
--
--   texlua tools/unit_measure.lua SPECDIR SETUP
--
-- Prints pattern, edge, kept cells, lone dots and open ends.

package.path = "./lua/?.lua;./tests/?.lua;" .. package.path
local Serial = require("flora.serial")
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Init = require("flora.init")
local Settings = require("flora.settings")
local U = dofile("tests/pattern_units.lua")

local specdir, setup = arg[1], arg[2] or ""
for _, name in ipairs({ "sikku_kolam", "celtic_knot", "celtic_panels", "truchet" }) do
  for _, edge in ipairs({ "dissolve", "cell", "fade", "border" }) do
    local f = assert(io.open(specdir .. "/spec-4.lua"))
    local spec = Serial.decode(f:read("a"))
    f:close()
    spec.seed = Init.seed("11", 4)
    local own = Settings.from_spec(spec, Settings.fresh_keys())
    own.layout = "left"
    Settings.to_spec(Settings.merge(own, Settings.parse("pattern=" .. name .. ", edge=" .. edge .. (setup ~= "" and ", " .. setup or ""))), spec)
    spec.layout = "left"
    Paint.reset_resources()
    local pt = Compose.page(spec)
    local lone, open = U.count(pt.pattern.kept, { 3, 3, spec.width - 3, spec.height - 3 })
    print(string.format("%s\t%s\t%d\t%d\t%d", name, edge, #pt.pattern.kept, lone, open))
  end
end
