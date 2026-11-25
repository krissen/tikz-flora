-- A fingerprint of what the engine paints, page by page, for telling
-- whether a change leaves the output byte for byte as it was
-- (tools/bodies-compare.sh compares two trees; docs/testing.md).
--
--   texlua tools/bodies.lua [--fixtures DIR] SUITE...
--
-- Run from a tree's root: that tree's lua/ and tests/ are used. Prints one
-- line per page (or plan stage, or sweep cell): the suite, a name and the
-- md5 of what was painted. The suites:
--
--   bands        the perimeter band (tests/pattern_perimeter.lua's pages):
--                every pattern x edge (each and none) on the 16:9 slide
--                (light) and A4 (dark), a 12 mm band, and the slide with
--                the theme's narrow margins; every pattern on a field
--                page in three layouts x four edges; and flora in the
--                band (tests/perimeter_flora.lua's pages) on the slide and
--                A4 at 8 and 18 mm, edge none and border. 358 pages.
--   slides       four slide layouts measured by LuaLaTeX (DIR, default
--                tests/fixtures/slides) x five layouts x eight pattern
--                setups, flora (pattern=none) among them, painted one
--                after another as in one document. 160 pages.
--   progression  growth plans (flora.progression) of five layouts (flora
--                in the perimeter band among them) x three seeds, each
--                plan's eight stages. 120 bodies.
--   protect      tests/pattern_protect.lua's sweep of the small page at
--                scale 1 and 4: each cell's record and the failures.
--
-- A suite is the same in two trees when every line is.

package.path = "./lua/?.lua;" .. package.path
require("flora.tune").gilt_dpi = 100

local fixtures = "tests/fixtures/slides"
local suites = {}
local i = 1
while arg[i] do
  if arg[i] == "--fixtures" then fixtures = arg[i + 1]; i = i + 2
  else suites[#suites + 1] = arg[i]; i = i + 1 end
end
if #suites == 0 then
  io.stderr:write("usage: texlua tools/bodies.lua [--fixtures DIR] bands|slides|progression|protect ...\n")
  os.exit(2)
end

local Compose = require("flora.compose")
local Paint = require("flora.paint")
local Settings = require("flora.settings")
local Patterns = require("flora.patterns")

local function out(suite, name, text)
  io.write(suite, "\t", name, "\t", md5.sumhexa(text), "\n")
end

-- A page's body with the warnings it gave and how many cells it kept.
local function page_text(spec)
  Paint.reset_resources()
  local pt = Compose.page(spec)
  local t = { pt:body(), "--warnings" }
  for _, w in ipairs(pt.pattern_warnings or {}) do t[#t + 1] = w end
  t[#t + 1] = "kept " .. (pt.pattern and #pt.pattern.kept or 0)
  return table.concat(t, "\n")
end

local run = {}

function run.bands()
  local B = dofile("tests/pattern_perimeter.lua")
  for _, p in ipairs(Patterns.list) do
    for _, edge in ipairs(B.EDGES) do
      for k, paper in ipairs({ B.PAPERS[1], B.PAPERS[3] }) do
        local bd = k == 1 and "light" or "dark"
        out("bands", string.format("band %s %s %s", p.name, tostring(edge), paper[1]), page_text(B.spec(p.name, 12, paper, edge, bd)))
      end
    end
    local nc = B.NARROW[2]
    out("bands", "narrow " .. p.name, page_text(B.spec(p.name, nc[3], nc[2], false, "light", nc[4])))
    for _, layout in ipairs({ "left", "surround", "centered" }) do
      for _, edge in ipairs({ "cell", "fade", "dissolve", "border" }) do
        local spec = { width = 300, height = 240, text = { x0 = 130, y0 = 30, x1 = 280, y1 = 210 }, seed = 7,
          layout = layout, pattern = { [p.name] = 1 }, pattern_edge = edge }
        Settings.to_spec(Settings.merge(Settings.from_spec(spec), Settings.parse("colourway=ember, finish=filled, ground=auto, backdrop=dark")), spec)
        out("bands", string.format("field %s %s %s", p.name, layout, edge), page_text(spec))
      end
    end
  end
  -- Flora in the band: the same pages without a pattern (built from
  -- tests/pattern_perimeter.lua, which an older tree has too).
  for _, paper in ipairs({ B.PAPERS[1], B.PAPERS[3] }) do
    for _, wmm in ipairs({ 8, 18 }) do
      for _, edge in ipairs({ false, "border" }) do
        local spec = B.spec(nil, wmm, paper, edge, "light")
        spec.pattern, spec.seed = nil, 1
        out("bands", string.format("flora %s %d %s", paper[1], wmm, tostring(edge)), page_text(spec))
      end
    end
  end
end

function run.slides()
  local Serial = require("flora.serial")
  local layouts = { "left", "right", "centered", "split", "surround" }
  local setups = { "pattern=none", "pattern=kikko", "pattern=kikko, edge=border", "pattern=kikko, edge=guilloche, outer=margin",
    "pattern=celtic_knot", "pattern=sikku_kolam, backdrop=dark", "pattern=asanoha, edge=fade, hero=rosette", "pattern=stars_8_4, edge=cell" }
  for _, n in ipairs({ "m8_t0_169", "m12_t1_169", "m18_t0_43", "m12_t1_43" }) do
    for _, l in ipairs(layouts) do
      for _, s in ipairs(setups) do
        local f = assert(io.open(fixtures .. "/" .. n .. ".lua"))
        local spec = Serial.decode(f:read("a"))
        f:close()
        spec.seed = 5
        Settings.to_spec(Settings.merge(Settings.from_spec(spec), Settings.parse(s)), spec)
        spec.layout = l
        spec.ornaments = spec.ornaments or {}
        -- One page after another without resetting the PDF resources, as
        -- a document paints them: a page that leaves state behind for the
        -- next shows here.
        out("slides", string.format("%s %s %s", n, l, s), Compose.page(spec):body())
      end
    end
  end
end

function run.progression()
  local H = dofile("tests/helper.lua")
  local P = require("flora.progression")
  for _, layout in ipairs({ "left", "wreath", "surround", "title", "perimeter" }) do
    for seed = 1, 3 do
      local spec = H.page(seed, 400)
      spec.layout = layout
      local plan = P.plan(spec)
      out("progression", string.format("%s %d plan", layout, seed), string.format("%d parts %.6f", #plan.parts, plan.area))
      for k, st in ipairs(P.stages(plan, 8)) do
        out("progression", string.format("%s %d stage %d", layout, seed, k), P.render(plan, st):body())
      end
    end
  end
end

function run.protect()
  dofile("tests/helper.lua")
  local M = dofile("tests/pattern_protect.lua")
  local cells, failures = M.sweep(nil, { plan = { { 1, 1 }, { 1, 4 } }, heroes = false })
  for n, c in ipairs(cells) do
    local ks = {}
    for k, v in pairs(c) do if type(v) ~= "table" and type(v) ~= "function" then ks[#ks + 1] = k .. "=" .. tostring(v) end end
    table.sort(ks)
    out("protect", "cell " .. n, table.concat(ks, " "))
  end
  local fs = {}
  for _, f in ipairs(failures) do fs[#fs + 1] = tostring(f) end
  out("protect", "failures " .. #failures, table.concat(fs, "\n"))
end

for _, s in ipairs(suites) do
  if not run[s] then
    io.stderr:write("bodies: no suite " .. s .. "\n")
    os.exit(2)
  end
  -- Each suite starts from no PDF resources, so that what one suite
  -- registers (and a change to it) leaves the names the next one paints
  -- with as they were.
  Paint.reset_resources()
  run[s]()
end
