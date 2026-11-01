-- Networks that want a sign-in first: NetworkManager's word for it when it
-- has one, and with `network.portal_probe` on, one question to the chosen
-- server each time a connection comes up. Either way one notice, and the
-- login page opens from it. Runs on the primary screen; no nodes.
local morf = require("morf")
local config = require("config")
local host = require("lib.services.host")
local check = require("lib.services.net_check")
local M = {}

local shared = morf.shared or morf.signal
--- The network asking: `{ name, login }`, or false.
M.asking = shared("eva.network.portal", false)

local SETTLE_MS = 2500
local timer, probing
local told = {}

local function server() return check.server(config.get("network.portal_server")) end

local function name_of(net)
  local state = net.state
  if state.wifi.connected and state.wifi.ssid ~= "" then return state.wifi.ssid end
  return state.primary.id ~= "" and state.primary.id or "This network"
end

--- Opens the page a network signs in on. True once it is on its way.
function M.open_login()
  local asking = M.asking:get()
  local url = asking and asking.login or server().url
  host.act({ "xdg-open", url })
  return true
end

local function ask(net, login)
  local name = name_of(net)
  M.asking:set { name = name, login = login or false }
  if told[name] then return end
  told[name] = true
  require("notifs").push { app = "Network", summary = "Sign in to " .. name,
    body = "This network wants you to sign in before it lets you online.", icon = "wifi_password", category = "network",
    transient = true, actions = { { key = "open", label = "Sign in" } },
    on_action = function(key) if key == "open" then M.open_login() end end }
end

local function clear()
  M.asking:set(false)
  told = {}
end

-- What a connection coming up asks. Off unless a person turned it on.
local function probe(net)
  if probing then probing:cancel() end
  probing = check.probe(server(), function(state, login)
    probing = nil
    if state == "portal" then ask(net, login)
    elseif state == "online" then clear() end
  end)
end

local function after(net, connected)
  if timer then timer:cancel() end
  timer = morf.time.timer(SETTLE_MS, function()
    timer = nil
    if connected and config.get("network.portal_probe") == true then probe(net) end
  end, false)
end

--- Starts following the network, where this is the primary screen.
function M.start()
  if morf.window.primary and not morf.window.primary() then return false end
  local net = require("services").net
  if not net or not net.state then return false end
  -- `fake-net [SCENE]`: the stand-in network turns; what it was asked either way.
  if host.fake() then
    morf.ipc["fake-net"] = function(scene)
      local fake = require("lib.services.host_fake")
      if scene then fake.set_net(scene) end
      return fake.asked
    end
  end
  local last
  morf.effect("eva.network.portal", function()
    if not net.state.available then return end
    local state, primary = net.state.connectivity, net.state.primary and net.state.primary.path or ""
    local probing_on = config.get("network.portal_probe") == true
    local word = table.concat({ tostring(state), tostring(primary), tostring(probing_on) }, "\n")
    if word == last then return end
    last = word
    morf.time.timer(1, function()
      if state == "portal" then ask(net)
      elseif primary == "" or (state == "full" and not probing_on) then clear() end
      after(net, net.state.available and primary ~= "")
    end, false)
  end)
  return true
end

return M
