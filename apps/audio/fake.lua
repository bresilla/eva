-- A stand-in for morf.audio where there is no PipeWire, with EVA_FAKE_AUDIO=1:
-- the engine's shape, in three list models, over rows that answer the same
-- calls. The equalizer's curve stays the engine's own.
local morf = require("morf")

local M = {}

local function device(id, kind, name, description, default, volumes)
  local total = 0
  for _, value in ipairs(volumes) do total = math.max(total, value) end
  return { id = id, kind = kind, name = name, description = description, default = default, muted = false,
    volume = total, volumes = volumes, channels = #volumes, icon_name = "audio-card" }
end

local function stream(id, direction, app, binary, media, target, volume)
  return { id = id, direction = direction, app_name = app, app_id = binary, binary = binary, media_name = media,
    device = target, volume = volume, muted = false, channels = 2, pid = 1000 + id, icon_name = binary }
end

--- Puts the stand-in where the sound model reads it.
function M.install()
  local real = morf.audio
  local revision = morf.signal("audio.fake.revision", 0)
  local devices = {
    device(10, "sink", "alsa_output.speakers", "Built-in speakers", true, { 0.7, 0.62 }),
    device(11, "sink", "bluez_output.headset", "Headset", false, { 0.45, 0.45 }),
    device(12, "sink", "alsa_output.hdmi", "Monitor HDMI", false, { 0.8, 0.8 }),
    device(20, "source", "alsa_input.mic", "Built-in microphone", true, { 0.55, 0.6 }),
    device(21, "source", "bluez_input.headset", "Headset microphone", false, { 0.5 }),
    device(22, "source", "alsa_output.speakers.monitor", "Monitor of Built-in speakers", false, { 0.7, 0.62 }),
  }
  local streams = {
    stream(30, "playback", "Firefox", "firefox", "Lo-fi beats to mix to", 10, 0.8),
    stream(31, "playback", "mpv", "mpv", "holiday.mkv", 11, 0.6),
    stream(40, "record", "OBS Studio", "obs", "Desktop capture", 20, 0.9),
    stream(41, "record", "Morf spectrum", "morf.spectrum", "Levels", 10, 1),
  }
  local sinks, sources, rows = morf.list_model({}), morf.list_model({}), morf.list_model({})

  local function update()
    local out, into = {}, {}
    for _, row in ipairs(devices) do
      local list = row.kind == "sink" and out or into
      list[#list + 1] = row
    end
    sinks:replace(out, "id")
    sources:replace(into, "id")
    rows:replace(streams, "id")
    revision:set(revision:get() + 1)
  end

  local function find(list, id)
    for _, row in ipairs(list) do
      if row.id == id then return row end
    end
  end

  local function any(id) return find(devices, id) or find(streams, id) end

  local function default(kind)
    revision:get()
    for _, row in ipairs(devices) do
      if row.kind == kind and row.default then return row end
    end
  end

  morf.audio = {
    sinks = sinks, sources = sources, streams = rows,
    available = function() revision:get() return true end,
    default_sink = function() return default("sink") end,
    default_source = function() return default("source") end,
    device = function(id) revision:get() return find(devices, id) end,
    stream = function(id) revision:get() return find(streams, id) end,
    equalizer_curve = real and real.equalizer_curve,
    set_volume = function(id, value)
      local row = any(id)
      if not row then return false end
      row.volume = value
      if row.volumes then
        for index in ipairs(row.volumes) do row.volumes[index] = value end
      end
      update()
      return true
    end,
    set_mute = function(id, muted)
      local row = any(id)
      if not row then return false end
      row.muted = muted
      update()
      return true
    end,
    set_default = function(id)
      local row = find(devices, id)
      if not row then return false end
      for _, other in ipairs(devices) do
        if other.kind == row.kind then other.default = other.id == id end
      end
      update()
      return true
    end,
    set_channel_volumes = function(id, values)
      local row = find(devices, id)
      if not row then return false end
      row.volumes = values
      update()
      return true
    end,
    move_stream = function(id, target)
      local row = find(streams, id)
      if not row then return false end
      row.device = target
      update()
      return true
    end,
  }
  update()
end

return M
