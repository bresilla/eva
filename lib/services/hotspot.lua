-- Sharing the machine's connection over Wi-Fi: a NetworkManager profile with
-- `mode = "ap"` and `ipv4.method = "shared"`, sent over the system bus so the
-- password is on no command line. NetworkManager keeps the secret in its own
-- store; nothing here writes it anywhere else.
--
--   local hotspot = require("lib.services.hotspot").new(net)
--   hotspot.save("Pocket", "a good password", done)
--   hotspot.start(done)
--
-- The access point lives on the Wi-Fi radio: switching Wi-Fi off takes it
-- down with the rest of the radio's connections.
local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local M = { ID = "eva-hotspot", MIN_PASSWORD = 8, MAX_PASSWORD = 63, MAX_SSID = 32 }

local NM, ROOT = "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager"
local WIRELESS = NM .. ".Device.Wireless"
local SETTINGS, SETTINGS_PATH = NM .. ".Settings", ROOT .. "/Settings"
local CONNECTION = SETTINGS .. ".Connection"
local SECURITY = "802-11-wireless-security"
-- NM_WIFI_DEVICE_CAP_AP: the radio can be an access point.
local CAP_AP = 0x40
local TIMEOUT = 30000

local typed, o = dbus_client.typed, dbus_client.o

--- Why `ssid` and `password` cannot be saved, or nil. An empty password on
--- a profile that has one leaves it as it is (`has_secret`).
function M.check(ssid, password, has_secret)
  if ssid == "" then return "Give it a name" end
  if #ssid > M.MAX_SSID then return "A name is at most 32 bytes" end
  if password == "" then
    return not has_secret and "Give it a password" or nil
  end
  if #password < M.MIN_PASSWORD then return "A password is at least 8 characters" end
  if #password > M.MAX_PASSWORD then return "A password is at most 63 characters" end
  return nil
end

--- The profile as NetworkManager takes it. Without a `password` the saved
--- secret stands: `Update` keeps the secrets of settings that bring none.
function M.settings(ssid, password, uuid)
  local security = { ["key-mgmt"] = "wpa-psk", proto = typed("as", { "rsn" }),
    pairwise = typed("as", { "ccmp" }), group = typed("as", { "ccmp" }) }
  if password and password ~= "" then security.psk = password end
  return {
    connection = { id = M.ID, uuid = uuid, type = "802-11-wireless", autoconnect = false },
    ["802-11-wireless"] = { ssid = typed("ay", ssid), mode = "ap" },
    [SECURITY] = security,
    ipv4 = { method = "shared" },
    ipv6 = { method = "ignore" },
  }
end

local function fresh_uuid()
  local ok, text = pcall(morf.fs.read, "/proc/sys/kernel/random/uuid")
  if ok and type(text) == "string" then return (text:gsub("%s+", "")) end
  local out = {}
  for i = 1, 16 do out[i] = ("%02x"):format(math.random(0, 255)) end
  local hex = table.concat(out)
  return ("%s-%s-4%s-a%s-%s"):format(hex:sub(1, 8), hex:sub(9, 12), hex:sub(14, 16), hex:sub(18, 20), hex:sub(21, 32))
end

--- A hotspot on `net` (lib.services.networkmanager). `options.dbus` is the
--- bus seam.
function M.new(net, options)
  options = options or {}
  local client = dbus_client.new({ dbus = options.dbus, bus = "system" })
  local hotspot = {}
  local capable = {}

  local function snapshot() return net and net.snapshot and net.snapshot() or {} end

  --- The saved profile's row, or nil.
  function hotspot.profile()
    for _, row in ipairs(snapshot().known or {}) do
      if row.id == M.ID then return row end
    end
  end

  --- The first Wi-Fi device that can be an access point, or nil.
  function hotspot.device()
    for _, device in ipairs(snapshot().devices or {}) do
      if device.type == "wifi" and device.managed ~= false then
        if capable[device.path] == nil then
          local caps = client.get(NM, device.path, WIRELESS, "WirelessCapabilities")
          capable[device.path] = type(caps) == "number" and (math.floor(caps) & CAP_AP) ~= 0
        end
        if capable[device.path] then return device end
      end
    end
  end

  --- The active connection's row: `state` says how far along it is.
  function hotspot.active()
    local model = net and net.state and net.state.active_connections
    if not model then return nil end
    for i = 1, model:len() do
      local row = model:get(i)
      if row.id == M.ID then return row end
    end
  end

  --- Saves the profile, new or changed. `done(path, err)`.
  function hotspot.save(ssid, password, done)
    done = done or function() end
    local saved = hotspot.profile()
    local why = M.check(ssid, password, saved ~= nil)
    if why then return nil, why end
    local function finish(reply, err)
      if net and net.refresh then pcall(net.refresh) end
      if reply == nil then return done(nil, err or "NetworkManager refused it") end
      done(saved and saved.path or dbus_client.first(reply))
    end
    if saved then
      return client.call_async(NM, saved.path, CONNECTION, "Update",
        { typed("a{sa{sv}}", M.settings(ssid, password, saved.uuid)) }, TIMEOUT, finish)
    end
    return client.call_async(NM, SETTINGS_PATH, SETTINGS, "AddConnection",
      { typed("a{sa{sv}}", M.settings(ssid, password, fresh_uuid())) }, TIMEOUT, finish)
  end

  --- Brings the saved profile up. `done(active_path, err)`.
  function hotspot.start(done)
    done = done or function() end
    local profile, device = hotspot.profile(), hotspot.device()
    if not profile then return nil, "no profile" end
    if not device then return nil, "no Wi-Fi radio can be an access point" end
    return client.call_async(NM, ROOT, NM, "ActivateConnection",
      { o(profile.path), o(device.path), o("/") }, TIMEOUT, function(reply, err)
        if net and net.refresh then pcall(net.refresh) end
        if reply == nil then return done(nil, err or "no active connection") end
        done(dbus_client.first(reply))
      end)
  end

  --- Takes it down. `done(ok, err)`.
  function hotspot.stop(done)
    done = done or function() end
    local active = hotspot.active()
    if not active then done(true) return true end
    return client.call_async(NM, ROOT, NM, "DeactivateConnection", { o(active.path) }, TIMEOUT,
      function(reply, err)
        if net and net.refresh then pcall(net.refresh) end
        done(reply ~= nil or nil, err)
      end)
  end

  return hotspot
end

return M
