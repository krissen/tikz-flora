-- A Form's deflate is reused only for the same content at the same level.
local H = dofile("tests/helper.lua")
if not (zlib and zlib.compress) then
  print("pdf_form_cache: skipped, needs zlib")
  return
end
local Pdf = require("flora.pdfout")
local Paint = require("flora.paint")
local calls, real = 0, zlib.compress
zlib.compress = function(d, l) calls = calls + 1; return real(d, l) end
Paint.reset_resources()
local form = { name = "F1", bbox = "[0 0 1 1]", body = "0 0 1 1 re f" }
local function encode(level)
  local pt = Paint.new({ backend = "pdf" })
  pt.xobjects = { form }
  return Pdf.encode(pt, 10, 10, level)
end
local function forms_compressed(fn)
  local before = calls
  local out = fn()
  return calls - before, out
end
local n0, first = forms_compressed(function() return encode(nil) end)
H.check(n0 >= 1, "the Form was not deflated")
local n1, again = forms_compressed(function() return encode(nil) end)
H.check(n1 == n0 - 1, "an unchanged Form was deflated again")
H.check(again == first, "cached output differs from a fresh deflate")
form.body = "0 0 2 2 re f"
local n2, changed = forms_compressed(function() return encode(nil) end)
H.check(n2 == n0, "changed Form content reused an old deflate")
H.check(changed ~= first, "changed Form content produced the old stream")
local fresh = { name = "F1", bbox = "[0 0 1 1]", body = "0 0 2 2 re f" }
local saved = form
form = fresh
H.check(encode(nil) == changed, "a cached stream differs from a fresh Form's")
form = saved
local n3 = forms_compressed(function() return encode(9) end)
H.check(n3 >= 1 and form.pdf_stream.level == 9, "a new level reused the old deflate")
zlib.compress = real
H.done("pdf_form_cache")
