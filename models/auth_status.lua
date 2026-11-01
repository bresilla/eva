-- The status row on a login screen: the battery, the kind of network, whether
-- Bluetooth is on and connected. No names leave here: no network's name, no
-- device's, nothing a person at the screen could not see by walking up to the
-- machine. Each reader connects the first time it is on show.
--
-- EVA_FAKE_BATTERY ("64,charging") and EVA_FAKE_STATUS ("wifi,bluetooth") stand
-- in, as they do for the bar.
local morf = require("morf")
local M = {}

local function words()
  local set = {}
  for word in tostring(morf.env("EVA_FAKE_STATUS") or ""):gmatch("[^,%s]+") do set[word] = true end
  return set
end

local function lazily(name)
  local made
  return function()
    if made == nil then
      local ok, service = pcall(function() return require("lib.services." .. name).connect() end)
      made = ok and service or false
    end
    return made or nil
  end
end

--- `options.active` (fn, tracked): reads only while on show. `options.status`:
--- which readings are wanted.
function M.new(options)
  local active, wanted = options.active, options.status or {}
  local fake = words()
  local fake_battery = morf.env("EVA_FAKE_BATTERY")
  local network = lazily("networkmanager")
  local bluetooth = lazily("bluez")
  local last = { battery = {}, network = "", bluetooth = "" }
  local self = {}

  local function read_battery()
    if fake_battery and fake_battery ~= "" then
      local level, state = fake_battery:match("^(%d+),?(%a*)")
      return { present = true, level = tonumber(level) or 0, charging = state == "charging",
        full = state == "full", time = state == "charging" and 2400 or 0 }
    end
    local ok, value = pcall(function() return require("lib.services.sysinfo").battery() end)
    local first = ok and type(value) == "table" and (value.batteries or {})[1]
    if not first then return {} end
    local charging = first.status == "Charging"
    return { present = true, level = math.floor((first.capacity or 0) + .5), charging = charging,
      full = first.status == "Full", time = charging and value.time_to_full or value.time_left or 0 }
  end

  --- `{ present, level, charging, full, time }`, time in seconds.
  function self.battery()
    if wanted.battery == false then return {} end
    if active() then last.battery = read_battery() end
    return last.battery
  end

  --- What the charge comes to in words: "64%" and, charging, how long to full.
  function self.battery_words()
    local b = self.battery()
    if not b.present then return "" end
    local text = ("%d%%"):format(b.level)
    if b.full then return text end
    if b.charging and (b.time or 0) >= 60 then
      local h, m = b.time // 3600, (b.time % 3600) // 60
      return text .. " · " .. (h > 0 and ("%dh %02dm"):format(h, m) or ("%dm"):format(m))
    end
    return text
  end

  function self.battery_icon()
    local b = self.battery()
    if not b.present then return "" end
    if b.charging then return "battery_charging_full" end
    if b.level > 90 then return "battery_full" end
    if b.level > 60 then return "battery_5_bar" end
    if b.level > 30 then return "battery_3_bar" end
    if b.level > 10 then return "battery_2_bar" end
    return "battery_alert"
  end

  local function read_network()
    if fake.wifi then return "network_wifi_3_bar" end
    local net = network()
    if not (net and net.state.available) then return "" end
    local wifi = net.state.wifi
    if wifi and wifi.connected then
      local strength = wifi.strength or 0
      if strength > 75 then return "network_wifi" end
      if strength > 50 then return "network_wifi_3_bar" end
      if strength > 25 then return "network_wifi_2_bar" end
      return "network_wifi_1_bar"
    end
    local wired = net.state.wired
    if wired and wired.connected then return "lan" end
    return "signal_wifi_off"
  end

  --- The network as an icon: strength and kind, never its name.
  function self.network_icon()
    if wanted.network == false then return "" end
    if active() then last.network = read_network() end
    return last.network
  end

  local function read_bluetooth()
    if fake.bluetooth then return "bluetooth_connected" end
    local bt = bluetooth()
    if not (bt and bt.state.available and bt.state.powered) then return "" end
    return (bt.state.connected_count or 0) > 0 and "bluetooth_connected" or "bluetooth"
  end

  --- Bluetooth as an icon, or "" while it is off: never what is connected.
  function self.bluetooth_icon()
    if wanted.bluetooth == false then return "" end
    if active() then last.bluetooth = read_bluetooth() end
    return last.bluetooth
  end
  return self
end

return M
