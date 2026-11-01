-- eva-keys: the live bindings of the compositor and the shell's own, as one
-- searchable list. No nodes.
local morf = require("morf")
local shortcuts = require("shortcuts")

local M = {
  rows = morf.signal("keys.rows", {}),
  query = morf.signal("keys.query", ""),
  message = morf.signal("keys.message", ""),
}

M.MODIFIERS = { { 64, "SUPER" }, { 8, "ALT" }, { 4, "CTRL" }, { 1, "SHIFT" } }

--- A Hyprland bind's chord: "SUPER + SHIFT + T".
function M.chord(bind)
  local parts = {}
  local mask = tonumber(bind.modmask) or 0
  for _, modifier in ipairs(M.MODIFIERS) do
    if mask & modifier[1] ~= 0 then parts[#parts + 1] = modifier[2] end
  end
  local key = tostring(bind.key or "")
  if key ~= "" then parts[#parts + 1] = key end
  return table.concat(parts, " + ")
end

--- What a Hyprland bind does, in the fewest words it offers.
function M.action(bind)
  local words = tostring(bind.description or "")
  if words ~= "" then return words end
  local arg = tostring(bind.arg or "")
  local dispatcher = tostring(bind.dispatcher or "")
  if arg == "" then return dispatcher end
  return dispatcher .. " " .. arg
end

--- A shell chord as binds are spelled: "CTRL + SHIFT + C".
local function spelled(chord)
  local parts = {}
  for part in chord:gmatch("[^+]+") do parts[#parts + 1] = #part > 1 and part or part:upper() end
  for i, part in ipairs(parts) do
    if part == "ctrl" or part == "alt" or part == "shift" then parts[i] = part:upper() end
  end
  return table.concat(parts, " + ")
end

--- The rows for `binds` (hyprctl's list) and the shell's own shortcuts.
function M.merge(binds)
  local rows, live = {}, {}
  for _, bind in ipairs(binds or {}) do
    local keys = M.chord(bind)
    live[keys] = true
    rows[#rows + 1] = { group = "Compositor", keys = keys, what = M.action(bind) }
  end
  -- eva's window keys the compositor does not have bound: a session with its
  -- own configuration binds them to `morf ipc call VERB` itself.
  local bound = next(live) ~= nil
  for _, bind in ipairs(require("keybinds").BINDS) do
    if not live[bind.keys] and not bind.quiet then
      rows[#rows + 1] = { group = bound and "Not bound" or "Windows", keys = bind.keys,
        what = bound and (bind.label .. ": morf ipc call " .. bind.verb) or bind.label }
    end
  end
  for _, label in ipairs(shortcuts.LABELS) do
    rows[#rows + 1] = { group = "Shell", keys = spelled(label[1]), what = label[2] }
  end
  return rows
end

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
