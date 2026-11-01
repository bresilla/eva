-- What a call does to the machine. While anything rings or talks: awake, the
-- screen on, and suspend held off through logind. While talking on the earpiece:
-- the proximity sensor is claimed, and something near blanks the panel.
-- EVA_FAKE_PROXIMITY=1 stands in for the sensor; `phone fake near on` moves it.
local morf = require("morf")
local M = {}

local function inhibitor(flags)
  local handle
  return function(on)
    if on and not handle then
      if flags.dry() then
        morf.log("info", "eva: inhibit sleep for a call (dry run)")
        handle = { release = function() end }
        return
      end
      local ok, login = pcall(function() return require("lib.services.logind").connect() end)
      if ok and login and login.inhibit then
        handle = login.inhibit("sleep:idle", "eva", "A phone call", "block")
      end
    elseif not on and handle then
      handle.release()
      handle = nil
    end
  end
end

function M.start(owner, flags)
  local model = owner.model
  local hold = inhibitor(flags)
  M.held = morf.signal("eva.phone.held", false)
  morf.effect("eva.phone.awake", function()
    local stage = model.stage:get()
    local busy = stage ~= "idle" and stage ~= "ended"
    hold(busy)
    M.held:set(busy)
  end)
  local was_incoming = false
  morf.effect("eva.phone.wake", function()
    local incoming = model.stage:get() == "incoming"
    if incoming and not was_incoming then flags.screen("wake") end
    was_incoming = incoming
  end)

  local sensors
  if flags.flag("EVA_FAKE_PROXIMITY") then
    sensors = { state = morf.state { proximity = true, near = false }, claim_proximity = function() end,
      release_proximity = function() end, standin = true }
  else
    local ok, lib = pcall(require, "lib.services.sensors")
    local connected, reader = false, nil
    if ok then connected, reader = pcall(lib.connect) end
    sensors = connected and reader or nil
  end
  M.sensors = sensors
  if not sensors then return end

  local claimed = false
  morf.effect("eva.phone.proximity", function()
    local talking = model.stage:get() == "talking" and not model.on_speaker()
    local wanted = talking and sensors.state.proximity == true
    if wanted ~= claimed then
      claimed = wanted
      if wanted then sensors.claim_proximity() else sensors.release_proximity() end
    end
    if not sensors.standin then owner.near:set(wanted and sensors.state.near == true) end
    if not wanted and sensors.standin then owner.near:set(false) end
  end)
  local blanked = false
  morf.effect("eva.phone.blank", function()
    local near = owner.near:get()
    if near == blanked then return end
    blanked = near
    if not flags.screen(near and "blank" or "unblank") and morf.output_power then
      pcall(morf.output_power.set, near and "off" or "on")
    end
  end)
end

return M
