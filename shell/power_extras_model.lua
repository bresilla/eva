-- What the Power page adds to the power model: the lid and the power button,
-- idle timeouts, the charge limit and the graphics mode.
local morf = require("morf")
local config = require("config")
local extras = require("lib.services.power_extras")
local page_model = require("page_model")

local M = {}

M.ACTIONS = { { "system", "settings_suggest", "System" }, { "nothing", "block", "Nothing" }, { "lock", "lock", "Lock" },
  { "suspend", "bedtime", "Suspend" }, { "hibernate", "downloading", "Hibernate" }, { "poweroff", "power_settings_new", "Power off" } }

local LOGIND = { ignore = "nothing", poweroff = "power off", reboot = "restart", halt = "halt", kexec = "kexec",
  suspend = "suspend", hibernate = "hibernate", ["hybrid-sleep"] = "hybrid sleep",
  ["suspend-then-hibernate"] = "suspend, then hibernate", lock = "lock" }

M.IDLE = { { "idle_lock", "lockTimeout", "Lock after", "lock" }, { "idle_screen", "screenOffTimeout", "Screen off after", "monitor" },
  { "idle_suspend", "suspendTimeout", "Suspend after", "bedtime" } }

--- `seconds` as a person reads it.
function M.duration(seconds)
  if seconds <= 0 then return "Never" end
  if seconds < 60 then return ("%d s"):format(seconds) end
  if seconds % 3600 == 0 then return ("%d h"):format(seconds // 3600) end
  return ("%d min"):format(seconds // 60)
end

--- Adds to `model` (from power_model).
function M.extend(model)
  local page = page_model.new("power", model.active)
  model.say, model.action, model.failed = page.say, page.action, page.failed
  model.note = page.message
  model.ACTIONS, model.IDLE, model.idle_format = M.ACTIONS, M.IDLE, M.duration
  local logind = morf.signal("eva.power.logind", {})
  local charge = morf.signal("eva.power.charge", { supported = false })
  local gpu = morf.signal("eva.power.gpu", { tool = "", modes = {} })
  local function read_charge() extras.charge(function(state) charge:set(state) end) end
  page.on_show(function()
    extras.logind(function(reply) logind:set(reply) end)
    read_charge()
    extras.gpu(function(state) gpu:set(state) end)
  end)

  --- What logind itself does, in words.
  function model.logind_action(field)
    local word = logind:get()[field]
    return word and (LOGIND[word] or word) or nil
  end
  function model.lid_present() return logind:get().HandleLidSwitch ~= nil end
  function model.action_of(key) return config.get("power." .. key) end
  function model.set_action(key, value) config.set("power." .. key, value) end

  local system = extras.idle_system()
  function model.idle_managed() return system ~= nil end
  function model.idle_seconds(entry)
    local chosen = tonumber(config.get("power." .. entry[1])) or -1
    if chosen >= 0 then return chosen end
    return tonumber(system and system[entry[2]]) or 0
  end
  function model.idle_changed()
    for _, entry in ipairs(M.IDLE) do
      if (tonumber(config.get("power." .. entry[1])) or -1) >= 0 then return true end
    end
    return false
  end
  local function send()
    local seconds = {}
    for _, entry in ipairs(M.IDLE) do
      seconds[({ idle_lock = "lock", idle_screen = "screen", idle_suspend = "suspend" })[entry[1]]] = model.idle_seconds(entry)
    end
    return model.action(function(done) extras.idle_apply(seconds, system, done) return true end)
  end
  function model.set_idle(entry, value)
    config.set("power." .. entry[1], value)
    return send()
  end
  --- Back to what the system configuration says.
  function model.idle_reset()
    for _, entry in ipairs(M.IDLE) do config.set("power." .. entry[1], -1) end
    return model.action(function(done) extras.idle_reset(done) return true end)
  end

  function model.charge() return charge:get() end
  function model.set_charge(on)
    return model.action(function(done) extras.set_charge(on, done) return true end, read_charge)
  end
  function model.gpu() return gpu:get() end
  function model.set_gpu(row)
    return model.action(function(done) extras.set_gpu(gpu:get().tool, row.key, done) return true end, function()
      local now = gpu:get()
      gpu:set { tool = now.tool, mode = row.key, modes = now.modes }
      model.say("It takes effect at the next login.")
    end)
  end
  return model
end

return M
