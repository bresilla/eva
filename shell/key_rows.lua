-- The live bindings of the compositor and the shell's own, as rows: what
-- eva-keys lists and edits, and the launcher's `keys` mode searches.
--
-- A row: `{ group, keys, what, id, default, custom, editable }`. `id` names what
-- a new chord is kept under (shell/keys_model.lua): `verb:VERB` for eva's own
-- keys, `bind:CHORD` for any other, `capture` for the capture key.
local shortcuts = require("shortcuts")

local M = {}

M.MODIFIERS = { { 64, "SUPER" }, { 8, "ALT" }, { 4, "CTRL" }, { 1, "SHIFT" } }

-- Holding Shift, a key names what it types: the key itself is what Hyprland
-- binds. A US layout's; another layout's shifted digits are not told apart.
local BASE = { ["!"] = "1", ["@"] = "2", ["#"] = "3", ["$"] = "4", ["%"] = "5", ["^"] = "6", ["&"] = "7",
  ["*"] = "8", ["("] = "9", [")"] = "0", ["_"] = "minus", ["+"] = "equal", ["{"] = "bracketleft",
  ["}"] = "bracketright", [":"] = "semicolon", ['"'] = "apostrophe", ["|"] = "backslash", ["~"] = "grave",
  ["<"] = "comma", [">"] = "period", ["?"] = "slash", ["-"] = "minus", ["="] = "equal", ["["] = "bracketleft",
  ["]"] = "bracketright", [";"] = "semicolon", ["'"] = "apostrophe", ["\\"] = "backslash", ["`"] = "grave",
  [","] = "comma", ["."] = "period", ["/"] = "slash", [" "] = "space" }

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

--- The chord a key press names: `name` and `mods` as `on_key_pressed` hands
--- them over, nil for a modifier alone.
function M.recorded(name, text, mods)
  name = name ~= "" and name or text
  if not name or name == "" or name:match("_[LR]$") or name == "Caps_Lock" or name == "Num_Lock" then return nil end
  local parts = {}
  mods = mods or ""
  for _, word in ipairs { { "super", "SUPER" }, { "alt", "ALT" }, { "ctrl", "CTRL" }, { "shift", "SHIFT" } } do
    if mods:find(word[1], 1, true) then parts[#parts + 1] = word[2] end
  end
  name = BASE[name] or name
  parts[#parts + 1] = #name == 1 and name:upper() or name
  return table.concat(parts, " + ")
end

--- A chord's modifiers (Hyprland's mask) and its key, however it is spelled.
function M.parts(chord)
  local mask, key = 0, nil
  for part in tostring(chord or ""):gmatch("[^+]+") do
    local word = part:match("^%s*(.-)%s*$")
    local upper = word:upper()
    local bit
    for _, modifier in ipairs(M.MODIFIERS) do if modifier[2] == upper then bit = modifier[1] end end
    if upper == "CONTROL" then bit = 4 end
    if bit then mask = mask | bit elseif word ~= "" then key = word end
  end
  return mask, key
end

--- The same chord, however it is spelled, is the same text: for comparing.
function M.normal(chord)
  local mask, key = M.parts(chord)
  return mask .. ":" .. tostring(key or ""):lower()
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

--- Whether a bind can take a new chord: a key, not a button or a switch.
local function movable(bind)
  local key = tostring(bind.key or "")
  if bind.mouse or bind.catch_all or tostring(bind.submap or "") ~= "" then return false end
  return key ~= "" and not key:match("^mouse") and not key:match("^switch:")
end

--- The rows for `binds` (hyprctl's list), the shell's own shortcuts and
--- `overrides` (id -> chord, shell/keys_model.lua); `capture` is the capture
--- key, which `capture.hotkey` keeps.
function M.merge(binds, overrides, capture)
  overrides = overrides or {}
  local keybinds = require("keybinds")
  local rows, live, by_label, moved = {}, {}, {}, {}
  for _, bind in ipairs(keybinds.BINDS) do
    if not bind.quiet then by_label[bind.label] = bind end
  end
  for id, chord in pairs(overrides) do
    if chord ~= "" then moved[M.normal(chord)] = id end
  end
  for _, bind in ipairs(binds or {}) do
    if tostring(bind.submap or "") == "" then
      local keys = M.chord(bind)
      local normal = M.normal(keys)
      local ours = by_label[tostring(bind.description or "")]
      local id, default = "bind:" .. keys, keys
      if ours then id, default = "verb:" .. ours.verb, ours.keys
      elseif normal == M.normal(capture or "") then id, default = "capture", "Print"
      elseif moved[normal] then
        id = moved[normal]
        default = id:match("^bind:(.+)$") or keys
      end
      live[keys] = true
      live[normal] = true
      rows[#rows + 1] = { group = "Compositor", keys = keys, what = M.action(bind), id = id, default = default,
        custom = overrides[id] ~= nil or (id == "capture" and keys ~= "Print"), editable = movable(bind) }
    end
  end
  -- eva's window keys the compositor does not have bound: a session with its
  -- own configuration binds them to `morf ipc call VERB` itself, or gives them
  -- a new chord here.
  local bound = next(live) ~= nil
  for _, bind in ipairs(keybinds.BINDS) do
    local id = "verb:" .. bind.verb
    local keys = overrides[id] or bind.keys
    if not bind.quiet and not live[keys] and not live[M.normal(keys)] then
      rows[#rows + 1] = { group = bound and "Not bound" or "Windows", keys = keys,
        what = bound and (bind.label .. ": morf ipc call " .. bind.verb) or bind.label,
        id = id, default = bind.keys, custom = overrides[id] ~= nil, editable = true }
    end
  end
  for _, label in ipairs(shortcuts.LABELS) do
    rows[#rows + 1] = { group = "Shell", keys = spelled(label[1]), what = label[2], id = "shell:" .. label[1], editable = false }
  end
  return rows
end

--- What a Hyprland bind does, in the fewest words it offers.
function M.action(bind)
  local words = tostring(bind.description or "")
  if words ~= "" then return words end
  local arg = tostring(bind.arg or "")
  local dispatcher = tostring(bind.dispatcher or "")
  if dispatcher == "__lua" then return "A key of your Hyprland configuration" end
  if arg == "" then return dispatcher end
  return dispatcher .. " " .. arg
end

--- The rows of `rows` that `chord` would collide with, leaving `id` out.
function M.conflicts(rows, chord, id)
  local out, normal = {}, M.normal(chord)
  for _, row in ipairs(rows or {}) do
    if row.id ~= id and row.keys ~= "" and M.normal(row.keys) == normal and row.group ~= "Not bound" then
      out[#out + 1] = row
    end
  end
  return out
end

--- Why `chord` cannot be taken, or nil: a plain letter would stop typing it.
function M.refused(chord)
  local mask, key = M.parts(chord)
  if not key then return "Press a key with the modifiers" end
  if mask == 0 and #key == 1 then return "A plain key would stop it being typed anywhere" end
  if mask == 0 and (key == "Return" or key == "BackSpace" or key == "Tab" or key == "space") then
    return "A plain key would stop it being typed anywhere"
  end
end

return M
