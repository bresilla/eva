-- What a phone's side keys mean on top of what they already do: the compositor
-- sends each press here (`phone key power`, nix/nixos/phone.nix) and the volume
-- and the screen still answer as ever.
--
--   a call ringing    volume or power silences it
--   a call up         power ends it, when `phone.power_ends_call` says so
--   power twice       `phone.double_power`, a command: the camera, say
--   power and down    a screenshot
--   power five times  `phone.sos`: a countdown to an emergency call
local morf = require("morf")
local config = require("config")
local M = {
  sos = morf.signal("eva.phone.sos", 0),
}

M.PRESSES = 5          -- of power, for help
M.COUNTDOWN = 5        -- seconds to call it off
local WINDOW = 500     -- ms between presses that count as one run
local CHORD = 300      -- ms between two keys held as one

local taps, run_timer, chord_at, sos_timer = 0, nil, nil, nil

local function dry()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

--- Calls off the countdown.
function M.cancel()
  if sos_timer then sos_timer:cancel() sos_timer = nil end
  M.sos:set(0)
end

local function start_sos(owner)
  if sos_timer or not owner.model then return end
  M.sos:set(M.COUNTDOWN)
  sos_timer = morf.time.timer(1000, function()
    local left = M.sos:get() - 1
    M.sos:set(left)
    if left > 0 then return end
    sos_timer:cancel()
    sos_timer = nil
    owner.model.emergency(owner.model.emergency_numbers()[1])
  end, true)
end

local function run_of_presses(owner, count)
  if count == 2 then
    local command = config.get("phone.double_power")
    if type(command) == "table" and #command > 0 then
      if dry() then morf.log("info", "eva: double press (dry run)")
      else morf.process.run(command, {}, function() end) end
    end
  end
end

--- A key came down: `name` is volume-down, volume-up or power.
function M.press(owner, name)
  local model = owner.model
  local stage = model and model.stage:get()
  if stage == "incoming" then model.silence() end
  if name == "volume-down" and chord_at then
    chord_at = nil
    require("capture").shoot("screen", true)
    return "screenshot"
  end
  if name ~= "power" then return stage == "incoming" and "silenced" or "" end
  if stage == "incoming" then return "silenced" end
  if stage == "talking" and config.get("phone.power_ends_call") == true then
    model.hangup()
    return "ended"
  end
  chord_at = true
  morf.time.timer(CHORD, function() chord_at = nil end, false)
  taps = taps + 1
  if run_timer then run_timer:cancel() end
  if taps >= M.PRESSES and config.get("phone.sos") == true then
    taps, run_timer = 0, nil
    start_sos(owner)
    return "sos"
  end
  run_timer = morf.time.timer(WINDOW, function()
    run_of_presses(owner, taps)
    taps, run_timer = 0, nil
  end, false)
  return ""
end

return M
