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

--- The tiles, for the settings model `model`. `gamemode` is the signal game
--- mode keeps.
function M.list(model, gamemode)
  local hotspot, rotation = hardware("hotspot"), hardware("rotation")
  local night, torch, power = hardware("nightlight"), hardware("torch"), hardware("power")
  return {
    {
      -- Sharing the connection over Wi-Fi: a first start needs a name and a
      -- password, on its page.
      id = "hotspot", icon = "wifi_tethering", name = "Hotspot", detail = "hotspot",
      present = function() return hotspot().present() end,
      on = function() return hotspot().on() end,
      set = function(now)
        if now and not hotspot().saved() then model.detail:set("hotspot") return end
        hotspot().set(now)
      end,
      status = function() return hotspot().status() end,
    },
    {
      id = "rotation", name = "Rotation lock",
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
      id = "flashlight", icon = "flashlight_on", name = "Flashlight",
      present = function() return torch().present() end,
      on = function() return torch().on() end,
      set = function(now) torch().set(now) end,
      status = function() return torch().status() end,
    },
    {
      id = "gamemode", icon = "sports_esports", name = "Game mode",
      present = function() return model.can_run("gamemode_on") end,
      on = function() return gamemode:get() end,
      set = function(now)
        model.run(now and "gamemode_on" or "gamemode_off")
        gamemode:set(now == true)
      end,
    },
    {
      id = "screenshot", icon = "screenshot_monitor", name = "Screenshot",
      on = function() return false end,
      set = function() model.shoot() end,
      status = function() return "Region" end,
    },
    {
      id = "record", name = "Screen record",
      icon = function() return recording() and "stop_circle" or "screen_record" end,
      on = recording,
      set = function() model.record() end,
      status = function()
        if not recording() then return "Off" end
        return require("services").duration(capture().elapsed:get())
      end,
    },
    {
      id = "keyboard", icon = "keyboard", name = "On-screen keyboard",
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
      id = "phone", icon = "smartphone", name = "Phone", detail = "phone",
      present = function() return require("phone_model").present() end,
      on = function() return false end,
      set = function() require("pages").reach("phone") end,
      status = function() return "KDE Connect" end,
    },
  }
end

return M
