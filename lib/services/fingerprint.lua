-- The fingerprint reader, through fprintd: what it holds for a person, adding a
-- finger and taking one away. Matching a finger at the lock is PAM's, by way of
-- lib/shell/auth; this only fills what that reads. No nodes.
--
--   local reader = require("lib.services.fingerprint").new { user = "ada" }
--   reader.refresh()
--   reader.state:get()        -- { status, name, stages, fingers, enrolling, note }
--   reader.enroll("right-index-finger")
--
-- `status` is "none" (no fprintd here), "absent" (no reader) or "ready". fprintd
-- starts on a call to it, so nothing here calls it unless it is installed, or
-- under EVA_DRY_RUN unless the stand-in answers.
local morf = require("morf")
local host = require("lib.services.host")

local M = {}

local NAME, MANAGER = "net.reactivated.Fprint", "/net/reactivated/Fprint/Manager"
local DEVICE = NAME .. ".Device"
local PROPERTIES = "org.freedesktop.DBus.Properties"
local QUICK, ASKING = 5000, 120000

M.FINGERS = {
  { "right-index-finger", "Right index" }, { "left-index-finger", "Left index" },
  { "right-thumb", "Right thumb" }, { "left-thumb", "Left thumb" },
  { "right-middle-finger", "Right middle" }, { "left-middle-finger", "Left middle" },
  { "right-ring-finger", "Right ring" }, { "left-ring-finger", "Left ring" },
  { "right-little-finger", "Right little" }, { "left-little-finger", "Left little" },
}

--- How a finger reads.
function M.name_of(finger)
  for _, row in ipairs(M.FINGERS) do
    if row[1] == finger then return row[2] end
  end
  return finger
end

-- What fprintd says as a finger is read: what to tell the person, and whether
-- that reading counted.
local SAID = {
  ["enroll-stage-passed"] = { "Lift it, and touch again", true },
  ["enroll-retry-scan"] = { "That did not read. Touch again" },
  ["enroll-swipe-too-short"] = { "Too short. Touch again" },
  ["enroll-too-short"] = { "Too short. Touch again" },
  ["enroll-finger-not-centered"] = { "Centre your finger, and touch again" },
  ["enroll-remove-and-retry"] = { "Lift your finger, and try again" },
  ["enroll-completed"] = { "Done" },
  ["enroll-failed"] = { "The reader gave up. Try again" },
  ["enroll-data-full"] = { "The reader has no room left" },
  ["enroll-duplicate"] = { "That finger is already enrolled" },
  ["enroll-disconnected"] = { "The reader went away" },
  ["enroll-unknown-error"] = { "The reader failed" },
}

--- Whether this machine has fprintd to ask.
function M.installed()
  if host.fake() then return morf.env("EVA_FAKE_FPRINT") ~= "none" end
  if host.dry() then return false end
  return host.installed("fprintd-enroll")
end

--- A reader for `options.user`. `options.client` is a bus client.
function M.new(options)
  options = options or {}
  local client = options.client or host.bus("system")
  local user = options.user
  local reader = { state = morf.signal("eva.fingerprint.state", { status = "none", fingers = {} }) }
  local device, listening

  local function publish(change)
    local now = {}
    for key, value in pairs(reader.state:get()) do now[key] = value end
    for key, value in pairs(change) do now[key] = value end
    reader.state:set(now)
  end

  local function call(method, arguments, timeout, done)
    local sent, why = client.call_async(NAME, device, DEVICE, method, arguments, timeout, done)
    if not sent and done then done(nil, why) end
  end

  local function read_fingers()
    client.call1_async(NAME, device, DEVICE, "ListEnrolledFingers", { user }, QUICK, function(list)
      publish { status = "ready", fingers = type(list) == "table" and list or {} }
    end)
  end

  --- Reads the reader and its fingers again.
  function reader.refresh()
    if not M.installed() then return publish { status = "none", fingers = {} } end
    local sent = client.call1_async(NAME, MANAGER, NAME .. ".Manager", "GetDefaultDevice", nil, QUICK, function(path)
      device = type(path) == "string" and path or nil
      if not device then return publish { status = "absent", fingers = {} } end
      client.call1_async(NAME, device, PROPERTIES, "GetAll", { DEVICE }, QUICK, function(props)
        props = type(props) == "table" and props or {}
        publish { name = props.name or "Fingerprint reader", stages = props["num-enroll-stages"] or 0 }
        read_fingers()
      end)
    end)
    if not sent then publish { status = "absent", fingers = {} } end
  end

  local function stop_listening()
    if listening then listening.close() end
    listening = nil
  end

  local function finish(note)
    stop_listening()
    publish { enrolling = false, note = note or "" }
    call("Release", nil, QUICK)
    read_fingers()
  end

  local function heard(body)
    local result, done = body[1], body[2]
    local word = SAID[result] or { "Touch again" }
    local now = reader.state:get().enrolling
    if not now then return end
    if done then
      call("EnrollStop", nil, QUICK, function() finish(word[1]) end)
      return
    end
    publish { enrolling = { finger = now.finger, read = now.read + (word[2] and 1 or 0) }, note = word[1] }
  end

  --- Starts adding `finger`: the person is told what to do through `state`.
  function reader.enroll(finger)
    if not device or reader.state:get().enrolling then return false end
    publish { enrolling = { finger = finger, read = 0 }, note = "Asking for the reader" }
    call("Claim", { user }, ASKING, function(claimed, why)
      if not claimed then
        publish { enrolling = false, note = "The reader is busy, or that was refused" }
        morf.log("warn", "eva: cannot claim the reader: " .. tostring(why))
        return
      end
      listening = client.on_signal(NAME, device, DEVICE, "EnrollStatus", heard)
      call("EnrollStart", { finger }, QUICK, function(started)
        if started then publish { note = "Touch the sensor" } else finish("The reader would not start") end
      end)
    end)
    return true
  end

  --- Stops adding a finger.
  function reader.cancel()
    if not reader.state:get().enrolling then return end
    call("EnrollStop", nil, QUICK, function() finish("") end)
  end

  --- Takes `finger` off the reader.
  function reader.remove(finger)
    if not device then return false end
    call("Claim", { user }, ASKING, function(claimed)
      if not claimed then return publish { note = "The reader is busy, or that was refused" } end
      call("DeleteEnrolledFinger", { finger }, QUICK, function()
        call("Release", nil, QUICK)
        read_fingers()
      end)
    end)
    return true
  end

  return reader
end

return M
