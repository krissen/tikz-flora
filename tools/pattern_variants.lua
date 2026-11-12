-- The colour-role variants tools/pattern_roles.lua renders: each a set of
-- role overrides (pattern.lua's M.roles, as spec.pattern_roles) and the
-- palettes it is shown in. A prototype's working list, not settings.

local Tune = require("flora.tune")
local Inks = require("flora.inks")

-- A colourway as the mixer sets it: every part at its default, then the
-- colourway's inks (or `parts`) over them.
local function palette(name, parts)
  local p = {}
  for k, v in pairs(Tune.color.palette) do p[k] = v end
  for k, v in pairs(Inks.colourways[name] or {}) do p[k] = v end
  for k, v in pairs(parts or {}) do p[k] = v end
  return p
end

local COLOUR = { { "ember", palette("ember") }, { "original", palette("original") }, { "autumn", palette("autumn") } }

-- The grey palettes (gray-palette_rapport.md, proposals A and B).
local GREY_A = { { "greyA", palette("original", { hero = "take-sumi", blooms = "grey", leaves = "grey", leaflets = "grey",
  stems = "yama-guri", sprays = "fuyu-syogun", ghost = "grey", cartouche = "take-sumi" }) } }
local GREY_B = { { "greyB", palette("original", { hero = "take-sumi", blooms = "grey-warm", leaves = "grey-cool", leaflets = "grey-cool",
  stems = "yama-guri", sprays = "fuyu-syogun", ghost = "fukagawa-nezu", cartouche = "take-sumi" }) } }

-- The fields' chroma kept (Color.ink_rgb's share) at the two V1 levels.
local S1, S2 = 0.5, 0.3
-- Where the mocks lay a ground, and its lightness there.
local GROUND = { asanoha = 0.40, sikku_kolam = 0.31, rosette_lattice = 0.80 }

local function fields(share, extra)
  local r = { a = { share = share }, b = { share = share }, ground = { share = share } }
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end

-- The ground's chroma kept: the mocks' grounds have chroma 0.01 to 0.05,
-- the hero inks about 0.2 at the grounds' lightness.
local SG = 0.2
local V2 = fields(S1, { ground = { share = SG, on = GROUND } })
local function with(base, over)
  local r = {}
  for k, v in pairs(base) do r[k] = v end
  for k, v in pairs(over) do r[k] = v end
  return r
end

return {
  S1 = S1, S2 = S2, SG = SG, GROUND = GROUND,
  variants = {
    -- The default roles: today's colours, with the corrected figure and
    -- ground of khatam, kikko, seigaiha, shippo and the rose window.
    -- Today's patterns, rendered from the tree before roles (tools/pattern-roles.sh).
    { name = "V0", palettes = COLOUR, roles = {}, before = true },
    { name = "V0f", palettes = COLOUR, roles = {} },
    { name = "V1a", palettes = COLOUR, roles = fields(S1) },
    { name = "V1b", palettes = COLOUR, roles = fields(S2) },
    { name = "V2", palettes = COLOUR, roles = V2, slide = true },
    -- The same with the ground in the leaves' ink, the bands' own, in
    -- place of the main flower's.
    { name = "V2g", palettes = COLOUR, roles = with(V2, { ground = { part = "leaves", share = SG, on = GROUND } }) },
    -- Grey A in the inks' own tone, muted toward neutral, and without gold.
    { name = "V3a", palettes = GREY_A, roles = with(V2, { a = { share = 1 }, b = { share = 1 }, ground = { share = 1, on = GROUND } }) },
    { name = "V3b", palettes = GREY_A, roles = with(V2, { band = { share = 0.3 }, a = { share = 0.3 }, b = { share = 0.3 }, ground = { share = 0.3, on = GROUND } }) },
    { name = "V3c", palettes = GREY_A, roles = with(V2, { a = { share = 1 }, b = { share = 1 }, ground = { share = 1, on = GROUND },
      accent = { part = "hero", L = 0.45, share = 1, fallback = "ink" } }) },
    { name = "V4", palettes = GREY_B, roles = with(V2, { a = { share = 1 }, b = { share = 1 }, ground = { share = 1, on = GROUND } }) },
  },
}
