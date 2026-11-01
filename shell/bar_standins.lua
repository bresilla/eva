-- Stand-ins for what the bar reads and a sealed session lacks, each behind its
-- own variable. No nodes.
--
--   EVA_FAKE_MEDIA="Title|Artist|Art"   an MPRIS player, playing
--   EVA_FAKE_DEVICES="Name:82:kind,..." connected Bluetooth devices with batteries
--   EVA_FAKE_WEATHER="18:2"             degrees and a WMO code
--   EVA_FAKE_CALL="Name"                a call in progress
--   EVA_FAKE_TIMER="Label:300"          a timer of so many seconds
--
-- `morf ipc call fake-live KIND [VALUE]` moves the call and the timer.
local morf = require("morf")
local M = {}

local function env(name)
  local value = morf.env and morf.env(name)
  if value == nil or value == false or value == "" or value == "0" then return nil end
  return value
end

local function media(spec)
  local title, artist, art = spec:match("^([^|]*)|?([^|]*)|?(.*)$")
  local length = 240
  local state = morf.state { available = true, players = {}, active = { name = "Stand-in", identity = "Stand-in",
    desktop_entry = "", status = "playing", title = title, artist = artist, album_artist = "", album = "",
    art_url = art or "", url = "", track_id = "", playing = true, length = length, position = 96, rate = 1,
    volume = 1, shuffle = false, loop = "none", can_play = true, can_pause = true, can_go_next = true,
    can_go_previous = true, can_seek = true, can_control = true, can_raise = false, ignores_shuffle = false,
    ignores_loop = false } }
  morf.time.timer(1000, function()
    if state.active.playing then state.active.position = (state.active.position + 1) % length end
  end, true)
  local service = { state = state }
  function service.play_pause() state.active.playing = not state.active.playing end
  function service.next() state.active.position = 0 end
  function service.previous() state.active.position = 0 end
  function service.set_position(seconds) state.active.position = seconds end
  return service
end

local function devices(spec)
  local rows = {}
  for name, level, kind in tostring(spec):gmatch("([^:,]+):(%d+):?([%w_-]*)") do
    rows[#rows + 1] = { path = "/fake/" .. #rows, name = name, alias = name, connected = true, has_battery = true,
      battery = tonumber(level), icon = kind }
  end
  return { state = morf.state { available = true, powered = true, connected_count = #rows, devices = rows } }
end

local function call(name)
  local on, muted = morf.signal("eva.fake.call", true), morf.signal("eva.fake.call.muted", false)
  local started = morf.time.now()
  local service = {}
  function service.active() return on:get() end
  function service.name() return name end
  function service.started() return started end
  function service.muted() return muted:get() end
  function service.toggle_mute() muted:set(not muted:get()) end
  function service.hang_up() on:set(false) end
  function service.set(now)
    if now then started = morf.time.now() end
    on:set(now)
  end
  return service
end

local function timer(spec)
  local label, seconds = spec:match("^(.-):(%d+)$")
  local total = tonumber(seconds) or 300
  local running = morf.signal("eva.fake.timer", morf.time.now() + total)
  local service = { armed = function() return false end }
  function service.timer()
    local ends = running:get()
    if not ends then return nil end
    return { label = label or "Timer", ends = ends, total = total }
  end
  function service.cancel_timer() running:set(false) end
  function service.set(now) running:set(now and morf.time.now() + total or false) end
  return service
end

--- Puts the stand-ins asked for on `services`.
function M.apply(services)
  local spec = env("EVA_FAKE_MEDIA")
  if spec then services.media = media(spec) end
  spec = env("EVA_FAKE_DEVICES")
  if spec then services.bt = devices(spec) end
  spec = env("EVA_FAKE_WEATHER")
  if spec then
    local degrees, code = spec:match("^(%-?%d+):?(%d*)$")
    local reading = { available = true, temperature = tonumber(degrees) or 18, code = tonumber(code) or 2, is_day = true,
      place = "Wageningen, Gelderland", condition = "Partly cloudy", units = { temperature = "°C", wind = "km/h" }, daily = {} }
    services.weather = function() return reading end
  end
  spec = env("EVA_FAKE_CALL")
  if spec then services.call = call(spec) end
  spec = env("EVA_FAKE_TIMER")
  if spec then services.alarm = timer(spec) end
  if not (services.call or services.alarm) then return end
  morf.ipc["fake-live"] = function(kind, value)
    local service = kind == "call" and services.call or kind == "timer" and services.alarm
    if service then service.set(value ~= "off") end
    return true
  end
end

return M
