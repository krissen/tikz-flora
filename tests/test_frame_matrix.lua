-- Every layout on every page shape: no frame may stop a compile.
--
-- The matrix crosses each layout with four page formats (A4 and A5
-- portrait, Beamer 16:9 and 4:3), three text blocks (a typical one, which
-- for paper is tests/helper.lua's off-centre A4 block and for Beamer the
-- floral theme's 2.5 cm / 1 cm margins; narrow margins; wide margins), two
-- top insets (0 and 20 pt) and three kinds of content at the top of the
-- block (a short centred title, a wide centred title, left-aligned body
-- lines). A frame whose text block falls outside it is left out of the
-- layout's list and counted in `dropped`: every cell must lay out, its
-- frames must hold their text blocks, and kept plus dropped frames must be
-- the layout's full count. The cells that drop a frame are also painted
-- (at inset 0 only, to keep the test quick): a page with a bare frame
-- still paints the rest.

local H = dofile("tests/helper.lua")
local Frames = require("flora.frames")
local Compose = require("flora.compose")
local Paint = require("flora.paint")

local MM = 72 / 25.4
local FORMATS = {
  { "a4", 595.28, 841.89 },
  { "a5", 419.53, 595.28 },
  { "beamer169", 455.24, 256.07 },
  { "beamer43", 364.19, 273.14 },
}
-- Margins left, right, top, bottom, pt.
local function blocks(name, W, Hh)
  if name:match("^beamer") then
    return {
      { "theme", 71.13, 28.45, 16, 4 },
      { "narrow", 8 * MM, 8 * MM, 8 * MM, 8 * MM },
      { "wide", 25 * MM, 25 * MM, 20 * MM, 15 * MM },
    }
  end
  return {
    { "typical", 173, W - 544 * W / 595.28, Hh - 737 * Hh / 841.89, 90 * Hh / 841.89 },
    { "narrow", 12 * MM, 12 * MM, 12 * MM, 12 * MM },
    { "wide", 40 * MM, 40 * MM, 40 * MM, 40 * MM },
  }
end
local function content(kind, t)
  local cx = (t.x0 + t.x1) / 2
  if kind == "title" then
    return {
      { x0 = cx - 35, x1 = cx + 35, y0 = t.y1 - 26, y1 = t.y1 - 16 },
      { x0 = cx - 30, x1 = cx + 30, y0 = t.y1 - 50, y1 = t.y1 - 43 },
    }
  elseif kind == "wide" then
    local w = (t.x1 - t.x0) * 0.8
    return {
      { x0 = cx - w / 2, x1 = cx + w / 2, y0 = t.y1 - 24, y1 = t.y1 - 6 },
      { x0 = cx - w / 3, x1 = cx + w / 3, y0 = t.y1 - 44, y1 = t.y1 - 34 },
    }
  end
  local ls = {}
  for i = 1, 4 do
    local y = t.y1 - 4 - i * 13.6
    ls[i] = { x0 = t.x0, x1 = t.x0 + 110, y0 = y, y1 = y + 9 }
  end
  return ls
end
-- Frames each layout asks for.
local COUNT = { left = 1, right = 1, centered = 2, split = 1, title = 2, surround = 2,
  flank = 2, wreath = 2, bouquet = 2, scrollwork = 2 }
-- The perimeter band's flora is laid out as surround.
COUNT[require("flora.band").LAYOUT] = COUNT.surround

local cells, dropped_cells, painted = 0, 0, 0
for _, lay in ipairs(Frames.order) do
  for _, fm in ipairs(FORMATS) do
    local fname, W, Hh = fm[1], fm[2], fm[3]
    for _, b in ipairs(blocks(fname, W, Hh)) do
      for _, inset in ipairs({ 0, 20 }) do
        for _, kind in ipairs({ "title", "wide", "body" }) do
          cells = cells + 1
          local cell = string.format("%s %s %s inset %d %s", lay, fname, b[1], inset, kind)
          local function spec()
            local t = { x0 = b[2], x1 = W - b[3], y1 = Hh - b[4], y0 = b[5] }
            return { width = W, height = Hh, text = t, lines = content(kind, t), seed = 3, page = 1,
              layout = lay, tune = { gesture = { top_inset = inset } } }
          end
          local ok, fs = pcall(Frames.of, spec())
          H.check(ok, cell .. ": layout failed: " .. tostring(fs))
          if ok then
            local dropped = fs.dropped or 0
            if dropped > 0 then dropped_cells = dropped_cells + 1 end
            H.check(#fs + dropped == COUNT[lay], string.format("%s: %d frames kept and %d dropped of %d",
              cell, #fs, dropped, COUNT[lay]))
            for k, f in ipairs(fs) do
              local s, t = f.spec, f.spec.text
              H.check(t and t.x0 >= 0 and t.y0 >= 0 and t.x1 <= s.width + 1e-6 and t.y1 <= s.height + 1e-6
                and t.x1 > t.x0 and t.y1 > t.y0, string.format("%s: frame %d's text block is not inside it", cell, k))
            end
            if dropped > 0 and inset == 0 then
              Paint.reset_resources()
              local good, err = pcall(Compose.page, spec())
              H.check(good, cell .. ": painting failed: " .. tostring(err))
              painted = painted + 1
            end
          end
        end
      end
    end
  end
end
-- 72 cells a layout: formats x text blocks x insets x kinds.
H.check(cells == 72 * #Frames.order, "the matrix has " .. cells .. " cells, not " .. 72 * #Frames.order)
-- The cells the crash came from must still be in the matrix.
H.check(dropped_cells > 0, "no cell drops a frame: the matrix no longer reaches the off-centre title")
print(string.format("frame matrix: %d cells, %d with a dropped frame, %d painted", cells, dropped_cells, painted))

H.done("test_frame_matrix")
