-- The live bindings of the compositor and the shell's own, as rows: what
-- eva-keys lists and the launcher's `keys` mode searches.
local shortcuts = require("shortcuts")
local unicase = require("lib.util.unicase")

local M = {}

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
  for part in chord:gmatch("[^+]+") do parts[#parts + 1] = utf8.len(part) == 1 and unicase.upper(part) or part end
  for i, part in ipairs(parts) do
    if part == "ctrl" or part == "alt" or part == "shift" then parts[i] = unicase.upper(part) end
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

return M
