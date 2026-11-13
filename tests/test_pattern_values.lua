-- Every pattern role takes every form of value patternpalette documents,
-- and refuses the others in the parser with a message naming them: role
-- (band, core, fielda, fieldb, ground, accent) x form (ink, ink group,
-- ink:L, ink:L:share, ink::share, paper, gold, none, look, random) x
-- backdrop (light, dark). An accepted value paints a page (rosette_lattice,
-- which paints every role, with its ground and a hero) without error and
-- gives its role a colour (none: no ground); a refused one fails in
-- Settings.parse, never in the painting. Then proof that the matrix fails
-- when an ink without a lightness reaches a role without one of its own.
local H = dofile("tests/helper.lua")
local Settings = require("flora.settings")
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Color = require("flora.color")

local ROLES = { band = "band", core = "core", fielda = "fill1", fieldb = "fill2", ground = "ground", accent = "accent" }
local ORDER = { "band", "core", "fielda", "fieldb", "ground", "accent" }
local FORMS = {
  { "ink", "hoteison" }, { "group", "warm" }, { "ink:L", "hoteison:0.4" }, { "ink:L:share", "hoteison:0.4:0.5" },
  { "ink::share", "hoteison::0.5" }, { "paper", "paper" }, { "gold", "gold" }, { "none", "none" },
  { "look", "look" }, { "random", "random" },
}
-- What the parser takes, by form: every role all ink forms, paper and
-- gold; only the ground none; no role look or random (those are flora's).
local function accepted(role, form)
  if form == "look" or form == "random" then return false end
  if form == "none" then return role == "ground" end
  return true
end

local function run()
  local cells, failures, table_ = 0, {}, {}
  for _, role in ipairs(ORDER) do
    table_[role] = {}
    for _, f in ipairs(FORMS) do
      local form, value = f[1], f[2]
      for _, bd in ipairs({ "light", "dark" }) do
        cells = cells + 1
        local where = string.format("%s=%s (%s) on %s", role, value, form, bd)
        local line = "pattern=rosette_lattice, ground=on, hero=rose, backdrop=" .. bd .. ", patternpalette={" .. role .. "=" .. value .. "}"
        local ok, set = pcall(Settings.parse, line)
        if ok then
          table_[role][form] = true
          if not accepted(role, form) then failures[#failures + 1] = where .. ": accepted" end
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
          if accepted(role, form) then failures[#failures + 1] = where .. ": refused: " .. tostring(set) end
          -- A refusal is the parser's message, naming the key and the value.
          local msg = tostring(set)
          if not (msg:find("patternpalette:", 1, true) and msg:find(value, 1, true)) then
            failures[#failures + 1] = where .. ": refused without a message naming it: " .. msg
          end
        end
      end
    end
  end
  return cells, failures, table_
end

local cells, failures, forms = run()
H.check(cells == #ORDER * #FORMS * 2, "value cells: " .. cells)
for _, f in ipairs(failures) do H.check(false, f) end
if os.getenv("FLORA_MATRIX_VERBOSE") then
  print(string.format("values: %d cells, %d failures", cells, #failures))
  for _, role in ipairs(ORDER) do
    local got = {}
    for _, f in ipairs(FORMS) do if forms[role][f[1]] then got[#got + 1] = f[1] end end
    print("  " .. role .. ": " .. table.concat(got, ", "))
  end
end

-- An ink without a lightness reaching a role without one of its own, as
-- before the ink took its richest stop: core and accent fail to paint.
local ink_rgb = Color.ink_rgb
Color.ink_rgb = function(name, L, share)
  local ch, h = Color.ink_at(name, L)
  return Color.oklch(L, ch * (share or 1), h)
end
local ok, _, fs = pcall(run)
Color.ink_rgb = ink_rgb
H.check(ok and #fs > 0, "the value matrix missed an ink without a lightness")
if os.getenv("FLORA_MATRIX_VERBOSE") then print(string.format("mutation no-richest-stop: %d failures", ok and #fs or -1)) end

H.done("pattern values")
