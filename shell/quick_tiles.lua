-- The tiles beyond the network and sound ones `settings_model` keeps: the
-- machine's hardware (shell/quick_hardware.lua) and what the shell can do at
-- a press. Each has `id`, `name`, `icon`, `on`, `set`, `status`, `present`
-- and, with a page, `detail`.
local morf = require("morf")
local M = {}

local function hardware(name) return function() return require("quick_hardware")[name]() end end
local function capture() return require("capture") end
local function recording()
  local c = capture()
  return c.recording ~= nil and c.recording:get() == true
end
local function keyboard_open()
  local k = require("keyboard")
  return k.opened ~= nil and k.opened:get() == true
end

-- A device of quick_hardware as a tile.
local function switch(id, name, icon, device, detail)
  return { id = id, name = name, icon = icon, detail = detail,
    present = function() return device().present() end,
    on = function() return device().on() end,
    set = function(now) device().set(now) end,
    status = function() return device().status() end }
end

-- A colour filter over the screen, with the others on one page.
local function filter(id, name, icon)
  local filters = hardware("filters")
  return { id = id, name = name, icon = icon, detail = "filters",
    present = function() return filters().present() end,
    on = function() return filters().on(id) end,
    set = function(now) filters().set(id, now) end,
    status = function() return filters().status(id) end }
end

-- An application a press opens, where one of `ids` is installed or, failing
-- that, one that names `word`, and `wanted()` says it is of use. It never lights.
local function app(id, name, icon, ids, word, wanted)
  local function found() return require("apps").find(ids, word) end
  return { id = id, name = name, icon = icon,
    present = function() return found() ~= nil and (wanted == nil or wanted()) end,
    on = function() return false end,
    set = function()
      local entry = found()
      if not entry then return end
      local settings = require("settings_model")
      settings.close_panel()
      if settings.dry_run() then
        morf.log("info", "eva: open " .. entry.id .. " (dry run)")
      else
        require("apps").activate(entry)
      end
    end,
    status = function()
      local entry = found()
      return entry and entry.name or ""
    end }
end

-- A tool of apps/ a press opens, where this install has it, looked for once. It
-- never lights.
local function tool(model, id, name, icon, program, status)
  local function host() return require("lib.services.host") end
  local here
  return { id = id, name = name, icon = icon,
    present = function()
      if here == nil then here = host().tool(program) ~= nil end
      return here
    end,
    on = function() return false end,
    set = function()
      model.close_panel()
      host().open_tool(program)
    end,
    status = function() return status end }
end

-- The launcher, opened on what `query` asks. It never lights.
local function asks(model, id, name, icon, query, status)
  return { id = id, name = name, icon = icon,
    on = function() return false end,
    set = function()
      model.close_panel()
      require("launcher").open_on(query())
    end,
    status = function() return status end }
end

-- A setting of `key` to flip, `detail` its page.
local function setting(id, name, icon, key, detail, present)
  local config = require("config")
  return { id = id, name = name, icon = icon, detail = detail, present = present,
    on = function() return config.get(key) == true end,
    set = function(now) config.set(key, now == true) end,
    status = function() return config.get(key) == true and "On" or "Off" end }
end

--- The tiles, for the settings model `model`. `gamemode` is the signal game
--- mode keeps.
function M.list(model, gamemode)
  local hotspot, rotation = hardware("hotspot"), hardware("rotation")
  local night, torch, power = hardware("nightlight"), hardware("torch"), hardware("power")
  local function prefix() return require("config").get("launcher.action_prefix") end
  return {
    {
      -- Sharing the connection over Wi-Fi: a first start needs a name and a
      -- password, on its page.
      id = "hotspot", icon = "wifi_tethering", name = "Hotspot", detail = "hotspot",
      present = function() return hotspot().present() end,
      on = function() return hotspot().on() end,
      set = function(now)
        if now and not hotspot().saved() then model.request("hotspot") return end
        hotspot().set(now)
      end,
      status = function() return hotspot().status() end,
    },
    {
      id = "rotation", name = "Rotation lock", detail = "displays",
      icon = function() return rotation().on() and "screen_lock_rotation" or "screen_rotation" end,
      present = function() return rotation().present() end,
      on = function() return rotation().on() end,
      set = function(now) rotation().set(now) end,
      status = function() return rotation().status() end,
    },
    {
      id = "nightlight", icon = "nightlight", name = "Night light", detail = "nightlight",
      present = function() return night().present() end,
      on = function() return night().on() end,
      set = function(now) night().set(now) end,
      status = function() return night().status() end,
    },
    {
      id = "powersaver", icon = "energy_savings_leaf", name = "Power saver", detail = "power",
      present = function() return power().present() end,
      on = function() return power().on() end,
      set = function(now) power().set(now) end,
      status = function() return power().status() end,
    },
    {
      id = "flashlight", icon = "flashlight_on", name = "Flashlight", detail = "flashlight",
      present = function() return torch().present() end,
      on = function() return torch().on() end,
      set = function(now) torch().set(now) end,
      status = function() return torch().status() end,
    },
    {
      id = "gamemode", icon = "sports_esports", name = "Game mode", detail = "commands",
      present = function() return model.can_run("gamemode_on") end,
      on = function() return gamemode:get() end,
      set = function(now)
        model.run(now and "gamemode_on" or "gamemode_off")
        gamemode:set(now == true)
      end,
    },
    {
      id = "screenshot", icon = "screenshot_monitor", name = "Screenshot", detail = "capture",
      on = function() return false end,
      set = function() model.shoot() end,
      status = function() return "Region" end,
    },
    {
      id = "record", name = "Screen record", detail = "capture",
      icon = function() return recording() and "stop_circle" or "screen_record" end,
      on = recording,
      set = function() model.record() end,
      status = function()
        if not recording() then return "Off" end
        return require("services").duration(capture().elapsed:get())
      end,
    },
    {
      id = "keyboard", icon = "keyboard", name = "On-screen keyboard", detail = "keyboard",
      on = keyboard_open,
      set = function(now) model.close_panel() require("keyboard").set(now) end,
    },
    {
      id = "notes", icon = "sticky_note_2", name = "Notes", detail = "notes",
      on = function() return false end,
      set = function() require("pages").reach("notes") end,
      status = function() return "Plain files" end,
    },
    {
      id = "linked_phone", icon = "smartphone", name = "Linked phone", detail = "linked_phone",
      present = function() return require("linked_phone_model").present() end,
      on = function() return false end,
      set = function() require("pages").reach("linked_phone") end,
      status = function() return "KDE Connect" end,
    },
    switch("nfc", "NFC", "nfc", hardware("nfc")),
    switch("location", "Location", "location_on", hardware("location")),
    switch("usbtether", "USB tethering", "usb", hardware("tether")),
    switch("datasaver", "Data Saver", "data_saver_on", hardware("datasaver")),
    switch("autobrightness", "Auto brightness", "brightness_auto", hardware("autobrightness")),
    filter("grayscale", "Grayscale", "filter_b_and_w"),
    filter("invert", "Invert colours", "invert_colors"),
    filter("extradim", "Extra dim", "brightness_low"),
    filter("reading", "Reading mode", "menu_book"),
    filter("correction", "Colour correction", "palette"),
    switch("voicenote", "Voice note", "record_voice_over", hardware("voice")),
    switch("sounds", "Background sounds", "waves", hardware("sounds"), "sounds"),
    switch("waydroid", "Waydroid", "android", hardware("waydroid")),
    switch("syncthing", "Syncthing", "sync", hardware("syncthing")),
    switch("ssh", "SSH", "terminal", hardware("ssh")),
    switch("onehanded", "One-handed", "swipe_down", hardware("onehanded")),
    {
      id = "reducemotion", icon = "animation", name = "Reduce motion",
      on = function() return model.reduce_motion() end,
      set = function(now) model.set_reduce_motion(now) end,
      status = function() return model.reduce_motion() and "On" or "Off" end,
    },
    {
      -- The launcher's own calculator, its field ready.
      id = "calculator", icon = "calculate", name = "Calculator",
      on = function() return false end,
      set = function()
        model.close_panel()
        require("launcher").open_on(require("config").get("launcher.action_prefix") .. "calc ")
      end,
      status = function() return "Open" end,
    },
    app("camera", "Camera", "photo_camera", { "org.gnome.Snapshot", "org.postmarketos.Megapixels", "megapixels",
      "org.kde.kamoso", "org.gnome.Cheese", "cheese" }, "camera"),
    app("alarm", "Alarm", "alarm", { "org.gnome.clocks", "org.kde.kclock" }, "alarm"),
    app("cast", "Cast", "cast", { "org.gnome.NetworkDisplays" }),
    app("nearby", "Nearby share", "share", { "org.localsend.localsend_app", "localsend_app", "org.kde.kdeconnect.app",
      "org.kde.kdeconnect-app" }),
    app("recognise", "Recognise music", "music_note", { "com.github.marinm.songrec" }),
    app("printers", "Printers", "print", { "system-config-printer", "org.gnome.Settings.printers" }),
    {
      -- More than one monitor: a press opens their arrangement in Settings.
      id = "displays", name = "Displays", icon = "monitor",
      present = function()
        local rows = require("lib.compositor.hyprland").state.monitors
        return rows ~= nil and rows:len() > 1
      end,
      on = function() return false end,
      set = function() model.request("displays") end,
      status = function() return "Arrange" end,
    },
    asks(model, "timer", "Timer", "timer", function() return prefix() .. " timer " end, "Set one"),
    asks(model, "clipboard", "Clipboard", "content_paste", function() return ";" end, "History"),
    tool(model, "clock", "Clock", "schedule", "clock", "Alarms and timers"),
    tool(model, "qr", "QR code", "qr_code_scanner", "qr", "Read or make one"),
    tool(model, "translate", "Translate", "translate", "translate", "Open"),
    tool(model, "magnifier", "Magnifier", "zoom_in", "zoom", "Open"),
    tool(model, "colorpick", "Colour picker", "colorize", "colorpick", "Open"),
    tool(model, "pomodoro", "Pomodoro", "timelapse", "pomodoro", "Open"),
    tool(model, "breaks", "Breaks", "self_improvement", "breaks", "Rests from the screen"),
    setting("alwayson", "Always on", "nightlight", "lock.always_on.enabled", "lock",
      function() return require("themes.phone_wake").always_on() end),
    setting("highcontrast", "High contrast", "contrast", "appearance.high_contrast", "accessibility"),
    {
      id = "largetext", icon = "format_size", name = "Large text", detail = "accessibility",
      on = function() return (tonumber(require("config").get("appearance.text_scale")) or 1) > 1 end,
      set = function(now) require("config").set("appearance.text_scale", now and 1.25 or 1) end,
      status = function()
        local scale = tonumber(require("config").get("appearance.text_scale")) or 1
        return scale > 1 and ("%d%%"):format(math.floor(scale * 100 + 0.5)) or "Off"
      end,
    },
    {
      id = "screentime", icon = "hourglass_bottom", name = "Screen time", detail = "screen_time",
      on = function() return false end,
      set = function() model.request("screen_time") end,
      status = function()
        local time = require("screen_time_model")
        local _, total = time.report(1)
        return time.words(total) .. " today"
      end,
    },
    {
      id = "bedtime", icon = "bedtime", name = "Bedtime", detail = "screen_time",
      on = function() return require("screen_time_model").bedtime() end,
      set = function(now) require("screen_time_model").set_bedtime(now) end,
      status = function() return require("screen_time_model").bedtime() and "On" or "Off" end,
    },
    {
      id = "lockscreen", icon = "lock", name = "Lock",
      on = function() return false end,
      set = function() model.session_run("lock") end,
      status = function() return "Now" end,
    },
    {
      id = "power", icon = "power_settings_new", name = "Power menu",
      on = function() return false end,
      set = function()
        model.close_panel()
        require("session").drawer.set(true)
      end,
      status = function() return "Sleep, restart, off" end,
    },
    {
      id = "getapps", icon = "add_circle", name = "Get apps",
      present = function() return require("software_model").can_install() end,
      on = function() return false end,
      set = function()
        model.close_panel()
        require("launcher").open_on("> get ")
      end,
      status = function() return "Install" end,
    },
  }
end

return M
