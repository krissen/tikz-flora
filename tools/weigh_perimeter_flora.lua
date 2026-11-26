-- What the perimeter flora suite's sweep items weigh, for the WEIGHTS table
-- in tests/perimeter_flora_suite.lua (tests/split.lua deals the items out
-- by them):
--
--   texlua tools/weigh_perimeter_flora.lua PAPER
--
-- PAPER is one of the sweep's (16:9, 4:3, A4), or wide, for each form's cells
-- in the wide bands. Prints "sweep:PAPER WIDTH",
-- a tab and the CPU seconds the width's cells took, one line a band width.
-- Run it alone on a quiet machine, one paper at a time or the three side by
-- side, and not while other tests run: CPU time moves with load.
package.path = "./lua/?.lua;" .. package.path
local F = dofile("tests/perimeter_flora.lua")
local paper = arg[1]
if not paper then
  io.stderr:write("usage: texlua tools/weigh_perimeter_flora.lua PAPER\n")
  os.exit(2)
end
if paper == "wide" then
  for _, form in ipairs(F.FORMS) do
    local t0 = os.clock()
    F.run({ papers = {}, narrow = false, wide = { [form] = true } })
    print(string.format("wide:%s\t%.1f", form, os.clock() - t0))
  end
  os.exit(0)
end
for _, wmm in ipairs(F.WIDTHS) do
  local t0 = os.clock()
  F.run({ papers = { [paper] = true }, widths = { [wmm] = true }, narrow = false })
  print(string.format("sweep:%s %d\t%.1f", paper, wmm, os.clock() - t0))
end
