-- Under TeX a frame's resource dictionary must stay small however many Forms
-- the plan holds, and splitting content into runs must keep the paint order.
local H = dofile("tests/helper.lua")
local Paint = require("flora.paint")
local P = require("flora.progression")
local objects = 0
pdf = { immediateobj = function() objects = objects + 1; return objects end }
local file = assert(io.open("tests/fixtures/support-seed3.lua"))
local spec = require("flora.serial").decode(file:read("a")); file:close()
Paint.reset_resources()
local plan = P.plan(spec)
H.check(#plan.forms > 500, "fixture no longer has many Forms")

local function flatten(body, forms, out)
  for name in body:gmatch("/([%w_]+) Do") do
    if forms[name] then flatten(forms[name].body, forms, out) else out[#out + 1] = name end
  end
  return out
end
local function sequence(pt)
  local forms = {}
  for _, f in ipairs(pt.xobjects or {}) do if f.name:match("^flbatch") then forms[f.name] = f end end
  return flatten(pt:body(), forms, {})
end

local grouped = 0
for _, t in ipairs({ 0.2, 0.5, 0.8, 0.95 }) do
  Paint.standalone = false
  local native = P.render(plan, t)
  local groups = 0
  for _, f in ipairs(native.xobjects or {}) do if f.name:match("^flbatch") then groups = groups + 1 end end
  if groups > 0 then
    grouped = grouped + 1
    H.check(groups < 400, "too many frame-level Forms: " .. groups)
    for _, f in ipairs(native.xobjects) do
      local depth = 0
      for token in f.body:gmatch("%S+") do
        if token == "q" then depth = depth + 1
        elseif token == "Q" then depth = depth - 1 end
        H.check(depth >= 0, f.name .. " pops a state it did not save")
      end
      H.check(depth == 0, f.name .. " leaves a state unbalanced")
    end
    H.check(#native.pdf_resources < 6000, "frame resources list the plan's Forms: " .. #native.pdf_resources)
  end
  local names = sequence(native)
  Paint.standalone = true
  local direct = sequence(P.render(plan, t))
  Paint.standalone = false
  H.check(table.concat(names, " ") == table.concat(direct, " "), "runs changed the paint order at t=" .. t)
end
H.check(grouped > 0, "no frame exercised transparency groups")
H.done("progression_frame_resources")
