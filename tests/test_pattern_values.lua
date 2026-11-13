-- Every pattern role takes every form of value patternpalette documents,
-- refuses the others in the parser with a message naming them, and every
-- part of a value it takes reaches the painting.
--
-- forms   role (band, core, fielda, fieldb, ground, accent) x form (ink,
--         ink group, ink:L, ink:L:share, ink::share, paper, gold, none,
--         look, random, and the malformed: too many colons, empty parts,
--         a lightness or share that is no number or lies outside 0 to 1,
--         an unknown ink or group) x backdrop (light, dark). An accepted
--         value paints a page (rosette_lattice, which paints every role,
--         with its ground and a hero) without error and gives its role a
--         colour (none: no ground); a refused one fails in Settings.parse
--         with its message, never with a Lua error and never in the
--         painting.
-- parts   pattern x each role it paints x each part of the value (ink, L,
--         share): changing that part alone changes the role's colour and
--         the painted page, and the role is painted at the lightness the
--         value gives (the band before a dark ground lifts it). At
--         scale 2, since at scale 1 some bands are too narrow for their
--         core or accent line to be drawn (pat_kit.lua, K.CORE_MIN).
--
-- Then proof that the matrix fails when each fault is put back into the
-- source: an ink without a lightness reaching a role without one of its
-- own, the pattern's ground lightness winning over the palette's, and the
-- parser taking a value it cannot split.
local H = dofile("tests/helper.lua")
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Color = require("flora.color")
local Patterns = require("flora.patterns")

local verbose = os.getenv("FLORA_MATRIX_VERBOSE")
local ROLES = { band = "band", core = "core", fielda = "fill1", fieldb = "fill2", ground = "ground", accent = "accent" }
local ORDER = { "band", "core", "fielda", "fieldb", "ground", "accent" }
local FORMS = {
  { "ink", "hoteison" }, { "group", "warm" }, { "ink:L", "hoteison:0.4" }, { "ink:L:share", "hoteison:0.4:0.5" },
  { "ink::share", "hoteison::0.5" }, { "paper", "paper" }, { "gold", "gold" }, { "none", "none" },
  { "look", "look" }, { "random", "random" },
  { "three colons", "hoteison:0.4:0.5:0.1", true }, { "only colons", "hoteison:::", true },
  { "empty L", "hoteison:", true }, { "empty L and share", "hoteison::", true }, { "no ink", ":0.4", true },
  { "L not a number", "hoteison:dark", true }, { "share not a number", "hoteison::half", true },
  { "L above 1", "hoteison:1.5", true }, { "share below 0", "hoteison:0.4:-0.1", true },
  { "unknown ink", "nonesuch", true }, { "unknown ink with L", "nonesuch:0.4", true },
  { "paper with L", "paper:0.4", true },
}
-- What the parser takes, by form: every role all ink forms, paper and
-- gold; only the ground none; no role look or random (those are flora's)
-- nor any malformed value.
local function accepted(role, f)
  if f[3] or f[1] == "look" or f[1] == "random" then return false end
  if f[1] == "none" then return role == "ground" end
  return true
end

local function forms(Settings)
  local cells, failures, took = 0, {}, {}
  for _, role in ipairs(ORDER) do
    took[role] = {}
    for _, f in ipairs(FORMS) do
      local form, value = f[1], f[2]
      for _, bd in ipairs({ "light", "dark" }) do
        cells = cells + 1
        local where = string.format("%s=%s (%s) on %s", role, value, form, bd)
        local line = "pattern=rosette_lattice, ground=on, hero=rose, backdrop=" .. bd .. ", patternpalette={" .. role .. "=" .. value .. "}"
        local ok, set = pcall(Settings.parse, line)
        if ok then
          took[role][form] = true
          if not accepted(role, f) then failures[#failures + 1] = where .. ": accepted" end
          local spec = Settings.to_spec(set, { width = 300, height = 240, text = { x0 = 130, y0 = 30, x1 = 280, y1 = 210 },
            seed = 7, layout = "left" })
          Paint.reset_resources()
          local painted, pt = pcall(Compose.page, spec)
          if not painted then
            failures[#failures + 1] = where .. ": painting failed: " .. tostring(pt)
          else
            local c = pt.pattern and pt.pattern.inks[ROLES[role]]
            if form == "none" then
              if c then failures[#failures + 1] = where .. ": none still paints a ground" end
            elseif not c then
              failures[#failures + 1] = where .. ": the role has no colour"
            end
          end
        else
          if accepted(role, f) then failures[#failures + 1] = where .. ": refused: " .. tostring(set) end
          -- A refusal is the parser's message, naming the key and the value.
          local msg = tostring(set)
          if not (msg:find("patternpalette: ", 1, true) and msg:find("\"" .. value .. "\"", 1, true)) then
            failures[#failures + 1] = where .. ": refused without the parser's message: " .. msg
          end
        end
      end
    end
  end
  return cells, failures, took
end

-- The parts of a value, each changed alone from BASE.
local BASE = { ink = "kon-peki", L = 0.4, share = 0.6 }
local PARTS = { { "ink", { ink = "momiji" } }, { "L", { L = 0.65 } }, { "share", { share = 0.2 } } }
local KEY_OF = { band = "band", core = "core", a = "fielda", b = "fieldb", accent = "accent", ground = "ground" }
local function value(over)
  local v = {}
  for k, x in pairs(BASE) do v[k] = over[k] or x end
  return string.format("%s:%s:%s", v.ink, v.L, v.share), v.L
end
local function key(c) return c and string.format("%.5f,%.5f,%.5f", c[1], c[2], c[3]) or "none" end

local function parts(Settings, filter)
  local cells, failures = 0, {}
  for _, p in ipairs(Patterns.list) do
    if not filter or filter(p.name) then
      for _, r in ipairs(p.roles) do
        local k = KEY_OF[r]
        if k and (r ~= "ground" or p.ground) then
          local function page(v)
            local spec = Settings.to_spec(Settings.parse("pattern=" .. p.name .. ", ground=on, edge=cell, density=3, scale=2, patternpalette={"
              .. k .. "=" .. v .. "}"), { width = 300, height = 240, text = { x0 = 130, y0 = 30, x1 = 280, y1 = 210 }, seed = 7, layout = "left" })
            Paint.reset_resources()
            local pt = Compose.page(spec)
            local inks = pt.pattern.inks
            return pt:body(), r == "band" and inks.band0 or inks[ROLES[k]]
          end
          local v0, L0 = value({})
          local body0, c0 = page(v0)
          for _, part in ipairs(PARTS) do
            cells = cells + 1
            local where = string.format("%s %s: %s", p.name, k, part[1])
            local v1, L1 = value(part[2])
            local body1, c1 = page(v1)
            if key(c1) == key(c0) then failures[#failures + 1] = where .. ": the role's colour does not change" end
            if body1 == body0 then failures[#failures + 1] = where .. ": the painted page does not change" end
            for _, x in ipairs({ { c0, L0 }, { c1, L1 } }) do
              if x[1] and math.abs(Color.lightness(x[1]) - x[2]) > 0.02 then
                failures[#failures + 1] = string.format("%s: painted at L %.3f, not %.2f", where, Color.lightness(x[1]), x[2])
              end
            end
          end
        end
      end
    end
  end
  return cells, failures
end

local Settings = require("flora.settings")
local fc, ff, took = forms(Settings)
H.check(fc == #ORDER * #FORMS * 2, "value cells: " .. fc)
for _, f in ipairs(ff) do H.check(false, f) end
local pc, pf = parts(Settings)
local want = 0
for _, p in ipairs(Patterns.list) do
  for _, r in ipairs(p.roles) do if KEY_OF[r] and (r ~= "ground" or p.ground) then want = want + #PARTS end end
end
H.check(pc == want and pc > 0, "part cells: " .. pc)
for _, f in ipairs(pf) do H.check(false, f) end
if verbose then
  print(string.format("forms: %d cells, %d failures", fc, #ff))
  for _, role in ipairs(ORDER) do
    local got = {}
    for _, f in ipairs(FORMS) do if took[role][f[1]] then got[#got + 1] = f[1] end end
    print("  " .. role .. ": " .. table.concat(got, ", "))
  end
  print(string.format("parts: %d cells, %d failures", pc, #pf))
end

-- An ink without a lightness reaching a role without one of its own, as
-- before the ink took its richest stop: core and accent fail to paint.
local ink_rgb = Color.ink_rgb
Color.ink_rgb = function(name, L, share)
  local ch, h = Color.ink_at(name, L)
  return Color.oklch(L, ch * (share or 1), h)
end
local ok, _, fs = pcall(forms, Settings)
Color.ink_rgb = ink_rgb
H.check(ok and #fs > 0, "the value matrix missed an ink without a lightness")
if verbose then print(string.format("mutation no-richest-stop: %d failures", ok and #fs or -1)) end

-- A fault put back into module `mod`'s source; returns what `check(M)`
-- returns with the mutated module loaded.
local function mutated(mod, file, old, new, check)
  local f = io.open(file)
  local src = f:read("a")
  f:close()
  local i, j = src:find(old, 1, true)
  H.check(i ~= nil, "mutation: the line to put the fault back into is gone: " .. old)
  if not i then return nil end
  local real = package.loaded[mod]
  local m = assert(load(src:sub(1, i - 1) .. new .. src:sub(j + 1), "@" .. file .. " (mutated)"))()
  package.loaded[mod] = m
  local res = { pcall(check, m) }
  package.loaded[mod] = real
  if not res[1] then error(res[2], 0) end
  return table.unpack(res, 2)
end

-- The pattern's own ground lightness winning over the palette's.
local _, ground_l = mutated("flora.pattern", "lua/flora/pattern.lua",
  "role(\"ground\", R.ground.on and R.ground.on[p.name], p.ground)",
  "role(\"ground\", R.ground.on and R.ground.on[p.name] or p.ground)",
  function() return parts(Settings, function(n) return n == "asanoha" or n == "rosette_lattice" end) end)
H.check(ground_l and #ground_l > 0, "the parts matrix missed a ground lightness the palette gives and the painting drops")
-- The parser taking a value it cannot split, as before it checked the form.
local _, split = mutated("flora.settings", "lua/flora/settings.lua", "  if not name then return nil end\n", "",
  function(S) return forms(S) end)
H.check(split and #split > 0, "the forms matrix missed a parser that crashes on a value it cannot split")
if verbose then
  print(string.format("mutation ground-L-ignored: %d failures", ground_l and #ground_l or -1))
  print(string.format("mutation unsplit-value: %d failures", split and #split or -1))
end

H.done("pattern values")
