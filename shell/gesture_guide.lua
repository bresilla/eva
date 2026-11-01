-- The gestures and keys this device has, in a person's words, for the welcome.
-- A row is `{ icon, what, how }`. What a keyboard or touchpad reaches is read
-- from the table that binds it (shell/keybinds.lua), so it cannot drift; the
-- touch rows follow shell/phone_gestures.lua and nix/nixos/scripts/gestures.sh.
local morf = require("morf")
local keybinds = require("keybinds")
local M = {}

-- On a phone and a tablet, where the panels are sheets and the edges gestures.
local SHEET = {
  { "south", "Swipe down from the top", "Quick settings and notifications" },
  { "north", "Swipe up from the bottom", "The dashboard" },
  { "east", "Pull in from the left edge", "Your apps" },
  { "west", "Pull in from the right edge", "Search the web" },
  { "swipe", "Swipe along the bottom edge", "The next or previous workspace" },
  { "keyboard", "Two fingers up from the bottom", "The on-screen keyboard" },
}

-- On a desk, what a panel at each edge holds.
local DESK = {
  { "north", "top", "The dashboard", "dashboard" },
  { "east", "right", "Settings and notifications", "sidebar" },
  { "west", "left", "Tasks and calendar", "leftbar" },
  { "south", "bottom", "The assistant and Drop", "bottom" },
}

-- The keys worth knowing first; the rest are in eva-keys.
local ESSENTIAL = { "SUPER + SPACE", "SUPER + D", "SUPER + N", "SUPER + comma", "SUPER + Tab", "ALT + Tab", "SUPER + W", "SUPER + X" }
local SPELLED = { SPACE = "Space", comma = "Comma", SUPER = "Super", ALT = "Alt" }

local function touchpad()
  local path = morf.env and morf.env("EVA_INPUT_DEVICES") or "/proc/bus/input/devices"
  local ok, text = pcall(morf.fs.read, path)
  if not ok or type(text) ~= "string" then return false end
  text = text:lower()
  return text:find("touchpad", 1, true) ~= nil or text:find("trackpad", 1, true) ~= nil
end

local function touchpad_rows(out)
  if not touchpad() then return end
  for _, gesture in ipairs(keybinds.GESTURES) do
    out[#out + 1] = { "swipe", ("%d fingers %s on the touchpad"):format(gesture.fingers, gesture.direction), gesture.label }
  end
end

--- The gestures of this form, as rows.
function M.gestures()
  local config, out = require("config"), {}
  if require("responsive").sheets() then
    for _, row in ipairs(SHEET) do out[#out + 1] = { row[1], row[2], row[3] } end
    return out
  end
  for _, row in ipairs(DESK) do
    local hover = config.get(row[4] .. ".hover") ~= false
    out[#out + 1] = { row[1], (hover and "Move the pointer to the %s edge" or "Press the %s edge"):format(row[2]), row[3] }
  end
  touchpad_rows(out)
  return out
end

local function spelled(keys)
  return (keys:gsub("%a+", function(word) return SPELLED[word] end))
end

--- The first keys to learn, as rows.
function M.keys()
  local labels, out = {}, {}
  for _, bind in ipairs(keybinds.BINDS) do labels[bind.keys] = bind.label end
  for _, keys in ipairs(ESSENTIAL) do
    if labels[keys] then out[#out + 1] = { "keyboard", spelled(keys), labels[keys] } end
  end
  return out
end

return M
