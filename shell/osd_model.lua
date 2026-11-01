-- The on-screen displays' catalogue and preferences: which kinds there are,
-- where each stands, how long it holds. No nodes and no services.
local morf = require("morf")
local config = require("config")

local M = {}

-- `family` picks the face: a tall `level` meter, a short `status` pill, or the
-- `media` pill with its cover. `place` is where it stands on a desk, `hold`
-- how long it stays by default, in ms.
M.KINDS = {
  { id = "volume", name = "Volume", icon = "volume_up", family = "level", place = "center_right", hold = 2200 },
  { id = "brightness", name = "Brightness", icon = "brightness_medium", family = "level", place = "center_right",
    hold = 2200 },
  { id = "mic", name = "Microphone", icon = "mic", family = "status", place = "bottom_center", hold = 1600 },
  { id = "caps", name = "Caps Lock", icon = "keyboard_capslock", family = "status", place = "bottom_center", hold = 1400 },
  { id = "num", name = "Num Lock", icon = "pin", family = "status", place = "bottom_center", hold = 1400 },
  { id = "layout", name = "Keyboard layout", icon = "keyboard", family = "status", place = "bottom_center", hold = 1600 },
  { id = "profile", name = "Power profile", icon = "balance", family = "status", place = "bottom_center", hold = 1800 },
  { id = "dnd", name = "Do not disturb", icon = "notifications_off", family = "status", place = "bottom_center",
    hold = 1600 },
  { id = "focus", name = "Focus mode", icon = "self_improvement", family = "status", place = "bottom_center", hold = 1800 },
  { id = "awake", name = "Keep awake", icon = "coffee", family = "status", place = "bottom_center", hold = 1600 },
  { id = "night", name = "Night light", icon = "nightlight", family = "status", place = "bottom_center", hold = 1600 },
  { id = "ring", name = "Ring mode", icon = "notifications_active", family = "status", place = "bottom_center",
    hold = 1600 },
  { id = "bluetooth", name = "Bluetooth device", icon = "bluetooth_connected", family = "status", place = "bottom_center",
    hold = 2400 },
  { id = "headphones", name = "Headphones", icon = "headphones", family = "status", place = "center", hold = 3200 },
  { id = "media", name = "Now playing", icon = "music_note", family = "media", place = "top_center", hold = 3600 },
  { id = "workspace", name = "Workspace", icon = "workspaces", family = "status", place = "top_center", hold = 1000 },
}
M.BY_ID = {}
for _, kind in ipairs(M.KINDS) do M.BY_ID[kind.id] = kind end

-- The nine places, in reading order: the settings' picker is this grid.
M.POSITIONS = { "top_left", "top_center", "top_right", "center_left", "center", "center_right",
  "bottom_left", "bottom_center", "bottom_right" }
-- The six a notification popup may take: the top and bottom anchors.
M.ANCHORS = { "top_left", "top_center", "top_right", "bottom_left", "bottom_center", "bottom_right" }
-- The holds the settings offer; 0 is the kind's own.
M.HOLDS = { 0, 1000, 2000, 3000, 5000 }

local VALID, ANCHORED = {}, {}
for _, position in ipairs(M.POSITIONS) do VALID[position] = true end
for _, position in ipairs(M.ANCHORS) do ANCHORED[position] = true end
M.VALID = VALID

local function setting(kind, key)
  if not config.get then return nil end
  return config.get("osd.kinds." .. kind .. "." .. key)
end
local function portrait() return require("responsive").portrait() end

--- Where `kind` stands: its setting, or by default the top centre upright
--- and its own place on a desk.
function M.position(kind)
  local chosen = setting(kind, "position")
  if VALID[chosen] then return chosen end
  if portrait() then return "top_center" end
  return (M.BY_ID[kind] or M.BY_ID.volume).place
end
function M.set_position(kind, position)
  if VALID[position] then config.set("osd.kinds." .. kind .. ".position", position) end
end

function M.enabled(kind) return setting(kind, "enabled") ~= false end
function M.set_enabled(kind, on) config.set("osd.kinds." .. kind .. ".enabled", on == true) end

--- What the setting of `kind`'s hold says, 0 for its own.
function M.chosen_hold(kind) return tonumber(setting(kind, "hold")) or 0 end

--- How long `kind` stays once it has stopped changing, in ms.
function M.hold(kind)
  local chosen = M.chosen_hold(kind)
  if chosen > 0 then return chosen end
  return (M.BY_ID[kind] or M.BY_ID.volume).hold
end
function M.set_hold(kind, ms) config.set("osd.kinds." .. kind .. ".hold", math.floor(tonumber(ms) or 0)) end

--- Whether a level shows its reading as a percentage.
function M.percent(kind) return setting(kind, "percent") ~= false end
function M.set_percent(kind, on) config.set("osd.kinds." .. kind .. ".percent", on == true) end

--- Where the notification popups stand: their setting, or by default the top
--- centre upright and the top right on a desk.
function M.notifications()
  local chosen = config.get and config.get("osd.notifications")
  if ANCHORED[chosen] then return chosen end
  return portrait() and "top_center" or "top_right"
end
function M.set_notifications(position)
  if ANCHORED[position] then config.set("osd.notifications", position) end
end

--- The edge a place swells from (nil in the centre) and where along it:
--- -1 the near end, 0 the middle, 1 the far end.
function M.anchor(position)
  local row, column = (position or "center"):match("^(%a+)_(%a+)$")
  if not row then return nil, 0 end
  if row == "center" then return column, 0 end
  return row, column == "left" and -1 or column == "right" and 1 or 0
end

return M
