-- The original ornaments, as registry kinds: the night-sky star cartouche,
-- the compass at the running head and the knot pendant (ornament.lua).

local Orn = require("flora.ornaments")
local O = require("flora.ornament")

Orn.register({
  name = "night", slot = "cartouche", label = "Night sky",
  draw = function(pt, rng, b)
    O.panel(pt, rng, b[1], b[2], b[3] - b[1], b[4] - b[2])
  end,
})

-- The compass's crosshair reaches HAIR times the star's radius. The star is
-- sized so the crosshair, its stroke's half width (O.compass draws it
-- HAIR_WIDTH pt wide) included, ends at the box's edge: the whole figure
-- paints inside its box, as the other running-head marks do.
local HAIR, HAIR_WIDTH = 1.3, 0.22
Orn.register({
  name = "compass", slot = "header", label = "Compass star",
  draw = function(pt, _, b)
    local half = (b[3] - b[1]) / 2
    O.compass(pt, (b[1] + b[3]) / 2, (b[2] + b[4]) / 2, (half - HAIR_WIDTH / 2) / HAIR, { hair = HAIR })
  end,
})

-- The cord runs up o.cord pt from the pendant's top.
Orn.register({
  name = "knot", slot = "pendant", label = "Knot pendant",
  draw = function(pt, rng, b, o)
    O.pendant(pt, rng, (b[1] + b[3]) / 2, (b[2] + b[4]) / 2, b[3] - b[1], b[4] - b[2], o.cord or 0)
  end,
})
