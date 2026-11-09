-- The Settings pages behind Focus: the modes and what each one does. The views
-- are the selected theme's; this is their model.
local config = require("config")
local focus = require("focus_model")
local rules = require("notification_rules")
local M = {}

local RING = { { "", "Leave" }, { "sound", "Sound" }, { "vibrate", "Vibrate" }, { "silent", "Silent" } }

--- `settings`: the host the page is built in, the Settings window's model or
--- the quick controls' panel's, for whether it is on show and where it leads.
function M.model(settings)
  local model = { active = settings.showing("focus"), MAX = focus.MAX,
    controls = settings.focus, DURATIONS = focus.DURATIONS, awake = require("awake_model").page() }
  model.modes = focus.modes
  --- The modes but Do not disturb, which has its row among the interruptions.
  function model.named()
    local out = {}
    for _, mode in ipairs(focus.modes()) do
      if mode.id ~= "dnd" then out[#out + 1] = mode end
    end
    return out
  end
  function model.on(id) return focus.active_id() == id end
  function model.set_on(id, on)
    if on then focus.start(id, { seconds = config.get("focus.duration") }) elseif focus.active_id() == id then focus.stop() end
  end
  function model.line(mode)
    if focus.active_id() == mode.id then
      local ends = focus.ends()
      return ends > 0 and "On until " .. require("morf").time.format("%H:%M", ends) or "On"
    end
    local schedule = focus.schedule_text(mode)
    return schedule == "Off" and "No schedule" or schedule
  end
  function model.open(id)
    settings.focus_mode:set(id)
    settings.request("focus/mode")
  end
  function model.add()
    local id = focus.add("Custom")
    if id then model.open(id) end
  end
  function model.duration() return config.get("focus.duration") end
  function model.set_duration(seconds) config.set("focus.duration", seconds) end
  function model.sharing() return config.get("focus.sharing") end
  function model.set_sharing(on) config.set("focus.sharing", on == true) end
  function model.fullscreen() return config.get("focus.fullscreen") end
  function model.set_fullscreen(on) config.set("focus.fullscreen", on == true) end
  return model
end

--- The model of a mode's page. `settings.focus_mode` names the mode.
function M.mode_model(settings)
  local model = { active = settings.showing("focus/mode"), ICONS = focus.ICONS,
    DAYS = focus.DAYS, URGENCY = focus.URGENCY, RING = RING }
  local function id() return settings.focus_mode:get() end
  local function mode() return focus.mode(id()) or {} end
  model.id, model.mode = id, mode
  --- A field of the mode, by dotted path.
  function model.get(field)
    local node = mode()
    for part in field:gmatch("[^.]+") do
      if type(node) ~= "table" then return nil end
      node = node[part]
    end
    return node
  end
  function model.set(field, value) focus.set(id(), field, value) end
  function model.flip(field, value) focus.flip(id(), field, value) end
  function model.has(field, value)
    for _, candidate in ipairs(model.get(field) or {}) do
      if candidate == value then return true end
    end
    return false
  end
  model.apps = rules.apps
  --- A list field as one line of words, and back.
  function model.words(field) return table.concat(model.get(field) or {}, ", ") end
  function model.set_words(field, text)
    local out = {}
    for word in tostring(text):gmatch("[^,]+") do
      word = word:match("^%s*(.-)%s*$")
      if word ~= "" then out[#out + 1] = word end
    end
    model.set(field, out)
  end
  function model.schedule_text() return focus.schedule_text(mode()) end
  --- Moves a time of the schedule by `minutes`, round the clock.
  function model.shift(field, minutes)
    local hour, minute = tostring(model.get(field)):match("(%d+):(%d+)")
    local total = ((tonumber(hour) or 0) * 60 + (tonumber(minute) or 0) + minutes) % 1440
    model.set(field, ("%02d:%02d"):format(total // 60, total % 60))
  end
  function model.removable() return id() ~= "dnd" end
  function model.remove()
    if focus.remove(id()) then settings.request("focus") end
  end
  return model
end

function M.page(settings, w, h)
  return require("themes").view("focus_page").build(M.model(settings), w, h)
end
function M.mode_page(settings, w, h)
  return require("themes").view("focus_page").mode(M.mode_model(settings), w, h)
end

return M
