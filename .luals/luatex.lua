---@meta
-- The LuaTeX environment the engine runs in. Each global is a table of
-- untyped members: the editor needs to know they exist, not their full API.
-- The unit tests stub some of them by plain assignment.

---@alias LuaTeXApi table<string, any>

---@type LuaTeXApi
tex = nil
---@type LuaTeXApi
node = nil
---@type LuaTeXApi
pdf = nil
---@type LuaTeXApi
pdfe = nil
---@type LuaTeXApi
texio = nil
---@type LuaTeXApi
lfs = nil
---@type LuaTeXApi
zlib = nil
---@type LuaTeXApi
fonts = nil
---@type LuaTeXApi
font = nil
---@type LuaTeXApi
md5 = nil
---@type LuaTeXApi
img = nil
---@type LuaTeXApi
image = nil
---@type LuaTeXApi
status = nil
---@type LuaTeXApi
luatexbase = nil
---@type LuaTeXApi
kpse = nil
---@type LuaTeXApi
callback = nil
---@type LuaTeXApi
token = nil
---@type LuaTeXApi
newtoken = nil
---@type LuaTeXApi
lpeg = nil
---@type LuaTeXApi
unicode = nil
---@type LuaTeXApi
slnunicode = nil
---@type LuaTeXApi
language = nil
---@type LuaTeXApi
mplib = nil
---@type LuaTeXApi
texconfig = nil
