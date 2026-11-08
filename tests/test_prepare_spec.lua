local H = dofile("tests/helper.lua")
tex = { sprint = function() end }
texio = { write_nl = function() end }
local seen, exported, filename
package.loaded["flora.compose"] = { page = function(s)
  seen = s
  return { defs = {}, out = {} }
end }
package.loaded["flora.measure"] = { boxes = function()
  return { { x0 = 40, x1 = 120, y0 = 250, y1 = 265 } }
end }
local Flora = require("flora.init")
H.check(Flora.prepare_spec_version == 1, "missing integration capability marker")
local function args()
  return { width = "400pt", height = "300pt", text_x0 = "40pt",
    text_x1 = "360pt", text_y0 = "30pt", text_y1 = "270pt",
    header_y = "280pt", frametitle = "1", frametitle_height = "30pt",
    box = 1, seed = "3", page = 7 }
end
Flora.page(args())
H.check(seen.seed == Flora.seed("3", 7) and seen.page == 7,
  "default physical seed/page changed")
local a = args()
a.prepare_spec = function(s)
  H.check(s.body_top == 240 and s.header_right == 120 and #s.lines == 1,
    "callback ran before measurements and header bounds")
  s.seed, s.lines = 42, { { x0 = 10, x1 = 350, y0 = 50, y1 = 250 } }
end
local getenv, open = os.getenv, io.open
os.getenv = function(k) if k == "FLORA_SPEC_DIR" then return "diagnostics" end return getenv(k) end
io.open = function(path, mode)
  H.check(mode == "w", "unexpected diagnostic file mode")
  filename = path
  return { write = function(_, s) exported = s end, close = function() end }
end
Flora.page(a)
os.getenv, io.open = getenv, open
H.check(seen.seed == 42 and seen.lines[1].x0 == 10, "compose missed callback mutations")
H.check(a.page == 7 and filename == "diagnostics/spec-7.lua", "callback changed physical output identity")
local saved = assert(load("return " .. exported, "diagnostic", "t", {}))()
H.check(saved.lines[1].x0 == 10 and saved.seed == nil, "export missed prepared geometry or exported seed")
a = args()
a.only = "8"
a.prepare_spec = function() error("filtered page callback ran") end
Flora.page(a)
a.only = nil
H.check(not pcall(Flora.page, a), "callback errors were swallowed")
H.done("prepare_spec")
