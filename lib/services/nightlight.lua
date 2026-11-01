-- The night light: Hyprland's hyprsunset, told what to do with
-- `hyprctl hyprsunset temperature N` and `hyprctl hyprsunset identity`. A
-- daemon that is not up yet is started through the compositor.
--
--   local night = require("lib.services.nightlight").new { run = morf.process.run }
--   night.apply(true, 4000)
local morf = require("morf")

local M = { COOLEST = 6000, WARMEST = 2500, STEP = 100 }

--- `temperature` held to the range, on its steps.
function M.clamp(temperature)
  local t = tonumber(temperature) or M.COOLEST
  t = math.max(M.WARMEST, math.min(M.COOLEST, t))
  return math.floor(t / M.STEP + 0.5) * M.STEP
end

--- `options`: `run(argv, done)` (a process, `done{ ok }`), `start(temperature)`
--- (the daemon, through the compositor), `delay` (ms between the last change
--- and the command, 120).
function M.new(options)
  local night = {}
  local timer, wanted, sent_on, sent_temperature

  local function send(on, temperature)
    local argv = on and { "hyprctl", "hyprsunset", "temperature", tostring(temperature) }
      or { "hyprctl", "hyprsunset", "identity" }
    options.run(argv, function(result)
      if on and result and result.ok == false and options.start then options.start(temperature) end
    end)
    sent_on, sent_temperature = on, temperature
  end

  --- Tells the daemon, a moment after the last change.
  function night.apply(on, temperature)
    temperature = M.clamp(temperature)
    if sent_on == nil and not on then return end
    if on == sent_on and (not on or temperature == sent_temperature) then return end
    wanted = { on, temperature }
    if timer then timer:cancel() end
    timer = morf.time.timer(options.delay or 120, function()
      timer = nil
      send(wanted[1], wanted[2])
    end, false)
  end

  return night
end

return M
