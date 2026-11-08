-- What the launcher can find that is not an application: every page, tile and
-- control of the shell that registers itself here, and whatever a plugin adds.
--
--   local index = require("lib.shell.launcher.search_index")
--   index.register {
--     id = "setting:power", name = "Power", keywords = "battery charge",
--     description = "Settings", material = "battery_full", tag = "Setting",
--     run = function() open_it() return "close" end,
--   }
--
-- An entry is a launcher row: `id` and `name` are required, `keywords` is what
-- else finds it, and `description` may be a function, read as it is listed.
-- `boost`, where given, is how much a match counts in place of the index's own
-- weight. Registering an `id` again replaces the entry.

local morf = require("morf")

local M = {}

local by_id, order = {}, {}

--- Moves whenever an entry comes or goes.
M.revision = morf.signal("eva.search.revision", 0)
local function bump() M.revision:set(M.revision:get() + 1) end

--- Adds `entry`, or replaces the one with its `id`.
function M.register(entry)
  assert(type(entry) == "table" and entry.id and entry.name, "a search entry needs an id and a name")
  assert(entry.run or entry.resolve, "a search entry needs a run")
  if not by_id[entry.id] then order[#order + 1] = entry.id end
  by_id[entry.id] = entry
  bump()
end

--- Removes the entry `id`.
function M.forget(id)
  if not by_id[id] then return end
  by_id[id] = nil
  for i, other in ipairs(order) do
    if other == id then table.remove(order, i) break end
  end
  bump()
end

--- The entry `id`, or nil.
function M.get(id) return by_id[id] end

--- Every entry, in the order they came.
function M.all()
  local out = {}
  for i, id in ipairs(order) do out[i] = by_id[id] end
  return out
end

return M
