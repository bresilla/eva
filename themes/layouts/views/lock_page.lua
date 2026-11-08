-- The right panel's Lock screen page, behind Eva's row: what it shows, what
-- stands at its corners, what a stranger may read, and how it opens. In the page
-- template (themes/layouts/page.lua).
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local F = require("themes.layouts.option_rows")

local V = {}

function V.build(model, w, h)
  local inner = P.inner(w)
  local function switch(key, icon, title, subtitle)
    return F.switch { id = "lock-set-" .. key:gsub("%.", "-"), width = inner, icon = icon, title = title,
      subtitle = subtitle, enabled = model.free(key),
      on = function() return model.get(key) == true end, set = function(on) model.set(key, on) end }
  end
  local function line(key, title)
    return F.text { id = "lock-set-" .. key:gsub("%.", "-"), width = inner, title = title, enabled = model.free(key),
      value = function() return model.get(key) or "" end, set = function(text) model.set(key, text) end }
  end

  local notifications = P.section { id = "lock-set-notifications", width = w, title = "Notifications",
    F.choices { id = "lock-set-level", width = inner, icon = "notifications", title = "Show on the lock",
      subtitle = function()
        local level = model.level()
        if level == "all" then return "What they say, readable by anyone at the screen" end
        if level == "senders" then return "Which apps, and how many" end
        if level == "count" then return "How many, and nothing else" end
        return "Nothing at all"
      end,
      choices = model.LEVELS, read = model.level, set = model.set_level,
      enabled = model.free("notifications.level") },
    switch("notifications.new_only", "fiber_new", "Only new ones", "What came since the last unlock"),
    switch("notifications.silent", "notifications_paused", "Silent ones too"),
    F.switch { id = "lock-set-dots", width = inner, icon = "more_horiz", title = "As dots", enabled = model.free("notifications.style"),
      on = function() return model.get("notifications.style") == "dots" end,
      set = function(on) model.set("notifications.style", on and "dots" or "list") end },
  }

  local shows = P.section { id = "lock-set-shows", width = w, title = "Shows",
    switch("status.battery", "battery_full", "Battery"),
    switch("status.network", "wifi", "Network", "Its kind and strength, never its name"),
    switch("status.bluetooth", "bluetooth", "Bluetooth", "On or connected, never to what"),
    switch("status.mode", "do_not_disturb_on", "Mode", "Do not disturb, ringer, airplane"),
    switch("media", "music_note", "What is playing"),
    switch("weather", "cloud", "Weather"),
    switch("avatar", "account_circle", "Your picture"),
    switch("name", "badge", "Your name"),
    switch("clock.twelve_hour", "schedule", "Twelve-hour clock"),
    F.choices { id = "lock-set-clock-position", width = inner, icon = "vertical_align_top", title = "Clock",
      choices = { { "centre", "Centre" }, { "top", "Top" } }, enabled = model.free("clock.position"),
      read = function() return model.get("clock.position") end,
      set = function(where) model.set("clock.position", where) end },
    F.choices { id = "lock-set-clock-size", width = inner, icon = "format_size", title = "Clock size",
      choices = { { .75, "Small" }, { 1, "Medium" }, { 1.25, "Large" } }, enabled = model.free("clock.size"),
      read = function() return model.get("clock.size") end,
      set = function(size) model.set("clock.size", size) end },
    F.choices { id = "lock-set-blur", width = inner, icon = "blur_on", title = "Background blur",
      choices = { { 0, "None" }, { 14, "Light" }, { 28, "Medium" }, { 48, "Heavy" } }, enabled = model.free("blur"),
      read = function() return model.get("blur") end, set = function(amount) model.set("blur", amount) end },
    F.choices { id = "lock-set-tint", width = inner, icon = "opacity", title = "Background tint",
      choices = { { .2, "Light" }, { .4, "Medium" }, { .6, "Deep" }, { .8, "Dark" } }, enabled = model.free("tint"),
      read = function() return model.get("tint") end, set = function(amount) model.set("tint", amount) end },
    line("wallpaper", "A picture of its own, as a path"),
  }

  local corners = { id = "lock-set-corners", width = w, title = "Shortcuts",
    note = "Camera and commands ask for the password first" }
  for _, shortcut in ipairs { { "flashlight", "flashlight_on", "Flashlight" }, { "camera", "photo_camera", "Camera" },
    { "media", "play_pause", "Play or pause" }, { "command", "terminal", "Your command" } } do
    corners[#corners + 1] = F.switch { id = "lock-set-shortcut-" .. shortcut[1], width = inner, icon = shortcut[2],
      title = shortcut[3], enabled = model.free("shortcuts"),
      on = function() return model.shortcut_on(shortcut[1]) end,
      set = function(on) model.set_shortcut(shortcut[1], on) end }
  end
  corners[#corners + 1] = line("command.name", "Name of your command")
  corners[#corners + 1] = F.text { id = "lock-set-command-argv", width = inner, title = "Your command, words split by spaces",
    enabled = model.free("command.argv"), value = model.argv, set = model.set_argv }
  corners[#corners + 1] = switch("command.safe", "gpp_maybe", "Run it without the password",
    "Anyone at the screen can run it")

  local widgets = { id = "lock-set-widgets", width = w, title = "Widgets",
    visible = function() return #model.widgets() > 0 end }
  for index = 1, 6 do
    local function widget() return model.widgets()[index] end
    widgets[#widgets + 1] = F.switch { id = "lock-set-widget-" .. index, width = inner, icon = "widgets",
      title = function() local item = widget() return item and item.name or "" end,
      visible = function() return widget() ~= nil end, enabled = model.free("widgets"),
      on = function() local item = widget() return item ~= nil and model.widget_on(item.id) end,
      set = function(on) local item = widget() if item then model.set_widget(item.id, on) end end }
  end

  local emergency = P.section { id = "lock-set-emergency", width = w, title = "Emergency",
    note = "Anyone at the screen can read this",
    line("emergency.text", "A line under the date"),
    line("emergency.name", "Name"), line("emergency.blood", "Blood type"),
    line("emergency.allergies", "Allergies"), line("emergency.medication", "Medication"),
    line("emergency.contact", "Emergency contact"),
  }

  local opening = P.section { id = "lock-set-opening", width = w, title = "Opening",
    F.choices { id = "lock-set-grace", width = inner, icon = "timer", title = "Require password", per_row = 3,
      subtitle = function()
        local seconds = model.get("grace_seconds")
        if seconds == 0 then return "As soon as it locks" end
        return ("Any key opens it for %d s after an idle lock. Never after sleep"):format(seconds)
      end,
      choices = model.GRACE, read = function() return model.get("grace_seconds") end,
      set = function(seconds) model.set("grace_seconds", seconds) end, enabled = model.free("grace_seconds") },
    F.switch { id = "lock-set-always-on", width = inner, icon = "nightlight", title = "Always on",
      subtitle = "Dark and dim instead of off. Spends power", enabled = model.free("always_on.enabled"),
      visible = function() return require("themes.phone_wake").always_on() end,
      on = function() return model.get("always_on.enabled") == true end,
      set = function(on) model.set("always_on.enabled", on) end },
    switch("readers", "fingerprint", "Fingerprint and face", "Off asks for the password every time"),
    switch("power_buttons", "power_settings_new", "Power buttons on the lock", "Anyone at the screen can turn it off"),
    F.choices { id = "lock-set-blank", width = inner, icon = "monitor", title = "Screen off while locked",
      choices = { { 0, "Never" }, { 30, "30 s" }, { 60, "1 m" }, { 300, "5 m" } }, enabled = model.free("blank_after"),
      read = function() return model.get("blank_after") end,
      set = function(seconds) model.set("blank_after", seconds) end },
    line("force_layout", "Keyboard layout for the password, such as us"),
    F.switch { id = "lock-set-keypad", width = inner, icon = "dialpad", title = "Number pad", subtitle = "For a numeric password",
      enabled = model.free("keypad"), on = function() return model.get("keypad") == "digits" end,
      set = function(on) model.set("keypad", on and "digits" or "text") end },
    F.switch { id = "lock-set-scramble", width = inner, icon = "shuffle", title = "Scramble the number pad",
      subtitle = "The digits change places each time. Only their places: it is checked as before",
      enabled = model.free("scramble"), visible = function() return model.get("keypad") == "digits" end,
      on = function() return model.get("scramble") == true end, set = function(on) model.set("scramble", on == true) end },
    P.row { id = "lock-set-fingerprints", width = inner, icon = "fingerprint", title = "Fingerprints",
      subtitle = "Add a finger, or take one away", trailing = P.chevron(),
      on_clicked = function() require("utilities").request("lock/fingerprint") end },
    P.row { id = "lock-set-pattern", width = inner, icon = "pattern", title = "Pattern",
      subtitle = "Draw or type one before the password", trailing = P.chevron(),
      on_clicked = function() require("utilities").request("lock/pattern") end },
    P.row { id = "lock-set-readers", width = inner, icon = "fingerprint", title = "Readers", trailing = P.chevron(),
      on_clicked = function() require("utilities").request("lock/more") end },
  }

  return P.page { id = "settings-lock-scroll", width = w, height = h,
    notifications, shows, P.section(corners), P.section(widgets), emergency, opening }
end

return V
