-- The power actions a login screen offers, asked of logind: an action shows
-- only if logind answers a plain yes, since nobody is here to answer a polkit
-- prompt. A dry run logs and touches nothing.
local morf = require("morf")
local auth = require("lib.shell.auth")
local M = {}

M.ACTIONS = {
  suspend = { can = "suspend", method = "Suspend", icon = "bedtime", name = "Suspend" },
  reboot = { can = "reboot", method = "Reboot", icon = "restart_alt", name = "Restart" },
  poweroff = { can = "power_off", method = "PowerOff", icon = "power_settings_new", name = "Power off" },
}

local function dry()
  local v = morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

function M.new()
  local login = require("models.logind").connect()
  local self = {}

  --- Whether `id` may be used here. Without logind to ask, nothing may.
  function self.available(id)
    local action = M.ACTIONS[id]
    if not action or not login then return false end
    return login.can(action.can) == "yes"
  end

  --- Whether the machine's firmware setup can be booted into.
  function self.firmware_available()
    return login ~= nil and login.can_firmware() == "yes"
  end

  --- Runs `id`: true, or nil and why.
  function self.run(id)
    local action = M.ACTIONS[id]
    if not action or not self.available(id) then return nil, "Not available here" end
    if dry() then
      morf.log("info", "eva: " .. action.method .. " (dry run)")
      return true
    end
    return auth.power(action.method)
  end

  --- Reboots into the firmware's setup screen.
  function self.firmware()
    if not self.firmware_available() then return nil, "Not available here" end
    if dry() then
      morf.log("info", "eva: RebootToFirmware (dry run)")
      return true
    end
    return login.reboot_to_firmware(false)
  end
  return self
end

return M
