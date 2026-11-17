-- The pattern scale study (tools/pattern-scale.sh): what a pattern's cell
-- size is in each field today, and mock pages with the cell size set from
-- the field or the page by one of the proposals below. The engine's own
-- path is not touched: a mock sets the page's scale key (spec.pattern_scale)
-- to the factor the proposal gives, which scales the cells and the bands
-- together as the scale key does.
--
--   texlua tools/pattern_scale.lua formats
--   texlua tools/pattern_scale.lua tex FORMAT
--   texlua tools/pattern_scale.lua measure BAKE OUT.tsv
--   texlua tools/pattern_scale.lua render BAKE OUTDIR
--
-- BAKE holds <format>/spec-1.lua for each format of tools/scale_formats.lua.
--
-- Definitions (in pt unless said otherwise):
--   period  the shortest translation of the pattern's cell centres (a cell
--           kind being its outline's vertex count, or its circle's radius)
--           that maps them onto themselves, measured on the cells the
--           module lays at scale=1: its repeat along x (period_x) and along
--           y (period_y). A pattern whose colours alternate (two fields a
--           and b) may read as twice that; penrose_rhombs has no period
--           and its edge length is given; truchet's tiles turn at random
--           and its tile is given.
--   field   the strip the pattern may stand in. left and right: from the
--           paper's edge to the text block less the gap (pattern.lua's
--           GAP, 6 pt), across = that width, along = the page's height.
--           centered: the narrower of its two strips. surround: the four
--           strips round the text block (left, right, top, bottom); across
--           = the narrowest of them, along = its length. (surround also
--           fills between short lines inside the block; that is not
--           counted.) Under outer=margin each strip loses OUTER_MARGIN
--           (4 pt) at the paper's edge; the table is for bleed, the
--           default.

package.path = "./lua/?.lua;" .. package.path
local Formats = dofile("tools/scale_formats.lua")

local mode = arg[1]
local MM = 72 / 25.4
local GAP = 6

local function fmt_of(name)
  for _, f in ipairs(Formats) do if f.name == name then return f end end
  error("no format " .. tostring(name))
end

if mode == "formats" then
  for _, f in ipairs(Formats) do print(f.name) end
  os.exit(0)
end

if mode == "tex" then
  local f = fmt_of(arg[2])
  io.write(string.format([[
\documentclass[11pt]{article}
\usepackage[paperwidth=%dmm,paperheight=%dmm,left=%dmm,right=%dmm,top=%dmm,bottom=%dmm]{geometry}
\usepackage{lipsum}
\usepackage{tikzflora}
\pagestyle{empty}
\florasetup{layout=left, seed=3}
\begin{document}
%s\lipsum[1-12]
\end{document}
]], f.w, f.h, f.left, f.right, f.top, f.bottom, f.font))
  os.exit(0)
end

local Serial = require("flora.serial")
local Paint = require("flora.paint")
local Compose = require("flora.compose")
local Init = require("flora.init")
local Pdf = require("flora.pdfout")
local Settings = require("flora.settings")
local Patterns = require("flora.patterns")
local Rng = require("flora.rng")

local bake = arg[2]
local SEED = 11

local function load(fname)
  local f = assert(io.open(bake .. "/" .. fname .. "/spec-1.lua"))
  local s = Serial.decode(f:read("a"))
  f:close()
  return s
end

-- As tools/pattern_roles.lua: the baked page with its own settings less
-- its inks, then `setup`, the text moved where `layout` puts it (flush
-- with the far margin under left, the near one under right, centred
-- otherwise; the narrower margin kept).
local function page_spec(fname, layout, setup)
  local spec = load(fname)
  spec.seed = Init.seed(tostring(SEED), 1)
  local own = Settings.from_spec(spec, Settings.fresh_keys())
  own.layout, own.header = layout, spec.header
  local set = Settings.merge(own, Settings.parse(setup .. ", backdrop=light"))
  Settings.to_spec(set, spec)
  spec.layout = layout
  spec.ornaments = {}
  local t, W = spec.text, spec.width
  local m = math.min(t.x0, W - t.x1)
  local x0
  if layout == "left" then x0 = W - m - (t.x1 - t.x0)
  elseif layout == "right" then x0 = m
  else x0 = (W - (t.x1 - t.x0)) / 2 end
  local dx = x0 - t.x0
  spec.text = { x0 = t.x0 + dx, y0 = t.y0, x1 = t.x1 + dx, y1 = t.y1 }
  for _, l in ipairs(spec.lines or {}) do l.x0, l.x1 = l.x0 + dx, l.x1 + dx end
  return spec
end

-- The field's strips for `layout` on `spec`: { name, across, along }.
local function strips(spec, layout)
  local t, W, H = spec.text, spec.width, spec.height
  local L = { "left", t.x0 - GAP, H }
  local R = { "right", W - t.x1 - GAP, H }
  if layout == "left" then return { L } end
  if layout == "right" then return { R } end
  if layout == "centered" then return { L, R } end
  return { L, R, { "top", H - t.y1 - GAP, W }, { "bottom", t.y0 - GAP, W } }
end

local function narrowest(ss)
  local best = ss[1]
  for _, s in ipairs(ss) do if s[2] < best[2] then best = s end end
  return best
end

-- The strip a proposal sizes the cells by: the layout's own strip, the
-- narrower of centered's two, and surround's widest (its narrowest, the
-- top or bottom strip, is under a period wide on a slide; sizing by it
-- would shrink the whole field to fit a sliver).
local function governing(ss, layout)
  if layout ~= "surround" then return narrowest(ss) end
  local best = ss[1]
  for _, s in ipairs(ss) do if s[2] > best[2] then best = s end end
  return best
end

-- The pattern's period at scale=1, measured on its cells (see above).
local period_cache = {}
local function period(p)
  if period_cache[p.name] then return period_cache[p.name] end
  local size = p.scale
  local B = math.max(400, 14 * size)
  local env = { x0 = 0, y0 = 0, x1 = B, y1 = B, size = size, rng = Rng.new(1):fork("cells"), opts = {}, style = {},
    room = { text = { x0 = B + 100, y0 = B + 100, x1 = B + 200, y1 = B + 200 }, gap = GAP, W = B, H = B, top = B, reach = 1,
      avoid = {}, outer = "bleed" } }
  local ok, cells = pcall(p.cells, env)
  if not ok then period_cache[p.name] = { note = "cells failed: " .. tostring(cells) }; return period_cache[p.name] end
  local function kind(c)
    if c.circle then return string.format("c%.1f", c.circle.r or c.circle[3] or 0) end
    return "v" .. tostring(c.verts and #c.verts or 0)
  end
  local tol = 0.02 * size + 0.05
  local grid = {}
  local g = tol * 4
  local function gk(x, y) return math.floor(x / g) .. "," .. math.floor(y / g) end
  for _, c in ipairs(cells) do
    local k = gk(c.x, c.y)
    grid[k] = grid[k] or {}
    table.insert(grid[k], c)
  end
  local function has(x, y, kd)
    local gx, gy = math.floor(x / g), math.floor(y / g)
    for dx = -1, 1 do for dy = -1, 1 do
      for _, o in ipairs(grid[(gx + dx) .. "," .. (gy + dy)] or {}) do
        if math.abs(o.x - x) <= tol and math.abs(o.y - y) <= tol and kind(o) == kd then return true end
      end
    end end
    return false
  end
  -- The share of the inner cells that `t` maps onto a cell of their kind.
  local function score(tx, ty)
    local n, hit = 0, 0
    local m = math.sqrt(tx * tx + ty * ty) + 2 * size
    for _, c in ipairs(cells) do
      if c.x > m and c.x < B - m and c.y > m and c.y < B - m then
        n = n + 1
        if has(c.x + tx, c.y + ty, kind(c)) then hit = hit + 1 end
      end
    end
    return n > 0 and hit / n or 0, n
  end
  -- Candidate translations: from the cell nearest the box's centre to
  -- every other cell within 6 sizes.
  local c0, bd = nil, math.huge
  for _, c in ipairs(cells) do
    local d = (c.x - B / 2) ^ 2 + (c.y - B / 2) ^ 2
    if d < bd then bd, c0 = d, c end
  end
  local cand = {}
  for _, c in ipairs(cells) do
    local tx, ty = c.x - c0.x, c.y - c0.y
    local l = math.sqrt(tx * tx + ty * ty)
    if l > tol and l < 6 * size and kind(c) == kind(c0) then cand[#cand + 1] = { tx, ty, l } end
  end
  table.sort(cand, function(a, b) return a[3] < b[3] end)
  local px, py, prim, best = nil, nil, nil, 0
  for _, t in ipairs(cand) do
    local s = score(t[1], t[2])
    if s > best then best = s end
    if s >= 0.97 then
      prim = prim or t[3]
      if not px and math.abs(t[2]) <= tol and t[1] > 0 then px = t[1] end
      if not py and math.abs(t[1]) <= tol and t[2] > 0 then py = t[2] end
    end
    if px and py and prim then break end
  end
  local r = { x = px, y = py, prim = prim, cells = #cells, best = best }
  if not (px and py) then
    -- No exact repeat: the typical distance to a cell's nearest neighbour.
    local ds = {}
    for i = 1, #cells, math.max(1, #cells // 60) do
      local c, b = cells[i], math.huge
      for _, o in ipairs(cells) do
        local d = (o.x - c.x) ^ 2 + (o.y - c.y) ^ 2
        if d > 1e-6 and d < b then b = d end
      end
      ds[#ds + 1] = math.sqrt(b)
    end
    table.sort(ds)
    r.nn = ds[math.max(1, #ds // 2)]
    r.note = string.format("no repeat within 6 sizes (best share %.2f); nearest-neighbour distance used", best)
    if p.name == "penrose_rhombs" then r.nn, r.note = size, "aperiodic; its edge length (the cell size) used" end
  end
  period_cache[p.name] = r
  return r
end
local function px_of(r) return r.x or r.nn end
local function py_of(r) return r.y or r.nn end

-- The period across strip s: x for a side strip, y for a top or bottom one.
local function across_period(s, r)
  if s[1] == "top" or s[1] == "bottom" then return py_of(r) end
  return px_of(r)
end

local LAYOUTS = { "left", "right", "centered", "surround" }

-- Periods across and along a strip at scale k: a side strip's across is x,
-- a top or bottom strip's is y.
local function counts(s, r, k)
  local ax, ay = px_of(r) * k, py_of(r) * k
  if s[1] == "top" or s[1] == "bottom" then return s[2] / ay, s[3] / ax end
  return s[2] / ax, s[3] / ay
end

-- The proposals, each the scale factor k for pattern p on (format f, layout,
-- spec), with today's k = 1. REF is the reference field: the 160 x 90 mm
-- slide's left strip, where the patterns were drawn to their scale.
local ref_spec = page_spec("slide169", "left", "pattern=khatam")
local REF_ACROSS = strips(ref_spec, "left")[1][2]
local REF_SHORT = math.min(ref_spec.width, ref_spec.height)
local N_TARGET = 6

local proposals = {
  -- A: the field (its governing strip) holds N_TARGET periods, the same for every
  -- pattern.
  { name = "periods", label = "A: 6 periods across the field",
    k = function(p, spec, layout)
      local s = governing(strips(spec, layout), layout)
      return s[2] / (N_TARGET * across_period(s, period(p)))
    end },
  -- B: the pattern's own size on the reference field, scaled by the
  -- field's width against it (each pattern keeps its count of today's
  -- slide).
  { name = "refwidth", label = "B: own size x field / reference field (160 x 90 left)",
    k = function(p, spec, layout)
      local s = governing(strips(spec, layout), layout)
      return s[2] / REF_ACROSS
    end },
  -- B': as B, by the page's shorter side rather than the field.
  { name = "refpage", label = "B': own size x page's short side / 90 mm",
    k = function(p, spec, layout)
      return math.min(spec.width, spec.height) / REF_SHORT
    end },
  -- C: B rounded so the governing strip holds a whole number of periods
  -- (at least 2).
  { name = "whole", label = "C: B rounded to a whole number of periods across",
    k = function(p, spec, layout)
      local s = governing(strips(spec, layout), layout)
      local k = s[2] / REF_ACROSS
      local a = across_period(s, period(p))
      local n = math.max(2, math.floor(s[2] / (k * a) + 0.5))
      return s[2] / (n * a)
    end },
}

if mode == "measure" then
  local out = assert(io.open(arg[3], "w"))
  out:write(table.concat({ "format", "layout", "pattern", "strip", "across_mm", "along_mm", "size_pt", "period_x_pt", "period_y_pt",
    "periods_across", "periods_along", "periods_per_page_short", "strips", "note" }, "\t") .. "\n")
  local kout = assert(io.open(arg[3]:gsub("%.tsv$", "") .. "-proposals.tsv", "w"))
  kout:write("format\tlayout\tpattern\tgoverning_strip\ttoday_across")
  for _, q in ipairs(proposals) do kout:write("\t" .. q.name .. "_k\t" .. q.name .. "_across") end
  kout:write("\n")
  for _, f in ipairs(Formats) do
    for _, layout in ipairs(LAYOUTS) do
      for _, p in ipairs(Patterns.list) do
        local spec = page_spec(f.name, layout, "pattern=" .. p.name)
        local ss = strips(spec, layout)
        local s = narrowest(ss)
        local r = period(p)
        local ac, al = counts(s, r, 1)
        local short = math.min(spec.width, spec.height) / py_of(r)
        local all = {}
        for _, x in ipairs(ss) do
          local a = counts(x, r, 1)
          all[#all + 1] = string.format("%s %.1fmm %.1f", x[1], x[2] / MM, a)
        end
        out:write(string.format("%s\t%s\t%s\t%s\t%.1f\t%.1f\t%.1f\t%.2f\t%.2f\t%.2f\t%.1f\t%.1f\t%s\t%s\n",
          f.name, layout, p.name, s[1], s[2] / MM, s[3] / MM, p.scale, px_of(r), py_of(r), ac, al, short,
          table.concat(all, "; "), r.note or ""))
        local gs = governing(ss, layout)
        kout:write(string.format("%s\t%s\t%s\t%s %.1fmm\t%.2f", f.name, layout, p.name, gs[1], gs[2] / MM, (counts(gs, r, 1))))
        for _, q in ipairs(proposals) do
          local k = q.k(p, spec, layout)
          kout:write(string.format("\t%.3f\t%.2f", k, (counts(gs, r, k))))
        end
        kout:write("\n")
      end
    end
  end
  out:close()
  kout:close()
  os.exit(0)
end

local function render(spec, file)
  Paint.reset_resources()
  local ok, pt = pcall(Compose.page, spec)
  if not ok then
    io.stderr:write("FAIL " .. file .. ": " .. tostring(pt) .. "\n")
    return false
  end
  Pdf.write(file, pt, spec.width, spec.height)
  return true
end

-- The text's boxes (its lines, else the block) beside the page, for the
-- sheets to draw in place of the text: the page's size, then x0 y0 x1 y1.
local function write_text(spec, file)
  local f = assert(io.open(file, "w"))
  f:write(string.format("%.2f %.2f\n", spec.width, spec.height))
  local boxes = spec.lines and #spec.lines > 0 and spec.lines or { spec.text }
  for _, b in ipairs(boxes) do f:write(string.format("%.2f %.2f %.2f %.2f\n", b.x0, b.y0, b.x1, b.y1)) end
  f:close()
end

if mode == "render" then
  local outdir = arg[3]
  local SETUP = "colourway=tsuki-mi"
  local MOCK = { khatam = true, asanoha = true, sikku_kolam = true, celtic_knot = true }
  local MOCK_FORMATS = { slide169 = true, a4 = true, a5 = true }
  local log = assert(io.open(outdir .. "/factors.tsv", "w"))
  log:write("variant\tformat\tlayout\tpattern\tk\n")
  local function one(variant, fname, layout, p, k)
    local dir = outdir .. "/" .. variant
    os.execute("mkdir -p '" .. dir .. "'")
    local spec = page_spec(fname, layout, "pattern=" .. p.name .. ", " .. SETUP)
    if k then spec[Settings.SPEC.scale] = k * (spec[Settings.SPEC.scale] or 1) end
    local base = dir .. "/" .. fname .. "__" .. layout .. "__" .. p.name
    write_text(spec, base .. ".text")
    render(spec, base .. ".pdf")
    log:write(string.format("%s\t%s\t%s\t%s\t%.3f\n", variant, fname, layout, p.name, k or 1))
  end
  -- Today: every pattern, every format, left and surround.
  for _, f in ipairs(Formats) do
    for _, layout in ipairs({ "left", "surround" }) do
      for _, p in ipairs(Patterns.list) do one("today", f.name, layout, p, nil) end
    end
  end
  for _, q in ipairs(proposals) do
    for _, f in ipairs(Formats) do
      if MOCK_FORMATS[f.name] then
        for _, layout in ipairs({ "left", "surround" }) do
          for _, p in ipairs(Patterns.list) do
            if MOCK[p.name] then
              local spec = page_spec(f.name, layout, "pattern=" .. p.name)
              one(q.name, f.name, layout, p, q.k(p, spec, layout))
            end
          end
        end
      end
    end
  end
  log:close()
  -- The labels the sheets print.
  local lf = assert(io.open(outdir .. "/labels.txt", "w"))
  for _, q in ipairs(proposals) do lf:write(q.name .. "\t" .. q.label .. "\n") end
  for _, f in ipairs(Formats) do lf:write(f.name .. "\t" .. f.label .. "\n") end
  lf:close()
  os.exit(0)
end

error("usage: pattern_scale.lua formats | tex FORMAT | measure BAKE OUT.tsv | render BAKE OUTDIR")
