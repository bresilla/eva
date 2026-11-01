-- The right panel's Focus page, behind the Focus tile: what interrupts, the
-- modes, how long a session runs and what quiets the machine by itself; and one
-- page in, what a mode lets through, when it comes on and what it changes. In the
-- page template (themes/layouts/page.lua).
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local L = require("themes.layouts.parts")
local C = theme.color
local V = {}

local APPS = 8

local function toggle(w, id, icon, name, subtitle, on, set)
  local function lit() return on() == true end
  return P.row { id = id, width = P.inner(w), icon = icon, title = name, subtitle = subtitle, on = lit,
    trailing = P.switch { id = id .. "-switch", name = name, on = lit, on_toggled = set } }
end

local function caption(w, text)
  return kit.subtitle { width = P.inner(w), font_size = theme.size.small, color = kit.ink("lo"), text = text }
end

local function choices(w, id, title, items, now, pick, per)
  local named = {}
  for i, item in ipairs(items) do named[i] = { item[1], nil, item[2] } end
  return ui.Column { width = P.inner(w), gap = theme.space.xs, caption(w, title),
    F.choices { id = id, width = P.inner(w), items = named, per_row = per or #items, now = now, pick = pick } }
end

function V.build(model, w, h)
  local inner = P.inner(w)
  local modes = { id = "settings-focus-modes", width = w, title = "Modes" }
  for slot = 1, model.MAX - 1 do
    local function mode() return model.named()[slot] end
    local function on() local m = mode() return m ~= nil and model.on(m.id) end
    modes[#modes + 1] = P.row { id = "focus-mode-" .. slot, width = inner, on = on,
      icon = function() local m = mode() return m and m.icon or "self_improvement" end,
      visible = function() return mode() ~= nil end,
      title = function() local m = mode() return m and m.name or "" end,
      subtitle = function() local m = mode() return m and model.line(m) or "" end,
      trailing = P.switch { id = "focus-mode-switch-" .. slot, name = "Mode", on = on,
        on_toggled = function(now) local m = mode() if m then model.set_on(m.id, now) end end },
      on_clicked = function() local m = mode() if m then model.open(m.id) end end }
  end
  modes[#modes + 1] = P.button { id = "focus-add", icon = "add", label = "New mode", on_clicked = model.add,
    visible = function() return #model.modes() < model.MAX end }

  local section = { id = "settings-focus", width = w, title = "Interruptions" }
  for _, control in ipairs(model.controls) do
    local function on() return control.on() == true end
    local trailing
    if control.id == "ringer" then
      trailing = P.button { id = "utilities-toggle-ringer", label = control.status, on_clicked = function() control.set() end }
    else
      trailing = P.switch { id = "utilities-toggle-" .. control.id, name = control.name, on = on, on_toggled = control.set }
    end
    section[#section + 1] = P.row { id = "settings-focus-" .. control.id, width = inner, icon = control.icon, on = on,
      title = control.name, trailing = trailing,
      on_clicked = control.id == "dnd" and function() model.open("dnd") end or nil,
      subtitle = function()
        if control.id == "awake" then return on() and control.status() or "Allow the screen to sleep" end
        if control.id == "ringer" then return "Notification sounds and vibration" end
        return on() and "Notifications stay in history" or "Show notification popups"
      end }
  end

  return P.page { id = "settings-focus-scroll", width = w, height = h, active = model.active,
    P.section(section),
    P.section(modes),
    P.section { id = "focus-session", width = w, title = "A session",
      choices(w, "focus-duration", "How long a mode runs when turned on", model.DURATIONS, model.duration, model.set_duration, 3) },
    P.section { id = "focus-auto", width = w, title = "By itself",
      toggle(w, "focus-sharing", "screen_share", "While sharing the screen", "Stay quiet and hide what cards say",
        model.sharing, model.set_sharing),
      toggle(w, "focus-fullscreen", "fullscreen", "In fullscreen", "Stay quiet; a summary follows",
        model.fullscreen, model.set_fullscreen) },
  }
end

--- A one-line field the card's width, starting from `text()`, sending `set(value)`.
local function field(w, id, placeholder, text, set)
  local node, input = kit.text_field("entry", { id = id, x = 10, y = 3, width = w - 20, height = 30,
    font_family = theme.font, font_size = theme.size.small, placeholder = placeholder,
    color = function() return C.onSurface end, placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end, selection_color = function() return C.primary:alpha(.25) end,
    on_text_changed = set })
  morf.effect("eva.focus.field." .. id, function()
    local now = text()
    if input.text ~= now then input.text = now end
  end, { owner = node })
  return kit.surface { width = w, height = 36, radius = kit.round(10),
    color = function() return C.surfaceContainerHighest end, node }
end

function V.mode(model, w, h)
  local inner = P.inner(w)
  local function get(key) return function() return model.get(key) end end
  local function set(key) return function(value) model.set(key, value) end end
  local function flag(id, icon, name, subtitle, key)
    return toggle(w, "focus-" .. id, icon, name, subtitle, get(key), set(key))
  end

  local SIZE = 44
  local per_row = math.max(1, (inner + theme.space.xs) // (SIZE + theme.space.xs))
  local grid = ui.Item { width = inner, height = (SIZE + theme.space.xs) * math.ceil(#model.ICONS / per_row) }
  for i, icon in ipairs(model.ICONS) do
    local button = L.icon_button { id = "focus-icon-" .. i, width = SIZE, height = SIZE, icon = icon, name = icon,
      on = function() return model.get("icon") == icon end, on_clicked = function() model.set("icon", icon) end }
    button.x = ((i - 1) % per_row) * (SIZE + theme.space.xs)
    button.y = ((i - 1) // per_row) * (SIZE + theme.space.xs)
    ui.reparent(button, grid)
  end

  local allow = { id = "focus-allow", width = w, title = "What comes through",
    choices(w, "focus-urgency", "Urgency", model.URGENCY, get("allow.urgency"), set("allow.urgency"), 2),
    flag("calls", "call", "Calls", "A second call in 15 minutes always rings", "allow.calls"),
    flag("alarms", "alarm", "Alarms", "Alarm notifications come through", "allow.alarms"),
    caption(w, "People: names in a title, separated by commas"),
    field(inner, "focus-people", "Ada, Grace", function() return model.words("allow.people") end,
      function(value) model.set_words("allow.people", value) end),
    caption(w, "Apps"),
  }
  for slot = 1, APPS do
    local function row() return model.apps()[slot] end
    local function on() local r = row() return r ~= nil and model.has("allow.apps", r.key) end
    allow[#allow + 1] = P.row { id = "focus-app-" .. slot, width = inner, icon = "apps", on = on, height = 48,
      visible = function() return row() ~= nil end, title = function() local r = row() return r and r.name or "" end,
      trailing = P.switch { id = "focus-app-switch-" .. slot, name = "Allow app", on = on,
        on_toggled = function() local r = row() if r then model.flip("allow.apps", r.key) end end } }
  end

  local days = { width = inner }
  for day, name in ipairs(model.DAYS) do
    days[#days + 1] = { id = "focus-day-" .. day, label = name:sub(1, 1), accessible_name = name,
      selected = function() return model.has("schedule.days", day) end,
      on_clicked = function() model.flip("schedule.days", day) end }
  end
  local function clock(id, name, key)
    return P.row { id = id, width = inner, icon = "schedule", title = name,
      subtitle = function() return tostring(model.get(key)) end,
      trailing = ui.Row { gap = theme.space.xs, align = "center",
        P.button { id = id .. "-earlier", label = "-30", width = 64, on_clicked = function() model.shift(key, -30) end },
        P.button { id = id .. "-later", label = "+30", width = 64, on_clicked = function() model.shift(key, 30) end } } }
  end
  local schedule = P.section { id = "focus-schedule", width = w, title = "Schedule",
    flag("schedule-on", "event", "On a schedule", model.schedule_text, "schedule.on"),
    flag("schedule-paused", "pause_circle", "Pause it", "Keeps the schedule without using it", "schedule.paused"),
    flag("schedule-charging", "battery_charging_full", "Only while charging", "For a bedtime that waits for the charger",
      "schedule.charging"),
    caption(w, "Days"), P.buttons(days),
    clock("focus-from", "Starts", "schedule.from"), clock("focus-to", "Ends", "schedule.to"),
  }
  local triggers = P.section { id = "focus-triggers", width = w, title = "Comes on with",
    caption(w, "An app opening: window classes, separated by commas"),
    field(inner, "focus-trigger-apps", "steam, obs", function() return model.words("triggers.apps") end,
      function(value) model.set_words("triggers.apps", value) end),
    toggle(w, "focus-trigger-screen", "desktop_windows", "A second screen", "On while docked",
      function() return model.get("triggers.display") == "any" end,
      function(on) model.set("triggers.display", on and "any" or "") end),
    flag("trigger-pad", "sports_esports", "A game controller", "On while one is connected", "triggers.gamepad"),
  }
  local effects = P.section { id = "focus-effects", width = w, title = "While it is on",
    flag("effect-night", "nightlight", "Night light", "Warm the screen", "effects.night"),
    flag("effect-dark", "dark_mode", "Dark theme", "Switch to the dark scheme", "effects.dark"),
    flag("effect-saver", "energy_savings_leaf", "Power saver", "Lower the power profile", "effects.saver"),
    flag("effect-awake", "coffee", "Keep awake", "The screen stays on", "effects.awake"),
    flag("effect-badges", "notifications_paused", "Hide badges", "Counts stay off the bar", "hide_badges"),
    choices(w, "focus-ring", "Ring mode", model.RING, get("effects.ring"), set("effects.ring")),
  }
  return P.page { id = "focus-mode-scroll", width = w, height = h, active = model.active,
    P.section { id = "focus-name", width = w, title = "Mode",
      field(inner, "focus-name-field", "Name", function() return model.get("name") or "" end, set("name")),
      grid,
      P.button { id = "focus-remove", icon = "delete", label = "Remove this mode", visible = model.removable,
        on_clicked = model.remove } },
    P.section(allow), schedule, triggers, effects,
  }
end

return V
