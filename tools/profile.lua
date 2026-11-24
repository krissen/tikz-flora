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
-- when the script ends, also by os.exit or an error (a failing test still
-- reports), and its first line says how the run ended. A timed function
-- that raises an error is timed to the error and the error goes on as it
-- was raised: the same value, so a pcall round it catches what it would
-- have caught; a traceback taken outside starts at the wrapper. Coroutines
-- the script creates are sampled too, and a timed function's calls are
-- nested by coroutine; its time includes any time it lies suspended.
-- Bad options, an unknown --time name and an --out file that cannot be
-- written stop the run before it starts (exit status 2).

package.path = "./lua/?.lua;" .. package.path

local function usage_error(msg)
  io.stderr:write("profile: " .. msg .. "\n")
  os.exit(2)
end
-- A whole number of at least 1, or a usage error naming the option.
local function count(name, v)
  local n = tonumber(v)
  if not n or n < 1 or n ~= math.floor(n) then usage_error(name .. " takes a whole number of at least 1, not " .. tostring(v)) end
  return math.floor(n --[[@as number]])
end

local opts = { period = 10000, top = 30, time = {}, sample = true }
local i = 1
local target, code
while arg[i] do
  local a = arg[i]
  if a == "--period" then opts.period = count("--period", arg[i + 1]); i = i + 2
  elseif a == "--top" then opts.top = count("--top", arg[i + 1]); i = i + 2
  elseif a == "--out" then opts.out = arg[i + 1] or usage_error("--out takes a file"); i = i + 2
  elseif a == "--time" then
    opts.time_given = true
    for name in (arg[i + 1] or usage_error("--time takes a list")):gmatch("[^,]+") do opts.time[#opts.time + 1] = name end
    i = i + 2
  elseif a == "--no-sample" then opts.sample = false; i = i + 1
  elseif a == "-e" then code = arg[i + 1] or usage_error("-e takes code"); i = i + 2; break
  else target = a; i = i + 1; break
  end
end
if opts.time_given and #opts.time == 0 then usage_error("--time takes a list of MODULE.FN, e.g. flora.pattern.clearance") end
if not opts.sample and #opts.time == 0 then usage_error("--no-sample needs --time: with neither, nothing is measured") end
if not target and not code then
  io.stderr:write("usage: texlua tools/profile.lua [--period N] [--top N] [--out FILE] [--time M.FN,...] [--no-sample] SCRIPT [ARGS] | -e CODE\n")
  os.exit(2)
end
local rest = {}
while arg[i] do rest[#rest + 1] = arg[i]; i = i + 1 end
local chunk, load_err
if code then chunk, load_err = load(code, "=-e") else chunk, load_err = loadfile(target) end
if not chunk then usage_error(load_err) end
-- The report's file, opened now: a run is not wasted on one it cannot write.
local out
if opts.out then
  local err
  out, err = io.open(opts.out, "w")
  if not out then usage_error("--out: " .. tostring(err)) end
end

-- Timing: wrap each MODULE.FN named.
local timed = {}
for _, name in ipairs(opts.time) do
  local mod, fn = name:match("^(.+)%.([^.]+)$")
  local okm, M = false, nil
  if mod then okm, M = pcall(require, mod) end
  if not (okm and type(M) == "table" and type(M[fn]) == "function") then
    usage_error("--time: no function " .. name .. (mod and not okm and (" (" .. tostring(M):match("^[^\n]*") .. ")") or ""))
  end
  local orig, t = M[fn], { name = name, calls = 0, secs = 0, errors = 0, depth = setmetatable({}, { __mode = "k" }) }
  timed[#timed + 1] = t
  local clock, running, pack, unpack = os.clock, coroutine.running, table.pack, table.unpack
  M[fn] = function(...)
    -- A call inside another call of the same function, in the same
    -- coroutine, is counted, but its time is the outer call's already.
    local co = running()
    local d = (t.depth[co] or 0) + 1
    t.calls = t.calls + 1
    t.depth[co] = d
    local t0 = clock()
    -- Ended on both paths: a call that raises an error is timed to it, and
    -- the depth is restored before the error goes on.
    local r = pack(pcall(orig, ...))
    t.depth[co] = d - 1
    if d == 1 then t.secs = t.secs + clock() - t0 end
    if not r[1] then
      t.errors = t.errors + 1
      error(r[2], 0)
    end
    return unpack(r, 2, r.n)
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
-- `ended` says how the run ended: "completed", "ended by os.exit(...)" or
-- "stopped by an error".
local function report(ended)
  if reported then return end
  reported = true
  debug.sethook()
  local f = out or io.stderr
  f:write(string.format("profile: %s, %.2f s CPU, %s\n", target or "-e", os.clock() - cpu0, ended))
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
    for _, t in ipairs(timed) do
      f:write(string.format("%9.3f s %10d  %s%s\n", t.secs, t.calls, t.name, t.errors > 0 and string.format(" (%d raised an error)", t.errors) or ""))
    end
  end
  if f ~= io.stderr then f:close() end
end

local exit = os.exit
os.exit = function(code_, ...)
  report("ended by os.exit(" .. tostring(code_ == nil and true or code_) .. ")")
  return exit(code_, ...)
end

-- A hook is the thread's own: each coroutine the script makes gets one.
if opts.sample then
  local create = coroutine.create
  coroutine.create = function(f)
    local co = create(f)
    debug.sethook(co, hook, "", opts.period)
    return co
  end
  coroutine.wrap = function(f)
    local co = coroutine.create(f)
    return function(...)
      local r = table.pack(coroutine.resume(co, ...))
      if not r[1] then error(r[2], 0) end
      return table.unpack(r, 2, r.n)
    end
  end
end

arg = { [0] = target or "-e" }
for k, v in ipairs(rest) do arg[k] = v end
if opts.sample then debug.sethook(hook, "", opts.period) end
local ok, err = xpcall(chunk --[[@as function]], debug.traceback, table.unpack(rest))
report(ok and "completed" or "stopped by an error")
if not ok then
  io.stderr:write(tostring(err), "\n")
  exit(1)
end
