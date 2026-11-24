-- A test too heavy for one file, split across several (test_X_1.lua,
-- test_X_2.lua, ...): each part runs its share of the sweep and of the
-- checks, and every item of the whole runs in exactly one part, so the
-- parts together make the checks the whole made.
--
--   local S = dofile("tests/split.lua").new(part, parts, weights)
--   if S.mine("mutant:no keep") then ... end
--
-- `weights` lists { item, seconds } for every item that can be put in any
-- part (a pattern's share of a sweep, a mutation, a block of checks), the
-- seconds measured (just test-times, the tool's own notes below). The items
-- are given to the parts heaviest first, each to the part with the least
-- so far, so the plan is the same in every part. An item that is not listed
-- is an error: a new mutation or pattern must say what it weighs. Items
-- that are not worth a place of their own are run by part 1 (S.first).
--
-- FLORA_SPLIT_LIST=1 names, on stderr, each item this part runs, so that
-- the parts' lists can be compared with the whole's (parts = 1).
local Split = {}

function Split.new(part, parts, weights)
  local load, owner = {}, {}
  for i = 1, parts do load[i] = 0 end
  local items = {}
  for _, w in ipairs(weights) do
    assert(owner[w[1]] == nil, "split: " .. w[1] .. " is listed twice")
    owner[w[1]] = false
    items[#items + 1] = w
  end
  table.sort(items, function(a, b)
    if a[2] ~= b[2] then return a[2] > b[2] end
    return a[1] < b[1]
  end)
  for _, w in ipairs(items) do
    local best = 1
    for i = 2, parts do if load[i] < load[best] then best = i end end
    owner[w[1]] = best
    load[best] = load[best] + w[2]
  end
  local S = { part = part, parts = parts, first = part == 1, load = load }
  local list = os.getenv("FLORA_SPLIT_LIST")
  local asked = {}

  -- Whether this part runs the item.
  function S.mine(item)
    local o = owner[item]
    if o == nil then error("split: no weight for " .. item, 2) end
    local mine = o == part
    asked[item] = true
    if mine and list then io.stderr:write(string.format("SPLIT part %d: %s\n", part, item)) end
    return mine
  end

  -- A check that every part makes on its own share (that its sweep had the
  -- cells it should): part 1 counts it, the others only report it when it
  -- fails, so the whole makes it once.
  function S.check(H, cond, msg)
    if S.first then H.check(cond, msg) elseif not cond then H.check(false, msg) end
  end

  -- At the end of the test: every item given to this part was asked for. An
  -- item that nothing in the test asks about would be run by no part.
  function S.finish(H)
    local lost = {}
    for item, o in pairs(owner) do
      if o == part and not asked[item] then lost[#lost + 1] = item end
    end
    table.sort(lost)
    for _, item in ipairs(lost) do H.check(false, "split: nothing in the test runs " .. item) end
  end

  -- Items run by part 1 only (checks too small to weigh).
  function S.once(item)
    if list and S.first then io.stderr:write(string.format("SPLIT part %d: %s\n", part, item)) end
    return S.first
  end

  return S
end

return Split
