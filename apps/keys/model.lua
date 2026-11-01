-- eva-keys: the live bindings of the compositor and the shell's own, as one
-- searchable list. No nodes.
local morf = require("morf")
local keybinds = require("key_rows")

local M = {
  rows = morf.signal("keys.rows", {}),
  -- Moves with `rows`, for what follows the list without reading it.
  loaded = morf.signal("keys.loaded", 0),
  query = morf.signal("keys.query", ""),
  message = morf.signal("keys.message", ""),
}

M.MODIFIERS = keybinds.MODIFIERS
M.chord = keybinds.chord
M.action = keybinds.action
M.merge = keybinds.merge

--- Reads the live bindings.
function M.load()
  morf.process.run({ "hyprctl", "binds", "-j" }, {}, function(result)
    local binds = {}
    if result and result.ok then
      local ok, list = pcall(morf.json.decode, result.stdout or "")
      if ok and type(list) == "table" then binds = list end
    else
      M.message:set("The compositor's bindings cannot be read here")
    end
    M.rows:set(M.merge(binds))
    M.loaded:set(M.loaded:get() + 1)
  end)
end

--- The rows matching the query, every word of it, in either column.
function M.found()
  local out = {}
  local words = {}
  for word in M.query:get():lower():gmatch("%S+") do words[#words + 1] = word end
  for _, row in ipairs(M.rows:get()) do
    local text = (row.keys .. " " .. row.what .. " " .. row.group):lower()
    local all = true
    for _, word in ipairs(words) do all = all and text:find(word, 1, true) ~= nil end
    if all then out[#out + 1] = row end
  end
  return out
end

return M
