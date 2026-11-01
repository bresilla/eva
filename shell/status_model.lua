-- What a status bar says, as data, and which of it fits. No nodes.
--
-- An indicator is `{ key, icon, tier, label }`, present only while it is
-- active. Its tier says when it collapses into the overflow dot: 1 the rare
-- ones, then 2 Bluetooth, then 3 VPN and Do not disturb. Tier 0, a microphone
-- or camera in use, never does.
local morf = require("morf")

local M = {}

M.KEYS = { "alarm", "night", "awake", "hotspot", "ring", "bluetooth", "vpn", "tor", "dnd", "mic", "camera" }
local LOW = require("battery_status_model").LOW

local function kept(name) return require("themes.session").keep(name, false):get() end
local function fake_set()
  local spec = morf.env and morf.env("EVA_FAKE_STATUS")
  local set = {}
  for word in tostring(spec or ""):gmatch("[^,%s]+") do set[word] = true end
  return set
end
local FAKE = fake_set()

-- A wifi connection that NetworkManager serves as a hotspot, by its name.
local function hotspot(net)
  local rows = net and net.state.available and net.state.active_connections
  if not rows then return false end
  for i = 1, rows:len() do
    local row = rows:get(i)
    if row.type == "802-11-wireless" and (row.id or ""):lower():find("hotspot", 1, true) then return true end
  end
  return false
end

-- A VPN of NetworkManager's, or a mesh or tunnel by its link.
local function vpn(net)
  if net and net.state.available then
    local rows = net.state.vpn_connections
    for i = 1, rows and rows:len() or 0 do if rows:get(i).active then return true end end
    if net.state.devices then net.state.devices:len() end
  end
  local ok, vpns = pcall(require, "lib.services.vpns")
  if not ok then return false end
  return #vpns.links("mesh") > 0 or #vpns.links("tunnel") > 0
end

-- A program recording from a source, the shell's own monitors aside.
local function recording()
  local ok, on = pcall(function()
    local audio = morf.audio
    if not (audio and audio.available() and audio.streams) then return false end
    for i = 1, audio.streams:len() do
      local row = audio.streams:get(i)
      if row.direction == "record" and not (row.app_id or ""):match("^morf%.") then return true end
    end
    return false
  end)
  return ok and on
end

local SOURCES = {
  { key = "alarm", tier = 1, icon = "alarm", label = "Alarm set",
    on = function(s) return s.alarm ~= nil and s.alarm.armed() == true end },
  { key = "night", tier = 1, icon = "nightlight", label = "Night light",
    on = function(s) return s.night_light ~= nil and s.night_light.on() == true end },
  { key = "awake", tier = 1, icon = "coffee", label = "Keep awake",
    on = function() return kept("eva.utilities.awake") end },
  { key = "hotspot", tier = 1, icon = "wifi_tethering", label = "Hotspot",
    on = function(s) return hotspot(s.net) end },
  { key = "ring", tier = 1, label = "Ring mode",
    icon = function(s) return require("lib.shell.audio.ringer").icon(s.ringer and s.ringer.state.mode or "sound") end,
    on = function(s) return s.ringer ~= nil and s.ringer.state.mode ~= "sound" end },
  { key = "bluetooth", tier = 2, icon = "bluetooth_connected", label = "Bluetooth connected",
    on = function(s) return s.bt ~= nil and s.bt.state.available and (s.bt.state.connected_count or 0) > 0 end },
  { key = "vpn", tier = 3, icon = "vpn_key", label = "VPN",
    on = function(s) return vpn(s.net) end },
  { key = "tor", tier = 3, icon = "travel_explore", label = "Tor",
    on = function(s) return s.tor ~= nil and s.tor.on() == true end },
  { key = "dnd", tier = 3, icon = "do_not_disturb_on", label = "Do not disturb",
    on = function() return kept("eva.notifications.dnd") end },
  { key = "mic", tier = 0, icon = "mic", label = "Microphone in use",
    on = recording },
  { key = "camera", tier = 0, icon = "videocam", label = "Camera in use",
    on = function(s) return s.camera ~= nil and s.camera.in_use() == true end },
}

--- The indicators that are active now, left to right. A tracked read.
function M.read(services)
  services = services or require("services")
  local out = {}
  for _, source in ipairs(SOURCES) do
    if FAKE[source.key] or source.on(services) then
      local icon = source.icon
      if type(icon) == "function" then icon = icon(services) end
      out[#out + 1] = { key = source.key, icon = icon, tier = source.tier, label = source.label }
    end
  end
  return out
end

--- What fits in `room` pixels. `sizes`: `icon` (an indicator's width), `dot`
--- (the overflow dot's), `fixed` (what never collapses), `percent` (0 without
--- one) and `level` (the battery's). Returns `{ hidden, dot, percent }`:
--- `hidden[key]` for each indicator in the dot, and whether the dot and the
--- percentage show.
function M.arrange(active, room, sizes)
  local need = sizes.fixed + (sizes.percent or 0) + #active * sizes.icon
  local out = { hidden = {}, dot = false, percent = (sizes.percent or 0) > 0 }
  for tier = 1, 3 do
    for _, item in ipairs(active) do
      if need <= room then break end
      if item.tier == tier then
        out.hidden[item.key] = true
        need = need - sizes.icon
        if not out.dot then out.dot = true need = need + sizes.dot end
      end
    end
  end
  if need > room and out.percent and (sizes.level or 0) > LOW then out.percent = false end
  return out
end

--- A connected Wi-Fi's strength, 0..100, or nil.
function M.wifi_strength(net)
  local state = net.state
  local wifi = state.wifi
  if wifi and wifi.connected then return wifi.strength or 0 end
  local rows = state.access_points
  for i = 1, rows and rows:len() or 0 do
    local ap = rows:get(i)
    if ap.in_use then return ap.strength or 0 end
  end
end

--- The network as an icon: Wi-Fi by its signal, the wire, or "" for neither.
function M.network_icon(net)
  if FAKE.wifi then return "network_wifi_3_bar" end
  if not (net and net.state.available) then return "" end
  local s = M.wifi_strength(net)
  if s then
    if s > 75 then return "network_wifi" end
    if s > 50 then return "network_wifi_3_bar" end
    if s > 25 then return "network_wifi_2_bar" end
    return "network_wifi_1_bar"
  end
  local wired = net.state.wired
  return wired and wired.connected and "lan" or ""
end

--- A phone's mobile network as an icon: "" without a modem.
function M.mobile_icon(modem, airplane)
  if airplane then return "flight" end
  if not (modem and modem.state.available) then return "" end
  local s = modem.state
  if s.locked then return "signal_cellular_connected_no_internet_0_bar" end
  if not s.registered then return "signal_cellular_off" end
  local q = s.signal or 0
  if q > 80 then return "signal_cellular_4_bar" end
  if q > 55 then return "signal_cellular_3_bar" end
  if q > 30 then return "signal_cellular_2_bar" end
  if q > 10 then return "signal_cellular_1_bar" end
  return "signal_cellular_0_bar"
end

return M
