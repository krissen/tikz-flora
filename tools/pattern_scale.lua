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

if mode == "patterns" then
  package.path = "./lua/?.lua;" .. package.path
  for _, p in ipairs(require("flora.patterns").list) do print(p.name) end
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
    room = { text = { x0 = B + 100, y0 = B + 100, x1 = B + 200, y1 = B + 200 }, gap = GAP, W = B, H = B, top = B,
      reach = 1,
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
    k = function(_, spec, layout)
      local s = governing(strips(spec, layout), layout)
      return s[2] / REF_ACROSS
    end },
  -- B': as B, by the page's shorter side rather than the field.
  { name = "refpage", label = "B': own size x page's short side / 90 mm",
    k = function(_, spec)
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
  out:write(table.concat({ "format", "layout", "pattern", "strip", "across_mm", "along_mm", "size_pt",
    "period_x_pt", "period_y_pt",
    "periods_across", "periods_along", "periods_per_page_short", "strips", "note" }, "\t") .. "\n")
  local kout = assert(io.open(arg[3]:gsub("%.tsv$", "") .. "-proposals.tsv", "w"))
  kout:write("format\tlayout\tpattern\tgoverning_strip\ttoday_across")
  for _, q in ipairs(proposals) do kout:write("\t" .. q.name .. "_k\t" .. q.name .. "_across") end
  kout:write("\n")
  for _, f in ipairs(Formats) do if not f.study then
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
        kout:write(string.format("%s\t%s\t%s\t%s %.1fmm\t%.2f", f.name, layout, p.name, gs[1], gs[2] / MM,
          (counts(gs, r, 1))))
        for _, q in ipairs(proposals) do
          local k = q.k(p, spec, layout)
          kout:write(string.format("\t%.3f\t%.2f", k, (counts(gs, r, k))))
        end
        kout:write("\n")
      end
    end
  end end
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
  for _, f in ipairs(Formats) do if not f.study then
    for _, layout in ipairs({ "left", "surround" }) do
      for _, p in ipairs(Patterns.list) do one("today", f.name, layout, p, nil) end
    end
  end end
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

-- Job files for the sweep (below) and the labels the sheets print, under
-- the field scale as the engine has it:
--   OUTDIR/own.job     greek_crosses, sikku_kolam and penrose_rhombs at
--                      their own size today and three candidates
--   OUTDIR/whole.job   khatam, asanoha, sikku_kolam and celtic_knot under
--                      outer=margin and edge=cell, at the field's size and
--                      rounded so the strip (less the margin) holds a whole
--                      number of periods
-- with OUTDIR/<job>.labels: variant format layout pattern k label.
if mode == "jobs" then
  local outdir = arg[3]
  local Pattern = require("flora.pattern")
  local OWN = { greek_crosses = { 30, 26, 22 }, sikku_kolam = { 16, 18, 21 }, penrose_rhombs = { 18, 21, 24 } }
  local ORDER = { "greek_crosses", "sikku_kolam", "penrose_rhombs" }
  local function factor_of(spec, p)
    return Pattern.field_factor(spec, p), Pattern.field_strip(spec)
  end
  local job = assert(io.open(outdir .. "/own.job", "w"))
  local lab = assert(io.open(outdir .. "/own.labels", "w"))
  for _, name in ipairs(ORDER) do
    local p = Patterns.by_name[name]
    for _, fname in ipairs({ "slide169", "a4" }) do
      for _, layout in ipairs({ "left", "surround" }) do
        local spec = page_spec(fname, layout, "pattern=" .. name)
        local f = factor_of(spec, p)
        local s = governing(strips(spec, layout), layout)
        local a = across_period(s, period(p))
        local sizes = { p.scale, table.unpack(OWN[name]) }
        for i, sz in ipairs(sizes) do
          local k = sz / p.scale
          local v = i == 1 and "own-today" or ("own-" .. i - 1)
          -- sikku_kolam's band would pass the width at which its core
          -- shows (pat_kit.lua's CORE_MIN) and turn pale: its width is
          -- held, so only the cells grow.
          local hold = (name == "sikku_kolam" and k > 1) and string.format(" spec.pattern_bandwidth=%.4f", 1 / k) or ""
          job:write(string.format("%s %s %s %s %.4f%s\n", v, fname, layout, name, k, hold))
          lab:write(string.format("%s %s %s %s %.4f %s\n", v, fname, layout, name, k,
            string.format("%s %g: %.1f across, field x%.2f%s", i == 1 and "today" or "cand.", sz, s[2] / (a * k * f), f,
              hold ~= "" and ", band held" or "")))
        end
      end
    end
  end
  job:close(); lab:close()
  job = assert(io.open(outdir .. "/whole.job", "w"))
  lab = assert(io.open(outdir .. "/whole.labels", "w"))
  local KEYS = "spec.pattern_outer=margin spec.pattern_edge=cell"
  for _, name in ipairs({ "khatam", "asanoha", "sikku_kolam", "celtic_knot" }) do
    local p = Patterns.by_name[name]
    for _, fname in ipairs({ "slide169", "a4", "a5" }) do
      for _, layout in ipairs({ "left", "surround" }) do
        local spec = page_spec(fname, layout, "pattern=" .. name .. ", outer=margin, edge=cell")
        local f = factor_of(spec, p)
        local s = governing(strips(spec, layout), layout)
        local a = across_period(s, period(p)) * f
        local w = s[2] - 4
        local n = math.max(2, math.floor(w / a + 0.5))
        local kc = w / (n * a)
        job:write(string.format("B %s %s %s 1 %s\n", fname, layout, name, KEYS))
        lab:write(string.format("B %s %s %s 1 B: %.2f across, field x%.2f\n", fname, layout, name, w / a, f))
        job:write(string.format("C %s %s %s %.4f %s\n", fname, layout, name, kc, KEYS))
        lab:write(string.format("C %s %s %s %.4f C: %d across (x%.3f)\n", fname, layout, name, kc, n, kc))
      end
    end
  end
  job:close(); lab:close()
  os.exit(0)
end

-- A sweep: pattern pages at a list of scale factors, for the floor and
-- ceiling study. Each line of the job file JOB is
--   variant format layout pattern k [key=value ...]
-- where k multiplies the page's scale key and the key=value pairs set
-- fields of flora.pattern's M.FIELD_SCALE for that page (enabled=false
-- draws it without the field factor, as before there was one; min_line=0,
-- ceil=none, ...), or, prefixed with spec., keys of the page's spec
-- (spec.pattern_outer=margin). as_field=true makes k the page's field
-- factor instead of a factor on its key. Writes
-- OUTDIR/<variant>/<format>__<layout>__<pattern>__<k>.pdf and .text.
if mode == "sweep" then
  local outdir, job = arg[3], arg[4]
  local Pattern = require("flora.pattern")
  local FS = Pattern.FIELD_SCALE or {}
  local saved = {}
  for k, v in pairs(FS) do saved[k] = v end
  local function value(v)
    if v == "none" then return nil elseif v == "true" then return true elseif v == "false" then return false end
    return tonumber(v) or v
  end
  for line in io.lines(job) do
    local w = {}
    for t in line:gmatch("%S+") do w[#w + 1] = t end
    if #w >= 5 and w[1]:sub(1, 1) ~= "#" then
      local variant, fname, layout, pname, k = w[1], w[2], w[3], w[4], tonumber(w[5])
      for kk in pairs(FS) do FS[kk] = nil end
      for kk, v in pairs(saved) do FS[kk] = v end
      local spec = page_spec(fname, layout, "pattern=" .. pname .. ", colourway=tsuki-mi")
      for i = 6, #w do
        local kk, v = w[i]:match("^([%w_.]+)=(.+)$")
        if kk:sub(1, 5) == "spec." then spec[kk:sub(6)] = value(v) else FS[kk] = value(v) end
      end
      if FS.as_field then
        -- k as the field factor rather than the key: the reference set so
        -- that this page's strip gives k, with no ceiling or floor.
        FS.as_field = nil
        FS.ref, FS.ceil, FS.floor, FS.min_factor = Pattern.field_strip(spec) / k, nil, 0, {}
      else
        spec[Settings.SPEC.scale] = k * (spec[Settings.SPEC.scale] or 1)
      end
      local dir = outdir .. "/" .. variant
      os.execute("mkdir -p '" .. dir .. "'")
      local base = string.format("%s/%s__%s__%s__%s", dir, fname, layout, pname, w[5])
      write_text(spec, base .. ".text")
      render(spec, base .. ".pdf")
    end
  end
  os.exit(0)
end

error("usage: pattern_scale.lua formats | patterns | tex FORMAT | measure BAKE OUT.tsv | render BAKE OUTDIR"
  .. " | jobs BAKE OUTDIR | sweep BAKE OUTDIR JOB")
