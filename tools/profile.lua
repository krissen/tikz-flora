-- Where a Lua run spends its time, measured two ways (docs/testing.md):
--
--   texlua tools/profile.lua [options] SCRIPT [ARGS...]
--   texlua tools/profile.lua [options] -e 'LUA CODE'
--
-- Sampling (the default): every PERIOD virtual-machine instructions the
-- function running and its stack are noted. The report gives each
-- function's share of the samples by itself ("self") and with what it
-- calls ("inclusive"), and the lines that take most samples. Shares are of
-- instructions, not of seconds: time in C (string building, table
-- allocation, the collector) is counted to the Lua line that asked for it.
--
-- Timing (--time MODULE.FN,...): the functions named are wrapped, and each
-- one's calls and its seconds of CPU (os.clock, what it calls included)
-- are counted, exactly and without sampling. Use it to check what the
-- sampling points at, or to count the calls behind a share.
--
-- Options:
--   --period N    instructions between samples (default 10000; larger
--                 is lighter and coarser)
--   --top N       rows per table (default 30)
--   --out FILE    write the report there (default: stderr)
--   --time LIST   comma-separated MODULE.FN, e.g.
--                 flora.pattern.clearance,flora.compose.page
--   --no-sample   with --time: time only, no sampling
--
-- The script runs from the current directory with ./lua on package.path,
-- as the tests do, and sees ARGS as its arg table. The report is written
-- when the script ends, also by os.exit (a failing test still reports).

package.path = "./lua/?.lua;" .. package.path

local opts = { period = 10000, top = 30, time = {}, sample = true }
local i = 1
local target, code
while arg[i] do
  local a = arg[i]
  if a == "--period" then opts.period = assert(tonumber(arg[i + 1]), "--period N"); i = i + 2
  elseif a == "--top" then opts.top = assert(tonumber(arg[i + 1]), "--top N"); i = i + 2
  elseif a == "--out" then opts.out = assert(arg[i + 1], "--out FILE"); i = i + 2
  elseif a == "--time" then
    for name in assert(arg[i + 1], "--time LIST"):gmatch("[^,]+") do opts.time[#opts.time + 1] = name end
    i = i + 2
  elseif a == "--no-sample" then opts.sample = false; i = i + 1
  elseif a == "-e" then code = assert(arg[i + 1], "-e CODE"); i = i + 2; break
  else target = a; i = i + 1; break
  end
end
if not target and not code then
  io.stderr:write("usage: texlua tools/profile.lua [--period N] [--top N] [--out FILE] [--time M.FN,...] [--no-sample] SCRIPT [ARGS] | -e CODE\n")
  os.exit(2)
end
local rest = {}
while arg[i] do rest[#rest + 1] = arg[i]; i = i + 1 end

-- Timing: wrap each MODULE.FN named.
local timed = {}
for _, name in ipairs(opts.time) do
  local mod, fn = name:match("^(.+)%.([^.]+)$")
  local M = mod and require(mod)
  if not (M and type(M[fn]) == "function") then error("--time: no function " .. name) end
  local orig, t = M[fn], { name = name, calls = 0, secs = 0, depth = 0 }
  timed[#timed + 1] = t
  local clock = os.clock
  local function finish(t0, ...)
    t.depth = t.depth - 1
    -- A call inside another call of the same function is counted, but its
    -- time is the outer call's already.
    if t.depth == 0 then t.secs = t.secs + clock() - t0 end
    return ...
  end
  M[fn] = function(...)
    t.calls = t.calls + 1
    t.depth = t.depth + 1
    return finish(clock(), orig(...))
  end
end

-- Sampling.
local self_f, incl_f, self_l, total = {}, {}, {}, 0
local getinfo = debug.getinfo
local self_src = getinfo(1, "S").short_src
local function where(info)
  return string.format("%s:%d %s", info.short_src, info.linedefined, info.name or "?")
end
local function hook()
  total = total + 1
  local info = getinfo(2, "Sln")
  if not info then return end
  local k = where(info)
  self_f[k] = (self_f[k] or 0) + 1
  local lk = info.short_src .. ":" .. (info.currentline or 0)
  self_l[lk] = (self_l[lk] or 0) + 1
  local seen, lvl = {}, 2
  while lvl < 80 do
    local s = getinfo(lvl, "Sn")
    if not s then break end
    local kk = s.short_src .. ":" .. s.linedefined
    -- The profiler's own frames and C's are on every stack: left out.
    if s.what ~= "C" and s.short_src ~= self_src and not seen[kk] then
      seen[kk] = true
      local e = incl_f[kk]
      if not e then e = { n = 0, name = where(s) }; incl_f[kk] = e end
      e.n = e.n + 1
    end
    lvl = lvl + 1
  end
end

local cpu0 = os.clock()
local reported = false
local function report()
  if reported then return end
  reported = true
  debug.sethook()
  local f = opts.out and assert(io.open(opts.out, "w")) or io.stderr
  f:write(string.format("profile: %s, %.2f s CPU\n", target or "-e", os.clock() - cpu0))
  local function rows(title, tbl, n, of)
    local t = {}
    for k, v in pairs(tbl) do
      if type(v) == "table" then t[#t + 1] = { v.name, v.n } else t[#t + 1] = { k, v } end
    end
    table.sort(t, function(a, b) return a[2] > b[2] end)
    f:write("\n== " .. title .. "\n")
    for r = 1, math.min(n, #t) do f:write(string.format("%6.2f%%  %s\n", 100 * t[r][2] / of, t[r][1])) end
  end
  if opts.sample and total > 0 then
    f:write(string.format("%d samples, one every %d instructions\n", total, opts.period))
    rows("self, by function", self_f, opts.top, total)
    rows("inclusive, by function", incl_f, opts.top, total)
    rows("self, by line", self_l, opts.top, total)
  end
  if #timed > 0 then
    f:write("\n== timed (CPU seconds, callees included; calls)\n")
    table.sort(timed, function(a, b) return a.secs > b.secs end)
    for _, t in ipairs(timed) do f:write(string.format("%9.3f s %10d  %s\n", t.secs, t.calls, t.name)) end
  end
  if f ~= io.stderr then f:close() end
end

local exit = os.exit
os.exit = function(...)
  report()
  return exit(...)
end

arg = { [0] = target or "-e" }
for k, v in ipairs(rest) do arg[k] = v end
local chunk = code and assert(load(code, "=-e")) or assert(loadfile(target))
if opts.sample then debug.sethook(hook, "", opts.period) end
local ok, err = xpcall(chunk, debug.traceback, table.unpack(rest))
report()
if not ok then
  io.stderr:write(tostring(err), "\n")
  exit(1)
end
