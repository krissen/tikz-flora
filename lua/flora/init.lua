-- Entry points called from TeX.

local M = {}
-- Capability marker for adapters requiring the post-measurement callback.
M.prepare_spec_version = 1
M.render_page_version = 1

-- Send a painted page to TeX. PGF code goes through TeX one chunk at a
-- time (each chunk begins with a control sequence, so concatenating them
-- without line ends is safe). A PDF content stream is held until TeX reaches
-- M.flush, which must run inside the picture, after the resource
-- registrations; it never passes through TeX's input.
function M.typeset(pt)
  for _, d in ipairs(pt.defs) do
    -- PDF registrations update document-wide PGF dictionaries. Cached plans
    -- share their defs across frames; inserting them again creates duplicate
    -- dictionary keys. PGF colours/shadings can be scoped and must repeat.
    if pt.backend == "pdf" then
      M._pdf_defs = M._pdf_defs or {}
      if not M._pdf_defs[d] then
        tex.sprint(d)
        M._pdf_defs[d] = true
      end
    else
      tex.sprint(d)
    end
  end
  if pt.backend == "pdf" then
    M._pending = pt:body()
    M._pending_resources = pt.xobjects and pt.pdf_resources or nil
    M._pending_size = pt.xobjects and {pt.width, pt.height} or nil
    tex.sprint("\\directlua{flora.flush()}")
  else
    for _, c in ipairs(pt.out) do tex.sprint(c) end
  end
end

-- Write the held PDF content as one literal, in the same coordinate mode
-- PGF's own literals use, so it shares the picture's origin.
function M.flush()
  if M._pending_resources then
    -- One native frame Form lets LuaTeX/animate manage its XObject reference
    -- in the current resource scope. The semantic forms are its resources;
    -- no custom /XObject page dictionary competes with Beamer or animate.
    local literal=node.new("whatsit", "pdf_literal")
    literal.mode=0; literal.data=M._pending
    local box=node.new("hlist")
    box.dir="TLT"; box.list=literal; box.width=math.floor(M._pending_size[1]*65536+.5)
    box.height=math.floor(M._pending_size[2]*65536+.5); box.depth=0
    local index=tex.saveboxresource(box,"",M._pending_resources,true)
    local wrapper=node.new("hlist")
    wrapper.dir="TLT"; wrapper.list=tex.useboxresource(index)
    wrapper.width=0; wrapper.height=0; wrapper.depth=0
    node.write(wrapper)
    M._pending=nil; M._pending_resources=nil; M._pending_size=nil
    return
  end
  local n = node.new("whatsit", "pdf_literal")
  n.mode = 0
  n.data = M._pending or ""
  M._pending = nil
  node.write(n)
end

-- Settings from \florasetup (the document's) and \florathispage (the next
-- page shipped only); see settings.lua for the keys.
M.settings = {}
M.once = nil

local function report(err)
  tex.error("tikzflora: " .. tostring(err):gsub("^.-:%d+: ", ""))
end

function M.setup(s, once)
  local Settings = require("flora.settings")
  local ok, t = pcall(Settings.parse, s)
  if not ok then return report(t) end
  if once then
    M.once = Settings.merge(M.once, t)
  else
    M.settings = Settings.merge(M.settings, t)
  end
end

-- Leave a named mark at this point of the page (measure.lua).
function M.mark(name)
  require("flora.measure").mark(name)
end

function M.specimens(seed)
  local spec = require("flora.specimen")
  tex.sprint(string.format(
    "\\pgfpathrectangle{\\pgfpointorigin}{\\pgfqpoint{%dpt}{%dpt}}\\pgfusepath{use as bounding box}",
    spec.width, spec.height))
  M.typeset(spec.draw(seed))
end

-- The ornament gallery (gallery.lua): every kind for `seeds` seeds, each
-- labelled with its name and the key that weighs it.
function M.gallery(seeds)
  local pt, cells, w, h = require("flora.gallery").sheet(nil, tonumber(seeds) or 3)
  tex.sprint(string.format(
    "\\pgfpathrectangle{\\pgfpointorigin}{\\pgfqpoint{%.2fpt}{%.2fpt}}\\pgfusepath{use as bounding box}", w, h))
  M.typeset(pt)
  for _, c in ipairs(cells) do
    if c.seed == 1 then
      tex.sprint(string.format(
        "\\pgftext[left,base,at=\\pgfqpoint{%.2fpt}{%.2fpt}]{\\footnotesize %s \\texttt{\\color{gray}%s}}",
        c.box[1], c.box[4] + 5 + c.lift, c.label, (c.name:gsub("_", "\\_"))))
    end
  end
end

local function pt_of(s)
  return tonumber((tostring(s):gsub("pt$", "")))
end

-- Rectangles the flora must keep out of, in paper coordinates (pt, origin at
-- the lower-left corner). Set from TeX with \florareserve; they apply to
-- every page shipped after the call.
M.reserve = {}

function M.add_reserve(x0, y0, x1, y1)
  M.reserve[#M.reserve + 1] = { pt_of(x0), pt_of(y0), pt_of(x1), pt_of(y1) }
end

function M.clear_reserve()
  M.reserve = {}
end

-- The seed for a page: a fixed document seed varied by page number, or the
-- clock when the document asks for "random".
function M.seed(base, page)
  if base == "random" then
    M._clock = M._clock or os.time()
    base = M._clock
  end
  return (tonumber(base) or 1) * 7919 + page * 104729
end

-- Draw the flora for one page as a page-sized pgfpicture whose origin is the
-- lower-left corner of the paper. Dimensions arrive as TeX "<n>pt" strings.
--   a.width, a.height, a.text_x0, a.text_y0, a.text_x1, a.text_y1,
--   a.header_y, a.seed, a.page, a.box (the register holding the page,
--   whose ink is measured so flora can grow into space the text leaves),
--   and a.only (a page number; other pages are left bare)
--
-- With FLORA_SPEC_DIR set, each page's measured layout (everything but the
-- seed) is also written to <dir>/spec-<page>.lua, for tools/preview.lua.
function M.page(a)
  local dump = os.getenv("FLORA_SPEC_DIR")
  local skip = a.only and a.only ~= "" and tonumber(a.only) ~= a.page
  if skip and not (dump and dump ~= "") then return end
  local set = require("flora.settings").merge(M.settings, M.once)
  M.once = nil
  local lines, marks
  if a.box then lines, marks = require("flora.measure").boxes(a.box, pt_of(a.height)) end
  local spec = {
    width = pt_of(a.width), height = pt_of(a.height),
    text = { x0 = pt_of(a.text_x0), y0 = pt_of(a.text_y0), x1 = pt_of(a.text_x1), y1 = pt_of(a.text_y1) },
    header_y = a.header_y and pt_of(a.header_y),
    seed = M.seed(set.seed or a.seed, a.page),
    lines = lines, layout = set.layout, page = a.page, mix = set.mix, ornaments = set.ornaments,
    palette = set.palette, spin = set.spin, tune = set.tune,
    header = set.header, frametitle = a.frametitle == "1",
    frametitle_height = a.frametitle_height and pt_of(a.frametitle_height),
    reserve = M.reserve,
    doc_seed = tostring(set.seed or a.seed),
  }
  if marks and marks["title-start"] and lines then
    spec.title = require("flora.frames").between(lines, marks["title-start"], marks["title-end"] or 0)
  end
  if spec.frametitle and spec.frametitle_height and spec.frametitle_height > 0 then
    spec.body_top = spec.text.y1 - spec.frametitle_height
    local top = spec.text.y1
    local bottom = top - spec.frametitle_height
    local right = 0
    for _, l in ipairs(lines or {}) do
      if l.y1 >= bottom - 2 and l.y0 <= top + 2 and l.x1 > right then right = l.x1 end
    end
    if right > 0 then spec.header_right = right end
  end
  -- Integration adapters may replace measured geometry and the logical seed.
  -- Keep a.page as the physical page for filtering and diagnostic filenames.
  if a.prepare_spec then a.prepare_spec(spec) end
  if dump and dump ~= "" then
    local f = assert(io.open(string.format("%s/spec-%d.lua", dump, a.page), "w"))
    local saved = {}
    for k, v in pairs(spec) do if k ~= "seed" then saved[k] = v end end
    f:write(require("flora.serial").encode(saved), "\n")
    f:close()
  end
  if skip then return end
  -- A cached-plan adapter can return a painter, or true after emitting its
  -- own picture/animation. Measurement and prepare_spec always precede it.
  local pt
  if a.render_page then
    pt = a.render_page(spec, a)
    if pt == true then return end
    assert(pt == nil or type(pt) == "table", "render_page must return a painter, nil or true")
  end
  pt = pt or require("flora.compose").page(spec)
  return M.typeset_page(pt, spec, a)
end

-- Shared picture wrapper for cached overlays and individual animation frames.
function M.typeset_page(pt, spec, a)
  a = a or {}
  tex.sprint("\\begin{pgfpicture}")
  local band = a.background_height and pt_of(a.background_height) or 0
  if band > 0 then
    local y = a.background_position == "bottom" and 0 or spec.height - band
    tex.sprint(string.format("\\pgfsetfillcolor{%s}", a.background_color or "black"))
    tex.sprint(string.format("\\pgfpathrectangle{\\pgfpoint{0pt}{%.2fpt}}{\\pgfqpoint{%.2fpt}{%.2fpt}}\\pgfusepath{fill}", y, spec.width, band))
  end
  tex.sprint(string.format(
    "\\pgfpathrectangle{\\pgfpointorigin}{\\pgfqpoint{%.2fpt}{%.2fpt}}\\pgfusepath{use as bounding box}",
    spec.width, spec.height))
  -- Intersect one exclusion clip per reservation. Separate clips keep
  -- overlapping rectangles excluded rather than toggling their overlap.
  if #(spec.reserve or {}) > 0 then
    tex.sprint("\\begin{pgfscope}")
    for _, r in ipairs(spec.reserve or {}) do
      tex.sprint(string.format(
        "\\pgfseteorule\\pgfpathrectangle{\\pgfpointorigin}{\\pgfqpoint{%.2fpt}{%.2fpt}}"
          .. "\\pgfpathrectangle{\\pgfqpoint{%.2fpt}{%.2fpt}}{\\pgfqpoint{%.2fpt}{%.2fpt}}\\pgfusepath{clip}\\pgfsetnonzerorule",
        spec.width, spec.height, r[1], r[2], r[3] - r[1], r[4] - r[2]))
    end
  end
  M.typeset(pt)
  if #(spec.reserve or {}) > 0 then tex.sprint("\\end{pgfscope}") end
  tex.sprint("\\end{pgfpicture}")
  texio.write_nl("log", string.format("flora: coverage %.2f", pt.coverage or 0))
end

return M
