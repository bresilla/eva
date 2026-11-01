-- Where each on-screen display's status comes from: for every kind whether
-- its service is there, what counts as its value, and how it reads. The
-- watch fires a kind only when a value it already knew really moved. Caps
-- and num lock are read from the kernel's LEDs on a short timer.
local morf = require("morf")
local services = require("services")
local remote = require("lib.util.remote")

local M = {}

local GRACE, POLL, RESCAN, ART_WAIT = 2500, 300, 15000, 800
local PROFILE = {
  ["power-saver"] = { "Power saver", "energy_savings_leaf" },
  balanced = { "Balanced", "balance" },
  performance = { "Performance", "rocket_launch" },
}
local RING = { sound = "Sound on", vibrate = "Vibrate", silent = "Silent" }

-- EVA_FAKE_OSD=1: stand-ins for the hardware a sealed session lacks.
local fake = morf.env and morf.env("EVA_FAKE_OSD")
if fake and fake ~= "" and fake ~= "0" then
  local device = { path = "/fake/buds", alias = "Pixel Buds", icon = "audio-card", connected = true }
  services = setmetatable({
    upower = { state = { available = true, profiles = { available = true, active = "balanced" } } },
    bt = { state = { available = true, devices = { len = function() return 1 end, get = function() return device end } } },
    ringer = { state = { mode = "vibrate" } },
    hyprland = { available = function() return true end, state = { keyboard_layout = "English (US)" } },
    media = { state = { available = true, active = { title = "Blue in Green", artist = { "Miles Davis" },
      album = "Kind of Blue", art_url = morf.env("EVA_FAKE_ART") or "", playing = true } } },
    night = { on = function() return true end },
    fake_input = { id = 1, muted = true },
  }, { __index = services })
end

local function input()
  if services.fake_input then return services.fake_input end
  local ok, source = pcall(function() return morf.audio.available() and morf.audio.default_source() end)
  return ok and source or nil
end

local function flag(title, icon, off_icon, on)
  return { shown_in_settings = true,
    present = function() return on() ~= nil end, key = function() return on() end,
    read = function()
      local now = on() == true
      return { icon = now and icon or off_icon, title = title, detail = now and "On" or "Off", on = now }
    end }
end

-- ---------------------------------------------------------------- lock keys --

local lights = require("lib.services.key_lights")
local leds = morf.state { caps = false, num = false, has_caps = false, has_num = false }
local paths = { caps = {}, num = {} }

local function scan()
  paths = lights.scan()
  leds.has_caps, leds.has_num = #paths.caps > 0, #paths.num > 0
end

local function look()
  leds.caps, leds.num = lights.lit(paths.caps), lights.lit(paths.num)
end

-- ------------------------------------------------------------------ sources --

local function dnd()
  local notifs = package.loaded.notifs
  if notifs and notifs.dnd then return notifs.dnd:get() end
end
local function awake()
  local model = package.loaded.settings_model
  if model and model.awake then return model.awake:get() end
end
local function night()
  local model = package.loaded.settings_model
  local control = model and model.CONTROLS and model.CONTROLS.nightlight
  if control and not control.present() then control = nil end
  control = control or services.night
  if control and control.on then return control.on() == true end
end

local function bluetooth_rows()
  local bt = services.bt
  if not (bt and bt.state.available) then return nil end
  local rows, model = {}, bt.state.devices
  for i = 1, model:len() do
    local row = model:get(i)
    if row.connected then rows[#rows + 1] = row end
  end
  return rows
end

--- The device a `bluetooth` display names: the one that came last.
M.device = morf.signal("eva.osd.device", "")

M.sources = {
  mic = { shown_in_settings = true,
    present = function() return input() ~= nil end,
    key = function() local s = input() if s then return s.muted == true, s.id end end,
    read = function()
      local muted = (input() or {}).muted == true
      return { icon = muted and "mic_off" or "mic", title = "Microphone", detail = muted and "Muted" or "Live", on = not muted }
    end },
  caps = { present = function() return leds.has_caps end, key = function() return leds.caps end,
    read = function()
      return { icon = "keyboard_capslock", title = "Caps Lock", detail = leds.caps and "On" or "Off", on = leds.caps }
    end },
  num = { present = function() return leds.has_num end, key = function() return leds.num end,
    read = function() return { icon = "pin", title = "Num Lock", detail = leds.num and "On" or "Off", on = leds.num } end },
  layout = {
    present = function() local h = services.hyprland return h ~= nil and h.available() end,
    key = function()
      local name = services.hyprland.state.keyboard_layout
      if name and name ~= "" then return name end
    end,
    read = function()
      local h = services.hyprland
      return { icon = "keyboard", title = "Keyboard layout", detail = h and h.state.keyboard_layout or "", on = true }
    end },
  profile = { shown_in_settings = true,
    present = function()
      local u = services.upower
      return u ~= nil and u.state.available == true and (u.state.profiles or {}).available == true
    end,
    key = function()
      local active = services.upower.state.profiles.active
      if active and active ~= "" then return active end
    end,
    read = function()
      local u = services.upower
      local p = PROFILE[u and u.state.profiles.active] or { "Balanced", "balance" }
      return { icon = p[2], title = "Power profile", detail = p[1], on = true }
    end },
  ring = { shown_in_settings = true,
    present = function() return services.ringer ~= nil end,
    key = function() return services.ringer.state.mode end,
    read = function()
      local mode = services.ringer and services.ringer.state.mode or "sound"
      local ok, ringer = pcall(require, "lib.shell.audio.ringer")
      return { icon = ok and ringer.icon(mode) or "notifications_active", title = "Ring mode",
        detail = RING[mode] or mode, on = mode == "sound" }
    end },
  bluetooth = {
    present = function() return bluetooth_rows() ~= nil end,
    key = function()
      local rows, ids = bluetooth_rows(), {}
      for i, row in ipairs(rows or {}) do ids[i] = row.path or row.address or row.alias end
      table.sort(ids)
      return table.concat(ids, "\n")
    end,
    -- A device that was not there before, unless the headphones display says it.
    fresh = function(was, _)
      local known = {}
      for id in was:gmatch("[^\n]+") do known[id] = true end
      local headset = require("osd_model").enabled("headphones") and "^audio%-head" or "^$"
      for _, row in ipairs(bluetooth_rows() or {}) do
        local id = row.path or row.address or row.alias
        if not known[id] and not (row.icon or "-"):match(headset) then
          M.device:set(row.alias or row.name or "Device")
          return true
        end
      end
      return false
    end,
    read = function()
      local name = M.device:get()
      if name == "" then
        local rows = bluetooth_rows()
        name = rows and rows[1] and (rows[1].alias or rows[1].name) or ""
      end
      if name == "" then return { icon = "bluetooth", title = "Bluetooth", detail = "Nothing connected", on = false } end
      return { icon = "bluetooth_connected", title = "Connected", detail = name, on = true }
    end },
  dnd = flag("Do not disturb", "notifications_off", "notifications", dnd),
  awake = flag("Keep awake", "coffee", "bedtime", awake),
  night = flag("Night light", "nightlight", "light_mode", night),
}

-- The headphones: what shell/headphones.lua last heard.
M.sources.headphones = {
  present = function() return package.loaded.headphones ~= nil end,
  read = function()
    local device = package.loaded.headphones and package.loaded.headphones.device
    local earbuds = device and device.kind == "earbuds"
    local name = device and device.name or ""
    return { icon = earbuds and "earbuds" or "headphones", title = earbuds and "Earbuds connected" or "Headphones connected",
      detail = name ~= "" and name or "Connection preview", on = true }
  end }

-- -------------------------------------------------------------- now playing --

local function player()
  local media = services.media
  if media and media.state.available ~= false and media.state.active then return media.state.active end
end
local function artists(a)
  local names = a.artist
  if type(names) == "table" then return table.concat(names, ", ") end
  return names or ""
end

--- The local file of the track's cover, or "" while there is none yet.
function M.artwork()
  local a = player()
  local url = a and a.art_url or ""
  if url == "" then return "" end
  local ok, file = pcall(remote.file, url)
  return ok and file or ""
end

M.sources.media = {
  present = function() return player() ~= nil end,
  read = function()
    local a = player() or {}
    if (a.title or "") == "" then return { icon = "music_note", title = "Nothing playing", detail = "", note = "", on = false } end
    return { icon = "music_note", title = a.title, detail = artists(a), note = a.album or "", on = true }
  end }

-- ------------------------------------------------------------------- watch --

local armed, watching = false, false
local seen, scopes = {}, {}
local poll

local function follow(kind, source, fire)
  morf.effect("eva.osd.source." .. kind, function()
    if not source.present() then seen[kind] = nil return end
    local now, scope = source.key()
    if now == nil then return end
    local was, was_scope = seen[kind], scopes[kind]
    seen[kind], scopes[kind] = now, scope
    if was == nil or was == now or scope ~= was_scope or not armed then return end
    if source.fresh and not source.fresh(was, now) then return end
    fire(kind)
  end)
end

-- A track shows once, when its art has come or it has been waited for.
local function follow_media(fire)
  local shown, shown_art, waiting, timed_out
  local waited = morf.signal("eva.osd.art_waited", 0)
  morf.effect("eva.osd.source.media", function()
    waited:get()
    local a = player()
    if not a or (a.title or "") == "" then return end
    local key = a.title .. "\n" .. artists(a)
    local url = a.art_url or ""
    if shown == nil or not armed then shown, shown_art = key, url return end
    if key == shown then return end
    if not a.playing then return end
    local art_is_new = url ~= "" and url ~= shown_art and M.artwork() ~= ""
    if not (art_is_new or timed_out == key) then
      if waiting ~= key then
        waiting = key
        morf.time.timer(ART_WAIT, function()
          timed_out = key
          waited:set(waited:get() + 1)
        end, false)
      end
      return
    end
    shown, shown_art, waiting, timed_out = key, url, nil, nil
    fire("media")
  end)
end

-- The lock keys are read only where they would show, and read afresh when
-- that screen takes over.
local function follow_leds()
  morf.effect("eva.osd.leds", function()
    local wanted = (leds.has_caps or leds.has_num) and services.here()
    if wanted and not poll then
      look()
      seen.caps, seen.num = leds.caps, leds.num
      poll = morf.time.timer(POLL, look, true)
    elseif not wanted and poll then
      poll:cancel()
      poll = nil
    end
  end)
end

--- Starts following every source; `fire(kind)` hears each real change. What
--- each reads at first, and for a moment after while services report in, is
--- taken as how things are.
function M.watch(fire)
  if watching then return end
  watching = true
  scan()
  morf.time.timer(RESCAN, scan, true)
  morf.time.timer(GRACE, function() armed = true end, false)
  for kind, source in pairs(M.sources) do
    if source.key then follow(kind, source, fire) end
  end
  follow_media(fire)
  follow_leds()
end

return M
