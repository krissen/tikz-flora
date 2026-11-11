-- The running-head mark (compose.header_mark): drawn whole inside the free
-- band between its ceiling and the ink under it, or not at all; smaller
-- between MARK.min and MARK.size; and its rule giving way to a plant's foot
-- run beside it.
local H = dofile("tests/helper.lua")
local Compose = require("flora.compose")
local Frames = require("flora.frames")
local Orn = require("flora.ornaments")

local K = Compose.MARK
local W, PH = 453.54, 256.07

-- A 16:9 slide: 2.5 cm and 1 cm margins, a running head 16 pt deep.
local function slide(o)
  o = o or {}
  return {
    width = W, height = PH, header_y = o.header_y or 240.09,
    text = { x0 = 71.13, y0 = 20, x1 = 425.2, y1 = 240.09 },
    lines = o.lines or {}, running_head = o.running_head, header = o.header,
    body_top = o.body_top, stem_runs = o.runs,
  }
end
local function near(a, b) return math.abs(a - b) < 1e-6 end
-- A line of ink under the mark whose top is `y`.
local function ink(y) return { x0 = 71.13, x1 = 200, y0 = y - 10, y1 = y } end

-- The invariant over every ceiling and floor: whole inside the band, or nil.
do
  local ceilings = {
    { name = "paper edge", o = { running_head = false }, ceil = PH - K.edge },
    { name = "running head", o = { running_head = true }, ceil = 240.09 - K.head },
    { name = "legacy", o = {}, ceil = math.min(PH, 240.09 - 3 + K.size / 2) },
    { name = "page inset", o = { running_head = false }, inset = 24, ceil = PH - 24 - K.head },
    { name = "header clip", o = { running_head = true }, clip = 228.09, ceil = 228.09 - K.head },
    { name = "body top", o = { running_head = true, header = "body", body_top = 201.22 }, ceil = 201.22 - K.head },
  }
  local bands = { 0, 10, K.min - 0.01, K.min, K.min + 0.01, 20, K.size - 0.01, K.size, K.size + 0.01, 80 }
  for _, c in ipairs(ceilings) do
    for _, band in ipairs(bands) do
      local floor_ink = c.ceil - band - K.ink
      c.o.lines = { ink(floor_ink) }
      local r = Compose.header_mark(slide(c.o), c.inset, c.clip)
      local tag = string.format("%s, band %.2f", c.name, band)
      if band < K.min then
        H.check(r == nil, tag .. ": a band under the minimum must leave the mark out")
      else
        H.check(r ~= nil, tag .. ": a band of the minimum or more must hold the mark")
        if r then
          H.check(near(r.size, math.min(K.size, band)), tag .. ": size must be the band, up to the full size")
          H.check(r.y + r.size / 2 <= c.ceil + 1e-9, tag .. ": mark crosses its ceiling")
          H.check(r.y - r.size / 2 >= floor_ink + K.ink - 1e-9, tag .. ": mark reaches the ink under it")
          H.check(near(r.y + r.size / 2, c.ceil), tag .. ": mark must sit at the top of its band")
        end
      end
    end
  end
end

-- Ink that crosses the ceiling leaves no band at all; ink beside the rule's
-- span, not under it, does not count.
do
  local across = slide({ running_head = true, lines = { { x0 = 71.13, x1 = 300, y0 = 230, y1 = 245 } } })
  H.check(Compose.header_mark(across) == nil, "a frame title across the ceiling must leave the mark out")
  local aside = slide({ running_head = true, lines = { { x0 = 430, x1 = 450, y0 = 200, y1 = 245 } } })
  H.check(Compose.header_mark(aside) ~= nil, "ink right of the rule's span must not block the mark")
end

-- Callers that do not set running_head keep the mark where it always was.
do
  local r = Compose.header_mark(slide({}))
  H.check(r and near(r.y, 240.09 - 3) and near(r.size, K.size), "legacy placement must stay 3 pt under header_y")
end

-- The rule: full length with no foot run beside it; stopped short of one
-- that runs beside it; left out when too little would remain; unaffected
-- by a run that is far away or outside its span.
do
  local hx = 71.13 - 6
  local rx0 = hx + 4
  local y = PH - K.edge - K.size / 2
  local function rule(runs)
    local r = Compose.header_mark(slide({ running_head = false, runs = runs }))
    return r and r.rule, r
  end
  local free = rule({})
  H.check(free and near(free[1], rx0) and near(free[2], 425.2), "an unaccompanied rule must run to the text's right edge")
  local short = rule({ { 300, y - 10, 425, y - 3 } })
  H.check(short and near(short[2], 300 - K.stem_gap), "a rule must stop short of a foot run beside it")
  local gone, r = rule({ { 100, y - 10, 425, y - 3 } })
  H.check(gone == nil and r ~= nil, "too short a rule must be left out while the mark stays")
  local edge = rx0 + K.rule_min + K.stem_gap
  H.check(rule({ { edge, y - 10, 425, y - 3 } }) ~= nil, "a rule of exactly the minimum length must stay")
  H.check(rule({ { edge - 0.01, y - 10, 425, y - 3 } }) == nil, "a rule just under the minimum must go")
  H.check(rule({ { 100, y - K.stem - 10, 425, y - K.stem } }) ~= nil, "a run MARK.stem away is not beside the rule")
  H.check(rule({ { 100, y - K.stem - 9.99, 425, y - K.stem + 0.01 } }) == nil, "a run just inside MARK.stem is beside it")
  H.check(rule({ { 430, y - 10, 450, y - 3 } }) ~= nil, "a run right of the span must not shorten the rule")
end

-- The page's foot runs, from the frames: on a surround slide the second
-- plant's foot runs along the top, beside the rule; on a one-plant page the
-- only foot is at the bottom.
do
  local function runs(layout, inset)
    local s = slide({ running_head = false })
    s.layout, s.header, s.top_inset = layout, "margin", inset
    local frames = Frames.of(s)
    Compose.stem_runs(frames, s)
    return frames[1].spec
  end
  local sur = runs("surround", 0)
  local top
  for _, r in ipairs(sur.stem_runs) do if r[4] > PH / 2 then top = r end end
  H.check(top ~= nil, "surround: the upper plant's foot run must be found at the top")
  local r = Compose.header_mark(sur)
  H.check(r and r.stem < K.stem, "surround: the top stem runs beside the mark")
  H.check(r and (r.rule == nil or r.rule[2] <= top[1] - K.stem_gap), "surround: no rule beside the top stem")
  local left = runs("left", 0)
  H.check(#left.stem_runs == 1 and left.stem_runs[1][4] < PH / 2, "left: one foot run, at the bottom")
  local l = Compose.header_mark(left)
  H.check(l and l.rule ~= nil, "left: the rule is drawn")
end

-- Through the whole page: every mark painted lies inside the page inset.
do
  local drawn = {}
  local draw = Orn.draw
  Orn.draw = function(kind, pt, rng, box, o)
    local k = type(kind) == "string" and Orn.kinds[kind] or kind
    if k.slot == "header" then drawn[#drawn + 1] = box end
    return draw(kind, pt, rng, box, o)
  end
  for _, case in ipairs({ { 24, true }, { 0, false } }) do
    drawn = {}
    local s = slide({ running_head = case[2], lines = { ink(150) } })
    s.layout, s.header, s.seed, s.page = "surround", "margin", 3, 1
    s.tune = { gesture = { top_inset = case[1], header_clip = 1, header_gap = 12 } }
    Compose.page(s)
    H.check(#drawn == 1, string.format("inset %d: one mark expected, got %d", case[1], #drawn))
    local ceil = case[1] > 0 and PH - case[1] or PH - K.edge
    for _, b in ipairs(drawn) do
      H.check(b[4] <= ceil + 1e-9, string.format("inset %d: mark top %.2f above %.2f", case[1], b[4], ceil))
      H.check(near(b[3] - b[1], K.size), "full-size mark expected")
    end
  end
  Orn.draw = draw
end

H.done("test_header_mark")
