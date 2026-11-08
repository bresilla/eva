-- Radios and sound from the search box, through the models the Settings pages
-- use: join a Wi-Fi network, connect a Bluetooth device or a VPN, change the
-- output, the volume, the brightness, and what is playing. A mode holds its model
-- live while it is on show.
local morf = require("morf")
local registry = require("lib.shell.launcher.registry")
local rows = require("lib.shell.launcher.rows")
local run = require("lib.shell.launcher.run")

local M = {}

local row, note = rows.row, rows.note

local function show(key, on) require("presentation").set("launcher." .. key, on) end

local function settings_page(key)
  return function()
    require("utilities").reach(key)
    return "close"
  end
end

-- ------------------------------------------------------------------ wi-fi --

local function wifi_rows(term)
  local model = require("connectivity").model("network")
  if not model.available() then
    return { note("wifi", "Wi-Fi is not available here", "NetworkManager does not answer", "wifi_off") }
  end
  if not model.enabled() then
    return { row { id = "wifi:on", name = "Turn Wi-Fi on", material = "wifi", description = "It is off",
      run = function() model.set_enabled(true) return "keep" end } }
  end
  local list = {}
  for _, ap in ipairs(model.list()) do
    if ap.ssid and ap.ssid ~= "" then
      list[#list + 1] = { ap = ap, name = ap.ssid, description = tostring(ap.security or "") }
    end
  end
  local out = {}
  for _, item in ipairs(rows.fuzzy(list, term)) do
    local ap = item.ap
    local asks = ap.secure and not ap.known and not ap.in_use
    out[#out + 1] = row {
      id = "wifi:" .. ap.view_key, name = ap.ssid, tag = "Wi-Fi", current = ap.in_use, material = model.signal_icon(ap.strength),
      description = (ap.in_use and "Connected" or ap.known and "Saved" or ap.secure and "Needs a password" or "Open")
        .. "  ·  " .. tostring(ap.strength or 0) .. "%",
      run = function()
        if asks then return settings_page("network")() end
        if run.dry() then morf.log("info", "eva: launcher (dry run): join " .. ap.ssid) return "close" end
        model.choose(ap)
        return "close"
      end,
      actions = { { name = "Open the Network page", material = "settings", run = settings_page("network") } },
    }
  end
  if #out == 0 then out[1] = note("wifi", "No network by that name", term, "wifi_find") end
  return out
end

registry.mode { id = "wifi", name = "Wi-Fi", material = "wifi", shape = "soft_burst", words = { "wifi", "wlan" },
  hint = "wifi home  ·  join a network", search = function(term)
    show("network", true)
    return wifi_rows(term)
  end, leave = function() show("network", false) end }

-- -------------------------------------------------------------- bluetooth --

local function bluetooth_rows(term)
  local model = require("connectivity").model("bluetooth")
  if not model.available() then
    return { note("bt", "Bluetooth is not available here", "BlueZ does not answer", "bluetooth_disabled") }
  end
  if not model.enabled() then
    return { row { id = "bt:on", name = "Turn Bluetooth on", material = "bluetooth", description = "It is off",
      run = function() model.set_enabled(true) return "keep" end } }
  end
  local list = {}
  for _, d in ipairs(model.list()) do
    list[#list + 1] = { device = d, name = d.alias or d.name or d.address or "Device", description = tostring(d.address or "") }
  end
  local out = {}
  for _, item in ipairs(rows.fuzzy(list, term)) do
    local d = item.device
    out[#out + 1] = row {
      id = "bt:" .. d.view_key, name = item.name, tag = "Bluetooth", current = d.connected == true,
      material = d.connected and "bluetooth_connected" or "bluetooth",
      description = d.connected and "Connected  ·  Return disconnects" or d.paired and "Paired  ·  Return connects" or "Return pairs it",
      run = function()
        if run.dry() then morf.log("info", "eva: launcher (dry run): bluetooth " .. item.name) return "close" end
        model.choose(d)
        return "close"
      end,
      actions = { { name = "Open the Bluetooth page", material = "settings", run = settings_page("bluetooth") } },
    }
  end
  if #out == 0 then
    out[1] = row { id = "bt:scan", name = "Look for devices", description = term ~= "" and term or "None known yet", material = "bluetooth_searching",
      run = function() model.scan(true) return "keep" end }
  end
  return out
end

registry.mode { id = "bluetooth", name = "Bluetooth", material = "bluetooth", shape = "soft_burst", words = { "bt", "bluetooth" },
  hint = "bt buds  ·  connect a device", search = function(term)
    show("bluetooth", true)
    return bluetooth_rows(term)
  end, leave = function() show("bluetooth", false) end }

-- -------------------------------------------------------------------- vpn --

local function vpn_rows(term)
  local out = {}
  local items = {}
  for _, kind in ipairs { "tunnel", "mesh" } do
    local model = require("net_pages").model(kind)
    for _, r in ipairs(model.list()) do
      items[#items + 1] = { model = model, target = r, name = r.name, description = r.detail or "" }
    end
  end
  for _, item in ipairs(rows.fuzzy(items, term)) do
    local r = item.target
    out[#out + 1] = row {
      id = "vpn:" .. r.key, name = r.name, description = item.description, tag = "VPN", current = r.on == true,
      material = r.icon or "vpn_lock",
      run = function()
        if run.dry() then morf.log("info", "eva: launcher (dry run): vpn " .. r.name) return "close" end
        item.model.toggle(r)
        return "close"
      end,
    }
  end
  if #out == 0 then out[1] = note("vpn", "No VPNs here", "From NetworkManager, Tailscale and the like", "vpn_lock") end
  return out
end

registry.mode { id = "vpn", name = "VPN", material = "vpn_lock", shape = "soft_burst", words = { "vpn", "tunnel" },
  hint = "vpn work  ·  bring a tunnel up or down", search = function(term)
    show("tunnel", true)
    show("mesh", true)
    return vpn_rows(term)
  end, leave = function() show("tunnel", false) show("mesh", false) end }

-- ------------------------------------------------------------------ audio --

local function device_rows(model, term, id, material)
  if not model.available() then
    return { note(id, "Sound is not available here", "PipeWire does not answer", "volume_off") }
  end
  local default = model.default()
  local list = {}
  for _, d in ipairs(model.list()) do
    list[#list + 1] = { device = d, name = d.description or d.name or "Device", description = d.name or "" }
  end
  local out = {}
  for _, item in ipairs(rows.fuzzy(list, term)) do
    local d = item.device
    local current = default ~= nil and default.id == d.id
    out[#out + 1] = row {
      id = id .. ":" .. tostring(d.key), name = item.name, description = current and "In use" or "Return switches to it",
      material = material, tag = "Audio", current = current,
      run = function()
        if run.dry() then morf.log("info", "eva: launcher (dry run): audio " .. item.name) return "close" end
        model.select_device(d)
        return "close"
      end,
    }
  end
  if #out == 0 then out[1] = note(id, "No device by that name", term, material) end
  return out
end

registry.mode { id = "audio", name = "Sound output", material = "speaker", shape = "soft_burst", words = { "audio", "output", "sink", "speaker" },
  hint = "audio headphones  ·  switch the output", search = function(term)
    show("sound", true)
    return device_rows(require("sound_page").output_model(), term, "audio", "speaker")
  end, leave = function() show("sound", false) end }

registry.mode { id = "mic", name = "Sound input", material = "mic", shape = "soft_burst", words = { "mic", "input", "source" },
  hint = "mic usb  ·  switch the microphone", search = function(term)
    show("microphone", true)
    return device_rows(require("sound_page").input_model(), term, "mic", "mic")
  end, leave = function() show("microphone", false) end }

-- ----------------------------------------------------------------- levels --

local function level_mode(id, name, material, word, kind)
  registry.mode { id = id, name = name, material = material, shape = "sunny", words = { word, id },
    hint = word .. " 40  ·  from 0 to 100", search = function(term)
      local model = require("settings_model")
      local now = math.floor((select(1, model.levels[kind]()) or 0) * 100 + 0.5)
      local wanted = tonumber(term)
      if wanted then
        wanted = math.max(0, math.min(100, wanted))
        return { row { id = id, name = name .. " to " .. wanted .. "%", description = "Now " .. now .. "%", material = material,
          run = function() model.levels["set_" .. kind](wanted / 100) return "close" end } }
      end
      local out = { note(id, name .. " is at " .. now .. "%", "Type a number from 0 to 100", material) }
      for _, step in ipairs { 0, 25, 50, 75, 100 } do
        out[#out + 1] = row { id = id .. ":" .. step, name = step .. "%", material = material,
          run = function() model.levels["set_" .. kind](step / 100) return "close" end }
      end
      return out
    end }
end
level_mode("volume", "Volume", "volume_up", "vol", "volume")
level_mode("brightness", "Brightness", "brightness_6", "bright", "brightness")

-- ------------------------------------------------------------------ media --

registry.mode { id = "media", name = "Media", material = "play_circle", shape = "cookie9", words = { "media", "music", "play", "pause", "next" },
  hint = "what is playing: pause, skip", search = function(term)
    local media = require("media_state")
    local active = media.active()
    if not media.something() then return { note("media", "Nothing is playing", "No player is open", "music_off") } end
    local title = tostring(active.title or active.name or "")
    local artist = type(active.artist) == "table" and table.concat(active.artist, ", ") or tostring(active.artist or "")
    local function control(verb)
      return function()
        if run.dry() then morf.log("info", "eva: launcher (dry run): media " .. verb) end
        media.control(verb)
        return "keep"
      end
    end
    local out = {
      row { id = "media:toggle", name = media.playing() and "Pause" or "Play", description = title .. "  ·  " .. artist,
        material = media.playing() and "pause" or "play_arrow", run = control("play_pause") },
      row { id = "media:next", name = "Next", description = title, material = "skip_next", run = control("next") },
      row { id = "media:previous", name = "Previous", description = title, material = "skip_previous", run = control("previous") },
    }
    return rows.fuzzy(out, term, "name")
  end }

return M
