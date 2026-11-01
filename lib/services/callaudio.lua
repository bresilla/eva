-- A call's sound: callaudiod (org.mobian_project.CallAudio on the session bus),
-- which moves the machine between its media and voice-call audio routes and
-- owns the earpiece, the speaker and the microphone during a call. The bus
-- starts it the first time it is called.
--
--   local audio = require("lib.services.callaudio").connect()
--   audio.call(true)        -- voice-call routing, false to go back
--   audio.speaker(true)
--   audio.mute(true)
--   audio.state.speaker, audio.state.muted, audio.state.ready
local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local M = {}

local NAME = "org.mobian_project.CallAudio"
local PATH = "/org/mobian_project/CallAudio"
local TIMEOUT = 5000
-- CallAudioMode, CallAudioSpeakerState, CallAudioMicState.
local MODE_DEFAULT, MODE_CALL = 0, 1
local SPEAKER_ON = 1
local MIC_OFF = 0

--- `options.dbus` is the bus seam.
function M.connect(options)
  options = options or {}
  local client = dbus_client.new({ dbus = options.dbus, bus = "session" })
  local state = morf.state { ready = false, in_call = false, speaker = false, muted = false }
  local audio = { state = state }
  local function dry()
    if options.dbus then return false end
    local v = morf.env and morf.env("EVA_DRY_RUN")
    return v ~= nil and v ~= "" and v ~= "0"
  end

  local function read(p)
    if type(p.SpeakerState) == "number" and p.SpeakerState ~= 255 then state.speaker = p.SpeakerState == SPEAKER_ON end
    if type(p.MicState) == "number" and p.MicState ~= 255 then state.muted = p.MicState == MIC_OFF end
    if type(p.AudioMode) == "number" and p.AudioMode ~= 255 then state.in_call = p.AudioMode == MODE_CALL end
  end

  local function send(method, argument, done)
    done = done or function() end
    if dry() then
      morf.log("info", "eva: call audio " .. method .. " (dry run)")
      done(false, "dry run")
      return false
    end
    return client.call_async(NAME, PATH, NAME, method, { argument }, TIMEOUT, function(reply, err)
      local fine = reply ~= nil and dbus_client.first(reply) ~= false
      state.ready = reply ~= nil
      done(fine, err)
    end) == true
  end

  --- Voice-call routing on, or back to the default.
  function audio.call(on, done)
    return send("SelectMode", dbus_client.u(on and MODE_CALL or MODE_DEFAULT), function(fine, why)
      if fine then state.in_call = on == true end
      if done then done(fine, why) end
    end)
  end

  function audio.speaker(on, done)
    return send("EnableSpeaker", on == true, function(fine, why)
      if fine then state.speaker = on == true end
      if done then done(fine, why) end
    end)
  end

  function audio.mute(on, done)
    return send("MuteMic", on == true, function(fine, why)
      if fine then state.muted = on == true end
      if done then done(fine, why) end
    end)
  end

  client.on_properties(NAME, PATH, function(interface, changed)
    if interface == NAME then read(changed) end
  end)
  return audio
end

return M
