-- The Connection help page: the five steps of the troubleshooter, the speed
-- test and the sign-in check. Everything that goes on the network starts from
-- a press here, but for the setting that says otherwise. No nodes.
local morf = require("morf")
local config = require("config")
local services = require("services")
local check = require("lib.services.net_check")
local portal = require("net_portal")
local page_model = require("page_model")
local M = {}

local function blank()
  local out = {}
  for _, row in ipairs(check.STEPS) do out[row[1]] = { state = "idle", words = "" } end
  return out
end

function M.new(active)
  local model = page_model.new("network/help", active)
  model.STEPS, model.SERVERS, model.SERVER_ORDER, model.SPEED = check.STEPS, check.SERVERS, check.SERVER_ORDER, check.SPEED
  model.steps = morf.signal("eva.nethelp.steps", blank())
  model.verdict = morf.signal("eva.nethelp.verdict", false)
  model.walking = morf.signal("eva.nethelp.walking", false)
  model.phase = morf.signal("eva.nethelp.phase", "")
  model.result = morf.signal("eva.nethelp.result", false)
  model.speed_said = morf.signal("eva.nethelp.said", "")
  model.asking = portal.asking
  local stop_walk, stop_speed

  --- The server the sign-in check and the Internet step ask.
  function model.server() return check.server(config.get("network.portal_server")) end
  function model.probing() return config.get("network.portal_probe") == true end
  function model.set_probing(on) config.set("network.portal_probe", on == true) end
  function model.server_key() return config.get("network.portal_server") end
  function model.set_server(key) config.set("network.portal_server", key) end

  --- Whether this connection is the kind that pays by the megabyte.
  function model.metered()
    local net = services.net
    local kind = net and net.state and net.state.primary.type or ""
    return kind == "gsm" or kind == "cdma"
  end

  --- Walks the steps, a press at a time. Again stops the one running.
  function model.troubleshoot()
    if model.walking:get() then
      if stop_walk then stop_walk() end
      model.walking:set(false)
      return false
    end
    model.steps:set(blank())
    model.verdict:set(false)
    model.walking:set(true)
    local function step(name, state, words)
      local next_steps = {}
      for key, value in pairs(model.steps:get()) do next_steps[key] = value end
      next_steps[name] = { state = state, words = words }
      model.steps:set(next_steps)
    end
    stop_walk = check.diagnose(services.net, model.server(), step, function(verdict)
      model.walking:set(false)
      model.verdict:set(verdict)
    end)
    return true
  end

  function model.sign_in() return portal.open_login() end
  --- The page a walk found a sign-in on.
  function model.open_found()
    local verdict = model.verdict:get()
    if verdict and verdict.login then
      portal.asking:set { name = "This network", login = verdict.login }
    end
    return portal.open_login()
  end

  --- Runs the speed test, or stops the one running.
  function model.speed()
    if model.phase:get() ~= "" then
      if stop_speed then stop_speed() end
      model.phase:set("")
      model.speed_said:set("Stopped.")
      return false
    end
    model.result:set(false)
    model.speed_said:set("")
    stop_speed = check.speed(function(name) model.phase:set(name) end, function(result, why)
      model.phase:set("")
      if result then model.result:set(result)
      else model.speed_said:set("It stopped: " .. tostring(why)) end
    end)
    return true
  end

  --- A reading in words.
  function model.rate(value)
    if not value then return "" end
    return value >= 100 and ("%d Mbit/s"):format(math.floor(value + 0.5)) or ("%.1f Mbit/s"):format(value)
  end
  function model.ms(value) return value and ("%d ms"):format(math.floor(value + 0.5)) or "" end
  return model
end

return M
