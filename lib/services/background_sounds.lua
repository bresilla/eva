-- Calm noise to sit in: a few seconds of it made here, in steps, then fed to
-- `pw-cat` over and over, so it needs no sound files and has no gap.
--
--   local sounds = require("lib.services.background_sounds").new()
--   sounds.play("rain", 0.3)
--   sounds.stop()
local morf = require("morf")

local M = { RATE = 22050, SECONDS = 8, STEP = 1500, TICK = 8 }

M.KINDS = {
  { id = "rain", name = "Rain", icon = "rainy" },
  { id = "ocean", name = "Ocean", icon = "water" },
  { id = "noise", name = "Noise", icon = "graphic_eq" },
}

-- A second of one end is faded into the other, so the loop has no seam.
local FADE = M.RATE

-- White noise through a light low-pass: rain on a roof.
local function rain()
  local a, b, c = 0, 0, 0
  return function()
    local white = math.random() * 2 - 1
    a = 0.99765 * a + white * 0.0990460
    b = 0.96300 * b + white * 0.2965164
    c = 0.57000 * c + white * 1.0526913
    return (a + b + c + white * 0.1848) * 0.11
  end
end

-- White noise summed up, rising and falling once a loop: waves on a shore.
local function ocean(length)
  local level, at = 0, 0
  return function()
    level = (level + (math.random() * 2 - 1) * 0.02) * 0.998
    at = at + 1
    local swell = math.sin(math.pi * at / length)
    return level * (0.35 + 0.65 * swell * swell) * 2.2
  end
end

local function noise() return function() return (math.random() * 2 - 1) * 0.5 end end

--- A maker of one loop of `kind`: `step()` makes the next samples and answers
--- the finished PCM (signed 16 bits, one channel) once there is no more to do.
function M.maker(kind, seconds)
  local length = math.floor((seconds or M.SECONDS) * M.RATE)
  local fade = math.min(FADE, length // 4)
  local source = kind == "ocean" and ocean(length + fade) or kind == "noise" and noise() or rain()
  local total, made = length + fade, 0
  local samples = {}
  local packed = 0
  local parts = {}

  local function blend()
    for i = 1, fade do
      local mix = i / fade
      samples[i] = samples[i] * mix + samples[length + i] * (1 - mix)
    end
  end

  return function()
    if made < total then
      for _ = 1, math.min(M.STEP, total - made) do
        made = made + 1
        samples[made] = source()
      end
      if made == total then blend() end
      return nil
    end
    local top = math.min(length, packed + M.STEP)
    local bytes = {}
    for i = packed + 1, top do
      local value = math.max(-1, math.min(1, samples[i]))
      bytes[#bytes + 1] = string.pack("<i2", math.floor(value * 32000))
    end
    parts[#parts + 1] = table.concat(bytes)
    packed = top
    if packed < length then return nil end
    return table.concat(parts)
  end
end

--- `options`: `spawn(argv, ended)` (a child with `:write` and `:kill`), `tick`.
function M.new(options)
  options = options or {}
  local spawn = options.spawn or function(argv, ended)
    local ok, child = pcall(morf.process.spawn, { command = argv, stdin = "pipe", on_stderr = function() end,
      on_exit = function() ended() end })
    if ok and child then return child end
    ended()
  end
  local sounds = { running = morf.signal("eva.sounds.running." .. tostring(options), false) }
  local made = {}
  local child, feeder, making, serial = nil, nil, nil, 0

  local function halt()
    serial = serial + 1
    if making then making:cancel() making = nil end
    if feeder then feeder:cancel() feeder = nil end
    if child then
      local running = child
      child = nil
      running:kill("TERM")
    end
  end

  local function start(pcm, level, mine)
    if mine ~= serial then return end
    child = spawn({ "pw-cat", "--playback", "--raw", "--rate", tostring(M.RATE), "--channels", "1",
      "--format", "s16", "--media-role", "Music", "--volume", ("%.2f"):format(level), "-" }, function()
      if mine == serial then
        halt()
        sounds.running:set(false)
      end
    end)
    if not child then return end
    -- A loop in hand, and one more each time one has played.
    child:write(pcm)
    child:write(pcm)
    feeder = morf.time.timer(M.SECONDS * 1000, function()
      if child then child:write(pcm) end
    end, true)
  end

  --- Plays `kind` at `level`, 0 to 1, in place of what was playing.
  function sounds.play(kind, level)
    halt()
    sounds.running:set(true)
    local mine = serial
    if made[kind] then return start(made[kind], level, mine) end
    local step = M.maker(kind)
    making = morf.time.timer(options.tick or M.TICK, function()
      local pcm = step()
      if not pcm then return end
      if making then making:cancel() making = nil end
      made[kind] = pcm
      start(pcm, level, mine)
    end, true)
  end

  --- Stops it.
  function sounds.stop()
    halt()
    sounds.running:set(false)
  end

  return sounds
end

return M
