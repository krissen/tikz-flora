-- A colourway paints the same pattern roles whatever came before it and
-- whichever way it reaches the page: colourway x history (none, every
-- other colourway, a patternpalette before it) x path (one \florasetup,
-- two \florasetup calls, the mixer's preview), compared role colour by role
-- colour, with a patternpalette after the colourway still changing the
-- roles it names. The order is the later one wins: a colourway sets every
-- role (those it leaves out back to their derived colour), and a
-- patternpalette after it changes only the roles it names. Then proof that
-- the matrix fails when a colourway merges its roles over the earlier ones.
local H = dofile("tests/helper.lua")
local Settings = require("flora.settings")
local Pattern = require("flora.pattern")
local Patterns = require("flora.patterns")
local Inks = require("flora.inks")
local Mix = require("flora.mix")
local Rng = require("flora.rng")

local P = Patterns.by_name.rosette_lattice
local ROLES = { "band", "core", "fill1", "fill2", "accent", "ground", "dark" }
-- A patternpalette that sets every role apart from every colourway's.
local CUSTOM = "patternpalette={band=hoteison, core=gold, fielda=yama-budo:0.5:0.9, fieldb=ebisu, ground=none, accent=paper}"
local AFTER = "patternpalette={accent=hoteison:0.4}"

local function spec_of(set)
  local spec = { width = 300, height = 240, text = { x0 = 130, y0 = 30, x1 = 280, y1 = 210 }, seed = 7,
    layout = "left" }
  return Settings.to_spec(Settings.merge(Settings.parse("pattern=rosette_lattice, ground=on"), set), spec)
end
-- \florasetup calls one after another, as init.lua merges them.
local function tex(...)
  local set = {}
  for _, s in ipairs({ ... }) do if s ~= "" then set = Settings.merge(set, Settings.parse(s)) end end
  return spec_of(set)
end
-- The mixer's worker: its palette parts as an object (the colourway's
-- inks, as Mixer.svelte's useColourway sets them) and the setup line's
-- colour parts (setup.js colourParts; site/tests/pattern-keys.mjs holds
-- that a colourway chosen after any other gives exactly colourway=NAME).
local function worker(colours, cw)
  local spec = { width = 300, height = 240, text = { x0 = 130, y0 = 30, x1 = 280, y1 = 210 }, seed = 7,
    layout = "left" }
  spec.palette = Settings.parse("colourway=" .. cw).palette
  return Settings.pattern_preview(spec, "pattern=rosette_lattice, ground=on", colours)
end
local function roles(spec)
  local base
  Mix.with_palette(spec.palette, function() base = Pattern.role_inks(Rng.new(5):fork("pattern inks"), P, spec) end)
  local out = {}
  for _, r in ipairs(ROLES) do
    local c = base[r]
    out[r] = c and string.format("%.5f,%.5f,%.5f", c[1], c[2], c[3]) or "none"
  end
  return out
end

local function run()
  local cells, failures = 0, {}
  for _, cw in ipairs(Inks.colourway_order) do
    local way = "colourway=" .. cw
    local want = roles(tex(way))
    -- What a patternpalette after it gives: its own accent, the rest the colourway's.
    local after = roles(tex(way, AFTER))
    local accent = roles(tex(AFTER)).accent
    local histories = { { "none", "" } }
    for _, other in ipairs(Inks.colourway_order) do
      if other ~= cw then histories[#histories + 1] = { other, "colourway=" .. other } end
    end
    histories[#histories + 1] = { "patternpalette before", CUSTOM }
    for _, h in ipairs(histories) do
      local name, before = h[1], h[2]
      local paths = {
        { "one setup", tex(before ~= "" and (before .. ", " .. way) or way) },
        { "two setups", tex(before, way) },
        { "mixer", worker(way, cw) },
      }
      for _, p in ipairs(paths) do
        cells = cells + 1
        local got = roles(p[2])
        for _, r in ipairs(ROLES) do
          if got[r] ~= want[r] then
            failures[#failures + 1] = string.format("%s after %s by %s: %s is %s, not %s", cw, name, p[1], r, got[r], want[r])
          end
        end
      end
      -- A patternpalette after the colourway changes the accent, and only it.
      for _, p in ipairs({ { "one setup", tex((before ~= "" and (before .. ", ") or "") .. way .. ", " .. AFTER) },
          { "two setups", tex(before, way, AFTER) } }) do
        cells = cells + 1
        local got = roles(p[2])
        for _, r in ipairs(ROLES) do
          local w = r == "accent" and accent or want[r]
          if got[r] ~= w then
            failures[#failures + 1] = string.format("%s after %s then patternpalette by %s: %s is %s, not %s", cw, name, p[1], r, got[r], w)
          end
        end
      end
    end
    H.check(after.accent == accent and after.accent ~= want.accent, cw .. ": a patternpalette after it does not set the accent")
  end
  return cells, failures
end

local cells, failures = run()
local n = #Inks.colourway_order
H.check(cells == n * (1 + (n - 1) + 1) * (3 + 2), "colourway cells: " .. cells)
if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("colourways: %d cells, %d failures", cells, #failures)) end
for _, f in ipairs(failures) do H.check(false, f) end

-- A colourway that merges its roles over the earlier ones, as it did
-- before it reset those it leaves out: tsuki-mi's accent outlives it.
local parse = Settings.parse
Settings.parse = function(s)
  local t = parse(s)
  if t.patternpalette then
    for k, v in pairs(t.patternpalette) do if v == false then t.patternpalette[k] = nil end end
  end
  return t
end
local ok, _, fs = pcall(run)
Settings.parse = parse
H.check(ok and #fs > 0, "the colourway matrix missed a colourway that keeps an earlier one's roles")
if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation merge-roles: %d failures", ok and #fs or -1)) end

-- A preview that takes the pattern keys but not the colourway's roles, as
-- the worker did before it parsed the colour parts.
local preview = Settings.pattern_preview
Settings.pattern_preview = function(spec, pattern) return preview(spec, pattern, "") end
ok, _, fs = pcall(run)
Settings.pattern_preview = preview
H.check(ok and #fs > 0, "the colourway matrix missed a preview without the colourway's roles")
if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation preview-without-roles: %d failures", ok and #fs or -1)) end

H.done("pattern colourways")
