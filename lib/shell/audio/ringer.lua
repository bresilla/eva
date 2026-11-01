-- Sound, vibrate or silent: how the machine calls for attention -- a
-- phone's ring switch, for any shell.
--
--   local ringer = require("lib.shell.audio.ringer")
--   local ring = ringer.connect { mode = "sound" }  -- where it starts, off a phone
--   ring.state.mode          -- "sound", "vibrate" or "silent"
--   ring.modes()             -- the ones this machine has, in order
--   ring.set("silent")
--   ring.next()              -- sound -> vibrate -> silent -> sound
--   ring.trigger("phone-incoming-call", { timeout = 0 }, function(id) end)
--   ring.stop(id)            -- feedback a trigger left running
--
-- On a phone it is feedbackd's profile (org.sigxcpu.Feedback, the event
-- sounds and haptics phosh and the phone apps use): full, quiet (vibration
-- only) and silent. Without feedbackd there is nothing to vibrate, so the
-- modes are sound and silent, and the mode is the shell's to honour -- a
-- notification, say, plays no sound while it is silent.

local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local ringer = {}

local NAME = "org.sigxcpu.Feedback"
local PATH = "/org/sigxcpu/Feedback"
local IFACE = "org.sigxcpu.Feedback"
local APP = "org.eva.Shell"
local TIMEOUT = 3000
local TO_PROFILE = { sound = "full", vibrate = "quiet", silent = "silent" }
local FROM_PROFILE = { full = "sound", quiet = "vibrate", silent = "silent" }

--- The Material Symbols name for a mode.
function ringer.icon(mode)
  if mode == "vibrate" then return "vibration" end
  if mode == "silent" then return "notifications_off" end
  return "notifications_active"
end

function ringer.connect(options)
  options = options or {}
  local client = dbus_client.new({ dbus = options.dbus, bus = "session" })
  local state = morf.state { mode = options.mode or "sound", feedbackd = false }
  local ring = { state = state }

  local function read()
    if not client.has_owner(NAME) then
      state.feedbackd = false
      return
    end
    state.feedbackd = true
    local p = client.get_all(NAME, PATH, IFACE) or {}
    state.mode = FROM_PROFILE[p.Profile] or state.mode
  end

  --- The modes this machine has: vibrate only where something vibrates.
  function ring.modes()
    if state.feedbackd then return { "sound", "vibrate", "silent" } end
    return { "sound", "silent" }
  end

  function ring.set(mode)
    if not TO_PROFILE[mode] then return nil, "no mode " .. tostring(mode) end
    if mode == "vibrate" and not state.feedbackd then mode = "silent" end
    state.mode = mode
    if state.feedbackd then
      return client.set(NAME, PATH, IFACE, "Profile", TO_PROFILE[mode])
    end
    return true
  end

  --- Plays a feedback event from feedbackd's theme, the profile's choice of
  --- sound, vibration and light. `options.timeout` is seconds, 0 until
  --- `stop`, -1 (the default) once; `options.important` plays it through a
  --- quieter profile. `done(id)` hears the event's id. False without feedbackd.
  function ring.trigger(event, options, done)
    if not state.feedbackd then return false end
    options = options or {}
    local hints = {}
    if options.important then hints.important = true end
    return client.call1_async(NAME, PATH, IFACE, "TriggerFeedback",
      { APP, event, dbus_client.typed("a{sv}", hints), dbus_client.i(options.timeout or -1) }, TIMEOUT,
      function(id) if done then done(id) end end) == true
  end

  --- Ends the feedback of the event `id`.
  function ring.stop(id)
    if not state.feedbackd or id == nil then return false end
    return client.call_async(NAME, PATH, IFACE, "EndFeedback", { dbus_client.u(id) }, TIMEOUT) == true
  end

  --- The next mode round.
  function ring.next()
    local modes = ring.modes()
    local at = 1
    for i, m in ipairs(modes) do if m == state.mode then at = i end end
    return ring.set(modes[at % #modes + 1])
  end

  client.watch_name(NAME, read)
  client.on_properties(NAME, PATH, function(_, changed)
    if changed.Profile then state.mode = FROM_PROFILE[changed.Profile] or state.mode end
  end)
  read()
  return ring
end

return ringer
