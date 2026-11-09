-- The right panel's Notifications page, behind Eva's row and the history's own:
-- how alerts sound, how popups behave, what cards show, how long the history
-- keeps, and the apps that have notified, one page in each. In the page template
-- (themes/layouts/page.lua).
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local L = require("themes.layouts.parts")
local S = require("notification_settings")
local C = theme.color
local V = {}

local APPS = 12

--- A row with a switch: `id`, `icon`, `name`, a line under it, how it reads
--- and how it is set.
local function toggle(w, id, icon, name, subtitle, on, set)
  return P.row { id = id, width = P.inner(w), icon = icon, title = name, subtitle = subtitle, on = on,
    trailing = P.switch { id = id .. "-switch", name = name, on = on, on_toggled = set } }
end

--- A caption and its choices, sharing the width: each choice `{ value, label }`.
local function choices(w, id, title, items, now, pick, per)
  local named = {}
  for i, item in ipairs(items) do named[i] = { item[1], nil, item[2] } end
  return ui.Column { width = P.inner(w), gap = theme.space.xs,
    kit.subtitle { width = P.inner(w), font_size = P.SUB, color = kit.ink("lo"), text = title },
    F.choices { id = id, width = P.inner(w), items = named, per_row = per or #items, now = now, pick = pick } }
end

--- A one-line text field the card's width: `id`, `placeholder`, `on_text`.
local function field(w, id, placeholder, on_text, on_accept)
  local node = kit.text_field("entry", { id = id, x = 10, y = 3, width = w - 20, height = 30,
    font_family = theme.font, font_size = theme.size.small, placeholder = placeholder,
    color = function() return C.onSurface end, placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end, selection_color = function() return C.primary:alpha(.25) end,
    on_text_changed = on_text, on_accepted = on_accept })
  return kit.surface { width = w, height = 36, radius = kit.round(10),
    color = function() return C.surfaceContainerHighest end, node }
end

function V.build(model, w, h)
  local inner = P.inner(w)
  local function setting(key) return function() return model.get(key) end end
  local function setter(key) return function(value) model.set(key, value) end end
  local function flag(id, icon, name, subtitle, key)
    return toggle(w, "notif-" .. id, icon, name, subtitle, setting(key), setter(key))
  end

  local sound = P.section { id = "notif-sound", width = w, title = "Sound",
    flag("sounds", "volume_up", "Notification sounds", function() return "Ring mode: " .. model.ring() end, "sounds"),
    ui.Item { width = inner, height = 52, visible = setting("sounds"),
      kit.slider { id = "notif-volume", accessible_name = "Notification volume", width = inner,
        value = function() return model.get("volume") / 100 end, icon = "volume_down",
        set = function(value) model.set("volume", math.floor(value * 100 + .5)) end } },
    P.row { id = "notif-try", width = inner, icon = "play_arrow", title = "Try the sound", visible = setting("sounds"),
      trailing = P.button { id = "notif-try-button", label = "Play", on_clicked = model.try } },
    flag("cooldown", "volume_down", "Repeats stay quiet", "An app that keeps pinging plays once a minute", "cooldown"),
    flag("flash", "flash_on", "Flash the screen", "A short flash on arrival", "flash"),
    flag("edge", "highlight", "Edge lighting", "The screen's edge glows on arrival", "edge_light"),
  }

  local popups = P.section { id = "notif-popups", width = w, title = "Popups",
    choices(w, "notif-time", "How long they stay", S.TIMES, setting("timeout"), setter("timeout")),
    choices(w, "notif-count", "How many stand at once", S.COUNTS, setting("max_popups"), setter("max_popups")),
    flag("ignore", "timer_off", "Ignore apps' own timers", "Every popup stays the time above", "ignore_app_timeouts"),
    flag("stack", "stacks", "Fold by app", "Three or more from one app become one card", "stack"),
    P.row { id = "notif-position", width = inner, icon = "picture_in_picture", title = "Position",
      subtitle = "Where popups stand", trailing = P.chevron(), on_clicked = model.open_position },
    #morf.screens > 1 and choices(w, "notif-output", "On which screen", model.outputs(), setting("output"), setter("output")) or nil,
  }

  local content = P.section { id = "notif-content", width = w, title = "What cards show",
    flag("actions", "smart_button", "Action buttons", "The buttons apps offer", "actions"),
    choices(w, "notif-keep", "Their buttons keep working for", S.KEEP, setting("keep_actions"), setter("keep_actions")),
    flag("smart", "auto_fix_high", "Codes and links", "Copy a one-time code, open a link", "smart"),
    toggle(w, "notif-hide", "visibility_off", "Hide content", "Cards show only the app until opened",
      function() return model.get("previews") == "hide" end,
      function(on) model.set("previews", on and "hide" or "show") end),
    choices(w, "notif-lock", "On the lock screen", S.LOCK, setting("lock_previews"), setter("lock_previews"), 2),
  }

  local summary = P.section { id = "notif-summary", width = w, title = "Summary",
    require("themes").view("settings_form").field(S.DIGEST, inner),
  }

  local kept = P.section { id = "notif-history", width = w, title = "History",
    flag("keep", "history", "Keep a history", "Off, nothing is kept or written", "history.enabled"),
    flag("dismissed", "playlist_remove", "Keep what you dismiss", "Off, a dismissed popup leaves the history too",
      "history.keep_dismissed"),
    flag("open", "unfold_more", "Open groups", "Every app starts open", "history.open_groups"),
    choices(w, "notif-limit", "How many it keeps", S.LIMITS, setting("history.limit"), setter("history.limit")),
    choices(w, "notif-days", "For how long", S.DAYS, setting("history.days"), setter("history.days")),
    choices(w, "notif-preview", "Lines in a shut group", S.PREVIEWS, setting("history.preview"), setter("history.preview")),
    P.row { id = "notif-clear", width = inner, icon = "delete_sweep", title = "Clear the history",
      trailing = P.button { id = "notif-clear-button", label = "Clear", on_clicked = model.clear_history } },
  }

  local apps = { id = "notif-apps", width = w, title = "Apps" }
  apps[#apps + 1] = kit.text { width = inner, font_size = P.SUB, color = kit.ink("lo"), wrap = true,
    text = "Apps appear here once they have notified.", visible = function() return #model.apps() == 0 end }
  for slot = 1, APPS do
    local function row() return model.apps()[slot] end
    apps[#apps + 1] = P.row { id = "notif-app-" .. slot, width = inner, icon = "apps",
      visible = function() return row() ~= nil end,
      title = function() local r = row() return r and r.name or "" end,
      subtitle = function() local r = row() return r and model.summary(r.key) or "" end,
      trailing = P.chevron(),
      on_clicked = function() local r = row() if r then model.open_app(r.key) end end }
  end

  local pattern = morf.signal("eva.notifications.settings.pattern", "")
  local content_rows = { id = "notif-matches", width = w, title = "Matching text" }
  content_rows[#content_rows + 1] = kit.text { width = inner, font_size = P.SUB, color = kit.ink("lo"), wrap = true,
    text = "A Lua pattern over a notification's title and body, for every app." }
  for slot = 1, 6 do
    local function row() return model.content()[slot] end
    content_rows[#content_rows + 1] = P.row { id = "notif-match-" .. slot, width = inner, icon = "rule",
      visible = function() return row() ~= nil end,
      title = function() local r = row() return r and r.rule.match or "" end,
      subtitle = function() local r = row() return r and model.describe(r.rule) or "" end,
      trailing = P.button { id = "notif-match-remove-" .. slot, label = "Remove", icon = "delete",
        on_clicked = function() local r = row() if r then model.remove_rule(r.index) end end } }
  end
  content_rows[#content_rows + 1] = field(inner, "notif-pattern", "Text to match", function(value) pattern:set(value) end)
  content_rows[#content_rows + 1] = P.buttons { width = inner,
    { id = "notif-add-mute", label = "Mute", on_clicked = function() model.add_rule(pattern:get(), "mute") end },
    { id = "notif-add-priority", label = "Priority", on_clicked = function() model.add_rule(pattern:get(), "priority") end },
    { id = "notif-add-highlight", label = "Highlight", on_clicked = function() model.add_rule(pattern:get(), "highlight") end },
  }

  local server = P.section { id = "notif-server", width = w, title = "Server",
    flag("daemon", "dns", "Serve notifications", "Off, another daemon keeps them", "daemon"),
  }

  return P.page { id = "notif-scroll", width = w, height = h, active = model.active,
    sound, popups, content, summary, kept, P.section(apps), P.section(content_rows), server }
end

--- One app's rules.
function V.app(model, w, h)
  local inner = P.inner(w)
  local function get(field) return function() return model.get(field) end end
  local function set(field) return function(value) model.set(field, value) end end
  local function flag(id, icon, name, subtitle, field)
    return toggle(w, "notif-rule-" .. id, icon, name, subtitle, get(field), set(field))
  end
  local head = P.section { id = "notif-rule-head", width = w,
    P.row { id = "notif-rule-app", width = inner, icon = "apps",
      title = function() local name = model.name() return (name and name ~= "") and name or "No app chosen" end,
      subtitle = function() return model.muted() and "Muted" or "Allowed" end,
      trailing = P.button { id = "notif-rule-reset", label = "Reset", icon = "restart_alt", on_clicked = model.reset } } }

  local mute_row = { width = inner }
  for _, preset in ipairs { { 3600, "1 h" }, { 28800, "8 h" }, { 0, "Forever" } } do
    mute_row[#mute_row + 1] = { id = "notif-rule-mute-" .. preset[1], label = preset[2],
      on_clicked = function() model.mute(preset[1]) end }
  end
  mute_row[#mute_row + 1] = { id = "notif-rule-unmute", label = "Unmute", on_clicked = model.unmute,
    visible = model.muted }

  local alerts = P.section { id = "notif-rule-alerts", width = w, title = "Alerts",
    kit.subtitle { width = inner, font_size = P.SUB, color = kit.ink("lo"), text = "Mute" },
    P.buttons(mute_row),
    flag("popup", "web_asset", "Popups", "Off, it goes straight to the history", "popup"),
    flag("history", "history", "Keep in history", "Off, it leaves no trace", "history"),
    flag("priority", "priority_high", "Priority", "Passes every Focus mode and rises to the top", "priority"),
    flag("digest", "summarize", "In the summary", "Held for the summary at set times", "digest"),
    choices(w, "notif-rule-urgency", "Urgency", S.URGENCY, get("urgency"), set("urgency")),
    choices(w, "notif-rule-time", "How long it stays", S.APP_TIMES, get("timeout"), set("timeout")),
  }
  local sound = P.section { id = "notif-rule-sound", width = w, title = "Sound",
    choices(w, "notif-rule-sound-choice", "Sound", S.APP_SOUND,
      function() local s = model.get("sound") return s == "off" and "off" or "default" end, set("sound")),
    flag("ring", "notifications_active", "Through silent", "Sounds even when the ring mode is silent", "ring"),
    flag("announce", "record_voice_over", "Read aloud", "Says who it is from", "announce"),
  }
  local look = P.section { id = "notif-rule-look", width = w, title = "On the card",
    flag("hide", "visibility_off", "Hide content", "Shows only the app until opened", "hide"),
    flag("actions", "smart_button", "Action buttons", "The buttons this app offers", "actions"),
    flag("highlight", "star", "Highlight", "A stronger card", "highlight"),
  }
  local channels = { id = "notif-rule-channels", width = w, title = "Categories",
    visible = function() return #model.categories() > 0 end }
  for slot = 1, 6 do
    local function category() return model.categories()[slot] end
    local function on() local c = category() return c ~= nil and not model.get("mute", c) end
    channels[#channels + 1] = P.row { id = "notif-rule-channel-" .. slot, width = inner, icon = "label",
      visible = function() return category() ~= nil end, on = on,
      title = function() return category() or "" end,
      trailing = P.switch { id = "notif-rule-channel-switch-" .. slot, name = "Category", on = on,
        on_toggled = function(now) local c = category() if c then model.set("mute", not now, c) end end } }
  end
  return P.page { id = "notif-rule-scroll", width = w, height = h, active = model.active,
    head, alerts, sound, look, P.section(channels) }
end

return V
