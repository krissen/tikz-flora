-- Nothing a pattern's cell paints lies nearer the text, the hero or the
-- paper's margin than the field keeps (tests/pattern_reach.lua measures
-- the paint itself), over every pattern x ground x edge x layout x outer
-- and hero x scale, and proof that the sweep fails when the field places
-- cells by their outline alone.
local H = dofile("tests/helper.lua")
local M = dofile("tests/pattern_reach.lua")
local Patterns = require("flora.patterns")
local Pattern = require("flora.pattern")

local verbose = os.getenv("FLORA_MATRIX_VERBOSE")
local cells, failures = M.run()
if verbose then print(string.format("reach: %d cells, %d failures", #cells, #failures)) end
H.check(#cells == #Patterns.list * 2 * #M.EDGES * 2 * #M.VARIANTS * 2, "reach cells: " .. #cells)
-- At scale 3 the larger cells do not fit inside the small page's margin,
-- so some of those cells paint nothing; at scale 1 every cell paints.
local empty, empty1 = 0, 0
for _, c in ipairs(cells) do
  if c.points == 0 then
    empty = empty + 1
    if c.where:find("scale=1$") then empty1 = empty1 + 1; H.check(false, "reach cell painted nothing: " .. c.where) end
  end
end
if verbose then print(string.format("reach: %d cells paint nothing (%d at scale 1)", empty, empty1)) end
for _, f in ipairs(failures) do H.check(false, f) end

-- The field placing cells by their outline alone, as it did before their
-- ground and plates were counted: the ground squares of the dot grids
-- reach past their dots into the text.
local footprint = Pattern.footprint
Pattern.footprint = function(c) return { c } end
local ok, _, fs = pcall(M.run, function(n) return n == "sikku_kolam" or n == "rosette_lattice" end)
Pattern.footprint = footprint
H.check(ok and #fs > 0, "the reach sweep missed cells placed by their outline alone")
if verbose then print(string.format("mutation outline-only: %d failing cells", ok and #fs or -1)) end

H.done("pattern reach")
