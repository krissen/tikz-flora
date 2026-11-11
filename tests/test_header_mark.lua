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

-- The minimum is gesture.mark_min, 10 pt by default; a caller that wants
-- the earlier 16 pt sets it. A band between the two holds the mark only
-- under the default. Around the default: 9.99 is left out, 10 and 10.01 hold.
do
  local Tune = require("flora.tune")
  H.check(K.min == 10 and Tune.gesture.mark_min == 10, "the default minimum is 10 pt")
  for _, c in ipairs({ { 9.99, false }, { 10, true }, { 10.01, true } }) do
    local top = PH - 24 - K.head
    local r = Compose.header_mark(slide({ running_head = false, lines = { ink(top - c[1] - K.ink) } }), 24)
    H.check((r ~= nil) == c[2] and (not r or near(r.size, c[1])),
      string.format("a %.2f pt band %s the mark at the default", c[1], c[2] and "holds" or "leaves out"))
  end
  local ceil = PH - 24 - K.head
  local o = { running_head = false, lines = { ink(ceil - 14 - K.ink) } }
  local r = Compose.header_mark(slide(o), 24)
  H.check(r and near(r.size, 14) and near(r.band, 14), "a 14 pt band holds a 14 pt mark under the default")
  Tune._with({ gesture = { mark_min = 16 } }, function()
    local none, band = Compose.header_mark(slide(o), 24)
    H.check(none == nil and near(band, 14), "gesture.mark_min=16 leaves a 14 pt band empty and reports it")
  end)
  H.check(Compose.header_mark(slide(o), 24) ~= nil, "the tuned minimum is restored after the page")
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

-- A titled frame of the floral theme: header clip 12 pt under the running
-- head, top inset 20, a two-line title whose ink tops out at 219.67. The
-- header clip alone leaves 4.42 pt, under the minimum; the inset leaves
-- 12.40 pt. The plant places the mark against the inset and holds it back
-- until the clip ends.
local TWO_LINE = 219.67
do
  local inset, clip = 20, 240.09 - 12
  local o = { running_head = true, lines = { ink(TWO_LINE) } }
  local none, band = Compose.header_mark(slide(o), inset, clip)
  H.check(none == nil and math.abs(band - 4.42) < 0.01, "under the header clip the band is 4.42 pt")
  local r = Compose.header_mark(slide(o), inset, nil)
  H.check(r and math.abs(r.size - 12.40) < 0.01 and near(r.y + r.size / 2, PH - inset - K.head),
    "outside the header clip the mark fills the 12.40 pt band under the inset")
  -- A first title line with a taller glyph (an accented capital) raises the
  -- ink. At the default the mark stays for ink up to 2.40 pt higher than
  -- TWO_LINE (band 10.00); at 2.50 pt higher the band is 9.90 and it goes.
  -- In the floral theme's title an accented capital raises the ink by about
  -- 1.25 pt, since the title block is centred on its own height.
  local tall = Compose.header_mark(slide({ running_head = true, lines = { ink(TWO_LINE + 2.40) } }), inset, nil)
  H.check(tall and math.abs(tall.size - 10.00) < 0.01, "a two-line title 2.40 pt taller keeps a 10.00 pt mark")
  local taller, b = Compose.header_mark(slide({ running_head = true, lines = { ink(TWO_LINE + 2.50) } }), inset, nil)
  H.check(taller == nil and math.abs(b - 9.90) < 0.01, "2.50 pt taller leaves a 9.90 pt band, under the default")
end

-- Through Compose.page: the mark of a titled frame is painted once, after the
-- header clip has ended (only the page inset's clip is open), whole under the
-- inset and above the title's ink, in the page's ornaments group. The held
-- marks belong to the painter, so the painter returned has none left and a
-- second page, composed next, paints only its own mark. An untitled page has
-- no header clip and paints its mark among its plant's ornaments, inside the
-- plant's own frame as before.
local function titled(layout, title_top, frametitle, seed)
  local s = slide({ running_head = true, lines = { ink(title_top) } })
  s.layout, s.header, s.seed, s.page, s.frametitle = layout, "margin", seed or 3, 1, frametitle
  s.tune = { gesture = { top_inset = 20, header_clip = 1, header_gap = 12 } }
  return s
end
local function marks(spec)
  local drawn = {}
  local draw = Orn.draw
  local hero = require("flora.flower").hero
  local hero_clips
  require("flora.flower").hero = function(pt, ...)
    hero_clips = hero_clips or pt.clips
    return hero(pt, ...)
  end
  Orn.draw = function(kind, pt, rng, box, o)
    local k = type(kind) == "string" and Orn.kinds[kind] or kind
    if k.slot == "header" then
      local pj = pt:_pj()
      local x0, y0 = box[1], box[2]
      local x1, y1 = box[3], box[4]
      if pj then x0, y0 = pj(x0, y0); x1, y1 = pj(x1, y1) end
      drawn[#drawn + 1] = { box = { math.min(x0, x1), math.min(y0, y1), math.max(x0, x1), math.max(y0, y1) },
        clips = pt.clips, group = pt.group and pt.group.tag, held = pt.held_marks ~= nil }
    end
    return draw(kind, pt, rng, box, o)
  end
  local ok, pt = pcall(Compose.page, spec)
  Orn.draw = draw
  require("flora.flower").hero = hero
  assert(ok, pt)
  return drawn, pt, hero_clips
end
for _, layout in ipairs({ "surround", "left" }) do
  for _, form in ipairs({ { "one-line", 210.60 }, { "subtitle", 217.88 }, { "two-line", TWO_LINE } }) do
    local tag = layout .. ", " .. form[1]
    local drawn, pt, hero_clips = marks(titled(layout, form[2], true))
    H.check(#drawn == 1, tag .. ": one mark expected, got " .. #drawn)
    local d = drawn[1]
    if d then
      local size = d.box[4] - d.box[2]
      local band = PH - 20 - K.head - (form[2] + K.ink)
      H.check(math.abs(size - math.min(K.size, band)) < 1e-6, string.format("%s: mark %.2f for a band of %.2f", tag, size, band))
      H.check(d.box[4] <= PH - 20 - K.head + 1e-6, tag .. ": mark crosses the page inset")
      H.check(d.box[2] >= form[2] + K.ink - 1e-6, tag .. ": mark reaches the title's ink")
      H.check(d.box[4] > 240.09 - 12, tag .. ": the mark should rise above the header clip")
      H.check(d.clips == 1 and hero_clips and hero_clips > d.clips, string.format(
        "%s: the mark must paint outside the header clip (%s clips, the hero %s)", tag, d.clips, hero_clips))
      H.check(d.group == "ornaments" and not d.held, tag .. ": painted in the ornaments group after the clip ended")
    end
    H.check(pt.held_marks == nil, tag .. ": the painter keeps no held marks")
  end
  -- Untitled: no header clip, the mark paints among the plant's ornaments.
  local drawn, _, hero_clips = marks(titled(layout, 150, nil))
  H.check(#drawn == 1 and drawn[1].clips == 1 and hero_clips == 1 and not drawn[1].held,
    layout .. ", untitled: one mark painted inside the plant's clips, as before")
end
-- Two compositions in one run: what the first held back cannot reach the
-- second.
do
  local first = marks(titled("surround", TWO_LINE, true, 3))
  local second = marks(titled("surround", 150, nil, 7))
  local third = marks(titled("surround", 210.60, true, 7))
  H.check(#first == 1 and #second == 1 and #third == 1, "each page paints exactly its own mark")
  H.check(second[1] and second[1].box[4] - second[1].box[2] == K.size, "the untitled page's mark is full size")
  H.check(third[1] and near(third[1].box[4] - third[1].box[2], PH - 20 - K.head - 210.60 - K.ink),
    "the third page's mark fits its own one-line title, not the first page's two-line one")
end

-- Growth (Progression.plan): the held mark becomes one ornament part, born
-- with the other ornaments that have no anchor (0.82), and its masks are the
-- clips open when it is painted: the page inset's, not the header clip.
do
  local Progression = require("flora.progression")
  local spec = titled("surround", TWO_LINE, true)
  local drawn
  local draw = Orn.draw
  Orn.draw = function(kind, pt, rng, box, o)
    local k = type(kind) == "string" and Orn.kinds[kind] or kind
    if k.slot == "header" and pt.progression and pt.progression.active then
      drawn = pt.progression.active
    end
    return draw(kind, pt, rng, box, o)
  end
  local ok, plan = pcall(Progression.plan, spec)
  Orn.draw = draw
  assert(ok, plan)
  H.check(drawn ~= nil, "growth: the mark is a progression part")
  if drawn then
    H.check(drawn.kind == "ornaments" and near(drawn.birth, 0.82), string.format(
      "growth: the mark is an ornament part born at 0.82 (got %s at %s)", tostring(drawn.kind), tostring(drawn.birth)))
    -- The masks lead the part's chunks: the inset's clip path, then a
    -- reserve mask for the title line its padded bounds touch. None is the
    -- header clip's path.
    local BP = 72 / 72.27
    local inset_y = string.format(" %.2f l", (PH - 20) * BP)
    local clip_y = string.format(" %.2f l", (240.09 - 12) * BP)
    local masks, inset_mask, header_mask = 0, false, false
    for _, c in ipairs(drawn.chunks) do
      if type(c) ~= "string" or not c:match("W%*? n$") then break end
      masks = masks + 1
      if c:find(inset_y, 1, true) then inset_mask = true end
      if c:find(clip_y, 1, true) then header_mask = true end
    end
    H.check(inset_mask and not header_mask, string.format(
      "growth: the mark's part is masked by the page inset and not the header clip (%d masks)", masks))
    H.check(drawn.bounds and drawn.bounds[4] > 240.09 - 12, "growth: the mark's part rises above the header clip")
  end
end

-- Marks placed and painted on their own (C.mark_layout, C.header_marks and
-- spec.marks_only), for a page that shows a drawing shared with other
-- pages: placed as C.page would place them from the page's own lines, and
-- painted alone in the same place, clips and kind as on the full page.
do
  local Serial = require("flora.serial")
  local function page_spec(layout, header, top, frametitle, seed)
    local s = slide({ running_head = true, header = header,
      lines = { ink(top), { x0 = 71.13, x1 = 300, y0 = 90, y1 = 100 } } })
    s.layout, s.seed, s.page, s.frametitle = layout, seed or 3, 1, frametitle
    if header == "body" then s.body_top = frametitle and top + 6 or s.text.y1 end
    s.tune = { gesture = { top_inset = 20, header_clip = 1, header_gap = 12 } }
    return s
  end
  -- Each header mark C.page paints: kind, page box, clip depth.
  local function painted(spec)
    local out, heroes = {}, 0
    local draw, hero = Orn.draw, require("flora.flower").hero
    require("flora.flower").hero = function(...) heroes = heroes + 1; return hero(...) end
    Orn.draw = function(kind, pt, rng, box, o)
      local k = type(kind) == "string" and Orn.kinds[kind] or kind
      if k.slot == "header" then
        local pj = pt:_pj()
        local x0, y0, x1, y1 = box[1], box[2], box[3], box[4]
        if pj then x0, y0 = pj(x0, y0); x1, y1 = pj(x1, y1) end
        out[#out + 1] = string.format("%s %.6f %.6f %.6f %.6f clips %d", k.name,
          math.min(x0, x1), math.min(y0, y1), math.max(x0, x1), math.max(y0, y1), pt.clips or 0)
      end
      return draw(kind, pt, rng, box, o)
    end
    local ok, pt = pcall(Compose.page, spec)
    Orn.draw, require("flora.flower").hero = draw, hero
    assert(ok, pt)
    return out, pt, heroes
  end
  local forms = { { "one-line", 210.60, true }, { "two-line", TWO_LINE, true }, { "untitled", 150, nil } }
  for _, layout in ipairs({ "left", "surround", "right", "centered", "split" }) do
    for _, header in ipairs({ "margin", "body" }) do
      for _, form in ipairs(forms) do
        local tag = string.format("%s, %s, %s", layout, header, form[1])
        local spec = page_spec(layout, header, form[2], form[3])
        local before = Serial.encode(spec)
        local marks, cut = Compose.header_marks(spec)
        H.check(Serial.encode(spec) == before, tag .. ": placing the marks must not change the spec")
        local full = painted(page_spec(layout, header, form[2], form[3]))
        H.check(#marks == #full, string.format("%s: %d marks placed, %d painted on the page", tag, #marks, #full))
        -- Painted alone, the marks match the full page's: kind, box, clips.
        local alone_spec = page_spec(layout, header, form[2], form[3])
        alone_spec.marks_only = marks
        local alone, pt, heroes = painted(alone_spec)
        H.check(table.concat(alone, "; ") == table.concat(full, "; "),
          tag .. ": marks painted alone must match the page's\n  " .. table.concat(full, "; ") .. "\n  " .. table.concat(alone, "; "))
        H.check(heroes == 0, tag .. ": painting the marks alone grows no plant")
        for _, b in ipairs(pt.boxes) do
          H.check(b.tag == "ornaments", tag .. ": marks alone paint only the ornaments group, not " .. tostring(b.tag))
        end
        -- The cut lines place the same marks; the body line far below is cut.
        local again = Compose.header_marks(page_spec(layout, header, form[2], form[3]))
        local recut = page_spec(layout, header, form[2], form[3])
        recut.lines = cut
        H.check(Serial.encode(Compose.header_marks(recut)) == Serial.encode(marks), tag .. ": the cut lines must place the same marks")
        H.check(Serial.encode(again) == Serial.encode(marks), tag .. ": placing is repeatable")
        for _, l in ipairs(cut) do
          H.check(l.y1 > 100, tag .. ": the body line far under the mark must be cut")
        end
      end
    end
  end
  -- One layout serves every page that differs only in its lines.
  do
    local layout = Compose.mark_layout(page_spec("surround", "margin", 150, true))
    for _, form in ipairs(forms) do
      local spec = page_spec("surround", "margin", form[2], true)
      H.check(Serial.encode((layout:place(spec.lines))) == Serial.encode((Compose.header_marks(spec))),
        "a shared layout must place " .. form[1] .. " lines as a fresh one does")
    end
  end
  -- A reused drawing keeps the whole text block clear as one line, which
  -- crosses every ceiling: no mark of its own. The page's own lines placed
  -- through the drawing's layout give the page its mark; a line across the
  -- ceiling is kept by the cut and still leaves the mark out.
  do
    local drawing = page_spec("surround", "margin", 210.60, true)
    local t = drawing.text
    drawing.lines = { { x0 = t.x0, y0 = t.y0, x1 = t.x1, y1 = t.y1 } }
    H.check(#Compose.header_marks(drawing) == 0, "a drawing kept clear of the whole text block has no mark")
    local layout = Compose.mark_layout(drawing)
    local marks = layout:place({ ink(210.60) })
    H.check(#marks == 1 and near(marks[1].size, PH - 20 - K.head - 210.60 - K.ink),
      "the page's own one-line title places its mark through the drawing's layout")
    local across = { x0 = 71.13, x1 = 300, y0 = 230, y1 = 245 }
    local none, cut = layout:place({ across, ink(150) })
    H.check(#none == 0 and #cut == 1 and cut[1].y1 == 245, "ink across the ceiling is kept by the cut and leaves the mark out")
  end
  -- A mark for a frame the page does not have is refused.
  do
    local spec = page_spec("left", "margin", 150, nil)
    spec.marks_only = { { frame = 2, y = 220, size = 20 } }
    H.check(not pcall(Compose.page, spec), "marks_only must refuse a frame the page does not have")
  end
end

-- Whole or absent, against everything that can cut a painted mark: every
-- clip compose opens around a mark (the page inset, a body-mode body clip,
-- a margin-mode header clip, the reserved boxes, a frame's notch) and the
-- paper's left edge. Clipper x header mode x path (the full page, and
-- marks_only over a shared drawing): in each cell every mark painted lies,
-- with all it paints past its box (measured here, per kind), inside what
-- is shown, and no rule crosses a reserved box or the notch.
--
-- The ceiling rows (inset, body clip, header clip) hold the mark's box to
-- the ceiling, as compose places it: the compass paints a quarter of its
-- size past its box on every side and so reaches past those clips. That
-- is left as it is (pages without obstacles keep their marks exactly), so
-- those rows weigh the compass out and no row holds the compass's top to
-- them. The obstacle rows hold every kind, the compass too, to the boxes.
do
  local Paint = require("flora.paint")
  local Rng = require("flora.rng")
  local P = getmetatable(Paint.new({})).__index
  -- How far each header kind paints past its box, per side, as a share of
  -- its size.
  local over = {}
  for _, k in ipairs(Orn.of("header")) do
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    local pt = Paint.new({})
    pt.probe = function(x, y, pad)
      x0, x1 = math.min(x0, x - pad), math.max(x1, x + pad)
      y0, y1 = math.min(y0, y - pad), math.max(y1, y + pad)
    end
    Orn.draw(k, pt, Rng.new(3), { 90, 90, 110, 110 })
    over[k.name] = { math.max(0, 90 - x0) / 20, math.max(0, 90 - y0) / 20, math.max(0, x1 - 110) / 20, math.max(0, y1 - 110) / 20 }
  end
  local function base(mode, seed)
    local s = slide({ running_head = true, header = mode, lines = { ink(150) } })
    s.layout, s.seed, s.page, s.frametitle = "left", seed, 1, nil
    if mode == "body" then s.body_top = s.text.y1 end
    s.mix = { density = 0.1 }
    s.tune = { gesture = { top_inset = 20, header_clip = 1, header_gap = 12 } }
    return s
  end
  -- Each row: a name, a change to the spec, and the regions to test in page
  -- coordinates: `shown` the area a mark must stay inside, `out` boxes it
  -- must stay out of, rule boxes its rule must not cross.
  local rows = {
    { name = "reserve over the band", set = function(s) s.reserve = { { 0, PH - 48, 95, PH } } end },
    { name = "reserve beside the mark", set = function(s) s.reserve = { { 74, 214, 90, PH } } end },
    { name = "reserve across the rule", set = function(s) s.reserve = { { 150, 200, 170, PH } } end },
    { name = "reserve under the mark", set = function(s) s.reserve = { { 40, 150, 120, 222 } } end },
    { name = "notch", set = function(s) s.layout = "right"; s.clip_x1, s.clip_y1 = 30, 230 end, frame = true },
    { name = "paper edge", set = function(s) s.text.x0 = 22 end },
    -- A reserve beside the mark that only a mark under the full size
    -- clears sideways (the painted half width 0.76 s + 2 must end by 80).
    { name = "reserve that only a smaller mark clears", set = function(s) s.reserve = { { 80, 0, 90, PH } } end },
    -- A reserve over the band forces the mark down; one ending at the
    -- band's floor (152, the ink's top plus MARK.ink), or 1 pt under it,
    -- still bounds what the mark paints below its box.
    { name = "reserve ending at the floor", set = function(s) s.reserve = { { 40, 180, 90, PH }, { 40, 0, 90, 152 } } end },
    { name = "reserve ending under the floor", set = function(s) s.reserve = { { 40, 180, 90, PH }, { 40, 0, 90, 151 } } end },
    -- The ceiling is PH - 20 - MARK.head: a reserve from there up.
    { name = "reserve starting at the ceiling", set = function(s) s.reserve = { { 40, PH - 22, 90, PH } } end },
    { name = "two reserves leaving a narrow stretch", set = function(s) s.reserve = { { 40, 206, 90, PH }, { 40, 0, 90, 184 } } end },
    { name = "two reserves leaving too narrow a stretch", set = function(s) s.reserve = { { 40, 200, 90, PH }, { 40, 0, 90, 184 } } end },
    { name = "page inset", ceiling = true, set = function() end },
    { name = "body clip", ceiling = true, set = function(s) if s.header == "body" then s.body_top = 228 end end },
    { name = "header clip", ceiling = true, set = function(s) s.frametitle = true; s.header_right = 200 end },
  }
  local function shown(s)
    local top = PH - 20
    if s.header == "body" and s.body_top then top = math.min(top, s.body_top) end
    return top
  end
  local cells, failures = 0, 0
  local function cell(row, mode, path, seed)
    local s = base(mode, seed)
    row.set(s)
    if row.ceiling then s.ornaments = { compass = 0 } end
    local spec = s
    if path == "marks_only" then
      local marks = Compose.header_marks(s)
      spec = base(mode, seed); row.set(spec)
      if row.ceiling then spec.ornaments = { compass = 0 } end
      spec.marks_only = marks
    end
    local drawn, rules = {}, {}
    local draw, stroke = Orn.draw, P.stroke
    Orn.draw = function(kind, pt, rng, box, o)
      local k = type(kind) == "string" and Orn.kinds[kind] or kind
      if k.slot == "header" then
        local pj = pt:_pj()
        local x0, y0, x1, y1 = box[1], box[2], box[3], box[4]
        if pj then x0, y0 = pj(x0, y0); x1, y1 = pj(x1, y1) end
        local size, ov = math.abs(x1 - x0), over[k.name]
        -- A mirrored frame swaps left and right overshoot.
        local l, r = ov[1], ov[3]
        if x1 < x0 then l, r = r, l end
        x0, x1 = math.min(x0, x1), math.max(x0, x1)
        y0, y1 = math.min(y0, y1), math.max(y0, y1)
        drawn[#drawn + 1] = { k.name, x0 - l * size, y0 - ov[2] * size, x1 + r * size, y1 + ov[4] * size }
      end
      return draw(kind, pt, rng, box, o)
    end
    P.stroke = function(pt, paths, rgb, w, a, ...)
      if w == 0.4 and a == 0.9 and #paths == 2 and paths[1][1] == "m" and paths[2][1] == "l" then
        local pj = pt:_pj()
        local p, q = paths[1], paths[2]
        local x0, y0, x1, y1 = p[2], p[3], q[2], q[3]
        if pj then x0, y0 = pj(x0, y0); x1, y1 = pj(x1, y1) end
        if math.abs(y0 - y1) < 1e-9 then rules[#rules + 1] = { math.min(x0, x1), y0, math.max(x0, x1) } end
      end
      return stroke(pt, paths, rgb, w, a, ...)
    end
    local ok, err = pcall(Compose.page, spec)
    Orn.draw, P.stroke = draw, stroke
    assert(ok, err)
    cells = cells + 1
    if os.getenv("MARK_MATRIX_DEBUG") then
      for _, d in ipairs(drawn) do io.write(string.format("  %s %s %s %d: %s %.2f %.2f %.2f %.2f\n", row.name, mode, path, seed, d[1], d[2], d[3], d[4], d[5])) end
      for _, r in ipairs(rules) do io.write(string.format("  %s %s %s %d: rule %.2f..%.2f at %.2f\n", row.name, mode, path, seed, r[1], r[3], r[2])) end
    end
    local tag = string.format("%s, %s, %s, seed %d", row.name, mode, path, seed)
    local function bad(msg) failures = failures + 1; H.check(false, tag .. ": " .. msg) end
    -- The regions in page coordinates.
    local outs = {}
    for _, r in ipairs(s.reserve or {}) do outs[#outs + 1] = r end
    if row.frame then
      -- The right layout's frame mirrors x: its notch's corner on the page.
      outs[#outs + 1] = { 0, 0, W - s.clip_x1, s.clip_y1 }
    end
    local top = shown(s)
    if row.name == "header clip" and mode == "body" then top = math.min(top, 240.09 - 12) end
    for _, d in ipairs(drawn) do
      local name, x0, y0, x1, y1 = d[1], d[2], d[3], d[4], d[5]
      if x0 < 0 or x1 > W then bad(string.format("%s crosses the paper's edge (%.2f..%.2f)", name, x0, x1)) end
      if y1 > top + 1e-6 and name ~= "compass" then bad(string.format("%s reaches %.2f, above the clip at %.2f", name, y1, top)) end
      for _, o in ipairs(outs) do
        if x1 > o[1] and x0 < o[3] and y1 > o[2] and y0 < o[4] then
          bad(string.format("%s (%.2f %.2f %.2f %.2f) meets the box %.2f %.2f %.2f %.2f", name, x0, y0, x1, y1, o[1], o[2], o[3], o[4]))
        end
      end
    end
    for _, r in ipairs(rules) do
      for _, o in ipairs(outs) do
        if r[3] > o[1] and r[1] < o[3] and r[2] > o[2] and r[2] < o[4] then
          bad(string.format("the rule at %.2f crosses the box %.2f %.2f %.2f %.2f", r[2], o[1], o[2], o[3], o[4]))
        end
      end
    end
    return #drawn
  end
  local placed = 0
  for _, row in ipairs(rows) do
    for _, mode in ipairs({ "margin", "body" }) do
      for _, path in ipairs({ "full", "marks_only" }) do
        for _, seed in ipairs(path == "full" and { 1 } or { 1, 2, 4, 7 }) do
          placed = placed + cell(row, mode, path, seed)
        end
      end
    end
  end
  H.check(placed > cells / 2, string.format("the matrix must place marks, not only leave them out (%d in %d cells)", placed, cells))
  print(string.format("whole-or-absent matrix: %d cells, %d marks, %d failures", cells, placed, failures))
  -- Beside an obstacle the place does not depend on the kind: seeds whose
  -- marks are a compass, a rosette, a sunburst and a quatrefoil place them
  -- alike, so a shared drawing's kind lands where the page's own would.
  for _, row in ipairs(rows) do
    if not row.ceiling then
      local first
      for _, seed in ipairs({ 1, 2, 4, 7 }) do
        local s = base("margin", seed)
        row.set(s)
        local key = require("flora.serial").encode((Compose.header_marks(s)))
        first = first or key
        H.check(key == first, row.name .. ": the mark's place must not depend on its kind (seed " .. seed .. ")")
      end
    end
  end
end

-- The placement is exact in both dimensions. A mark of size s whose box top
-- is t paints, with the largest reach of any header kind, over its box
-- widened by reach * s + MARK.head on every side; that must meet no
-- obstacle, wherever the obstacle lies (beside the mark, under the band's
-- floor, over its ceiling), and stay MARK.head inside the paper's left edge.
local REACH = 0
for _, k in ipairs(Orn.of("header")) do REACH = math.max(REACH, k.reach or 0) end
local function whole(s, t, hx, ceil, lo, obstacles, tol)
  tol = tol or 1e-6
  if s < K.min - tol or s > K.size + tol or t > ceil + tol or t - s < lo - tol then return false end
  if hx - (0.5 + REACH) * s < K.head - tol then return false end
  local e = REACH * s + K.head
  local x0, x1, y0, y1 = hx - s / 2 - e, hx + s / 2 + e, t - s - e, t + e
  for _, o in ipairs(obstacles) do
    if o[3] > x0 + tol and o[1] < x1 - tol and o[4] > y0 + tol and o[2] < y1 - tol then return false end
  end
  return true
end

-- The two cases from review, with text.x0 = 71 (the mark's centre at 65)
-- and a free band from 152 to 238.
do
  local function place(reserve)
    local s = slide({ running_head = true, header_y = 240, lines = { { x0 = 71, x1 = 200, y0 = 140, y1 = 150 } } })
    s.text.x0, s.text.y1, s.reserve = 71, 240, reserve
    return Compose.header_mark(s)
  end
  -- A reserve beside the mark, across the whole band: the full size meets
  -- it, but a mark up to (80 - 2 - 65) / 0.76 = 17.11 pt clears it.
  local side = { { 80, 0, 90, 256 } }
  local r = place(side)
  H.check(r ~= nil, "a reserve beside the mark that a smaller mark clears must not leave the mark out")
  if r then
    H.check(math.abs(r.size - (80 - K.head - 65) / (0.5 + REACH)) < 1e-6 and r.size >= 16,
      string.format("beside the reserve the mark is as large as clears it (%.3f)", r.size))
    H.check(whole(r.size, r.y + r.size / 2, 65, 238, 152, side), "the mark beside the reserve is whole")
  end
  -- A reserve over the band and one ending 1 pt under its floor: what the
  -- mark paints under its box must clear the lower one too, so the mark is
  -- (180 - 151 - 2 * 2) / 1.52 = 16.45 pt, not 20.63.
  local both = { { 40, 180, 90, 256 }, { 40, 0, 90, 151 } }
  r = place(both)
  H.check(r ~= nil, "a stretch between two reserves that holds a mark must hold it")
  if r then
    H.check(math.abs(r.size - (180 - 151 - 2 * K.head) / (1 + 2 * REACH)) < 1e-6,
      string.format("between the reserves the mark is as large as clears both (%.3f)", r.size))
    H.check(r.y - r.size / 2 - REACH * r.size - K.head >= 151 - 1e-6, string.format(
      "the mark paints down to %.2f, into the reserve ending at 151", r.y - r.size / 2 - REACH * r.size))
    H.check(whole(r.size, r.y + r.size / 2, 65, 238, 152, both), "the mark between the reserves is whole")
  end
end

-- Cross-check against an exhaustive search: for random obstacle sets, a
-- grid over sizes and box tops (0.25 pt) finds a whole placement only if
-- header_mark returns one; the one it returns is whole, at least as large
-- as any the grid finds, and the highest of its size.
do
  local seed = 20261111
  local function rnd(a, b)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return a + (b - a) * seed / 2147483648
  end
  local SETS, STEP = 500, 0.25
  local found, returned, witnessed, failures = 0, 0, 0, 0
  for n = 1, SETS do
    local x0 = rnd(24, 90)
    local ink_top = rnd(150, 226)
    local obstacles = {}
    for _ = 1, math.floor(rnd(1, 4)) do
      local ox, oy = rnd(0, 120), rnd(100, PH)
      obstacles[#obstacles + 1] = { ox, oy, ox + rnd(4, 60), math.min(PH, oy + rnd(4, 80)) }
    end
    local s = slide({ running_head = true, lines = { { x0 = x0, x1 = 200, y0 = ink_top - 10, y1 = ink_top } } })
    s.text.x0, s.reserve = x0, obstacles
    local r = Compose.header_mark(s)
    local hx, ceil, lo = x0 - 6, 240.09 - K.head, ink_top + K.ink
    local best
    if ceil - lo >= K.min then
      local sizes = {}
      for z = K.min, math.min(K.size, ceil - lo), STEP do sizes[#sizes + 1] = z end
      sizes[#sizes + 1] = math.min(K.size, ceil - lo)
      for i = #sizes, 1, -1 do
        local z = sizes[i]
        local t = ceil
        while t - z >= lo - 1e-9 do
          if whole(z, t, hx, ceil, lo, obstacles) then best = z; break end
          t = t - STEP
        end
        if best then break end
      end
    end
    local tag = string.format("random set %d (x0 %.2f, ink %.2f, %d obstacles)", n, x0, ink_top, #obstacles)
    local function bad(msg) failures = failures + 1; H.check(false, tag .. ": " .. msg) end
    if best then found = found + 1 end
    if r then
      returned = returned + 1
      local top = r.y + r.size / 2
      if not whole(r.size, top, hx, ceil, lo, obstacles) then bad(string.format("the mark %.3f at %.3f is not whole", r.size, top)) end
      if best and r.size < best - 1e-6 then bad(string.format("a %.3f pt mark, though %.3f pt fits", r.size, best)) end
      local t = ceil
      while t > top + 1e-6 do
        if whole(r.size, t, hx, ceil, lo, obstacles) then bad(string.format("a box top at %.3f is free, above %.3f", t, top)); break end
        t = t - STEP
      end
      if not best then witnessed = witnessed + 1 end
    elseif best then
      bad(string.format("no mark, though a %.3f pt one fits", best))
    end
  end
  H.check(found > SETS / 4 and found < SETS, string.format("the random sets must hold marks and leave some out (%d of %d)", found, SETS))
  print(string.format("brute-force cross-check: %d sets, grid finds %d, header_mark returns %d (%d finer than the grid), %d failures",
    SETS, found, returned, witnessed, failures))
end

H.done("test_header_mark")
