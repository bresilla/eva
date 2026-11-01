-- The lock's corner shortcuts. Each is either safe -- it does its one thing
-- from the lock -- or asks for the password first, and then only the shell
-- opens it. The lock never starts a window while it holds the session: a
-- window could not be seen, and what it started would run behind the lock.
--
--   flashlight   safe: lights the torch
--   media        safe: play or pause
--   camera       after the password
--   command      after the password, unless the person marked it safe
local morf = require("morf")
local M = {}

local function dry()
  local v = morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

local function torch_device()
  if morf.env("EVA_FAKE_HARDWARE") == "1" and dry() then
    local on = morf.signal("lock.torch.fake", false)
    return { device = function() return {} end, on = function() return on:get() end,
      set = function(value) on:set(value) end }
  end
  local ok, torch = pcall(function() return require("lib.services.torch").new() end)
  return ok and torch or nil
end

--- `options`: `prefs`, `media` (play_pause fn, available fn), `ask` (fn given
--- the shortcut: open the way in, and remember it), `run` (argv seam).
function M.new(options)
  local prefs = options.prefs
  local torch
  local self = {}
  local KINDS = {
    flashlight = { icon = function() return torch and torch.on() and "flashlight_on" or "flashlight_off" end,
      name = "Flashlight", safe = true,
      present = function() torch = torch or torch_device() return torch ~= nil and torch.device() ~= nil end,
      press = function() torch.set(not torch.on()) end,
      on = function() return torch ~= nil and torch.on() end },
    media = { icon = "play_pause", name = "Play or pause", safe = true,
      present = function() return options.media_available() end,
      press = function() options.play_pause() end },
    camera = { icon = "photo_camera", name = "Camera", safe = false,
      present = function()
        return type(prefs.camera) == "table" and #prefs.camera > 0
          and (morf.fs.exists("/dev/video0") or morf.env("EVA_FAKE_HARDWARE") == "1")
      end },
    command = { icon = function() return prefs.command.icon ~= "" and prefs.command.icon or "terminal" end,
      name = prefs.command.name ~= "" and prefs.command.name or "Command",
      safe = prefs.command.safe == true,
      present = function() return #prefs.command.argv > 0 end,
      press = function()
        if dry() then morf.log("info", "eva: lock command (dry run)") return end
        options.run(prefs.command.argv)
      end },
  }

  --- The shortcuts that apply here, in the chosen order.
  function self.list()
    local out = {}
    for _, id in ipairs(prefs.shortcuts or {}) do
      local kind = KINDS[id]
      if kind and kind.present() then
        out[#out + 1] = { id = id, icon = kind.icon, name = kind.name, safe = kind.safe, on = kind.on }
      end
    end
    return out
  end

  --- A press. Safe ones act; the rest ask for the password and wait.
  function self.press(id)
    local kind = KINDS[id]
    if not kind then return false end
    if kind.safe then kind.press() return true end
    options.ask(id, kind.name)
    return false
  end
  return self
end

return M
