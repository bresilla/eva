-- The lid and the power button, as Settings chose: while anything but System
-- is chosen the shell holds logind's inhibitor and acts itself. The inhibitor
-- ends with the shell.
local morf = require("morf")
local config = require("config")
local host = require("lib.services.host")

local M = {}

-- What each choice runs: the session's own commands.
local RUNS = { lock = "lock", suspend = "suspend", hibernate = "hibernate", poweroff = "shutdown" }

--- What the choice for this moment is: the lid's by power source.
function M.lid_choice(on_battery)
  return config.get(on_battery and "power.lid_battery" or "power.lid_ac")
end

--- The session action for a choice, or nil for none.
function M.run_of(choice) return RUNS[choice] end

local function act(choice)
  local id = RUNS[choice]
  if id then require("session").run(id) end
end

local function on_battery()
  local power = require("services").upower
  local display = power and power.state and power.state.display
  return display ~= nil and display.present == true and display.charging ~= true
end

--- Called by the `power-key` verb, which the compositor's binding sends.
function M.power_key() act(config.get("power.button")) end

--- What the shell must take from logind now: only what is chosen for this
--- moment, each lid choice by its power source.
function M.taken(battery)
  local parts = {}
  if M.lid_choice(battery) ~= "system" then parts[#parts + 1] = "handle-lid-switch" end
  if config.get("power.button") ~= "system" then parts[#parts + 1] = "handle-power-key" end
  return table.concat(parts, ":")
end

local function bind_key(on)
  local hyprconf = require("lib.compositor.hyprland_config")
  if not require("input_model").available() then return end
  hyprconf.apply(function(how)
    if how == "lua" then
      if on then return { { eval = 'hl.bind("XF86PowerOff", hl.dsp.exec_cmd("morf ipc call power-key"), { locked = true })' } } end
      return { { eval = 'hl.unbind("XF86PowerOff")' } }
    end
    if on then return { { keyword = "bindl", value = ",XF86PowerOff,exec,morf ipc call power-key" } } end
    return { { keyword = "unbind", value = ",XF86PowerOff" } }
  end)
end

--- Follows the choices, on the primary output.
function M.start()
  if morf.window.primary and not morf.window.primary() then return end
  local ok, login = pcall(function()
    return require("lib.services.logind").connect { dbus = host.fake() and require("lib.services.host_fake").dbus or nil, udev = false }
  end)
  if not ok then return morf.log("info", "eva: no logind: " .. tostring(login)) end
  local lock, held, keyed = nil, "", nil
  morf.effect("eva.lid.inhibit", function()
    local want = M.taken(on_battery())
    local key = config.get("power.button") ~= "system"
    if host.dry() then return end
    if want ~= held then
      if lock then lock.release() lock = nil end
      if want ~= "" then lock = login.inhibit(want, "eva", "Settings chose what they do", "block") end
      held = want
    end
    if key ~= keyed then
      if key or keyed then bind_key(key) end
      keyed = key
    end
  end)
  local closed = login.state.lid_closed == true
  morf.effect("eva.lid.closed", function()
    local now = login.state.lid_closed == true
    if now == closed then return end
    closed = now
    if now then act(M.lid_choice(on_battery())) end
  end)
end

return M
