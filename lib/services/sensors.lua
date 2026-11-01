-- The accelerometer and the proximity sensor: iio-sensor-proxy,
-- `net.hadess.SensorProxy` on the system bus. A reading only moves while
-- someone holds a claim, so one is taken for as long as a reader wants it and
-- let go after. The service is never started by looking: a name nobody owns
-- reads as no sensor.
--
--   local sensors = require("lib.services.sensors").connect()
--   if sensors.state.accelerometer then sensors.claim() end
--   ui.Text { text = function() return sensors.state.orientation end }
--   if sensors.state.proximity then sensors.claim_proximity() end
--   sensors.state.near        -- something is against the screen
local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local M = {}

local NAME, PATH = "net.hadess.SensorProxy", "/net/hadess/SensorProxy"
local TIMEOUT = 5000

--- Starts watching. `options.dbus` is the bus seam.
function M.connect(options)
  options = options or {}
  local client = dbus_client.new({ dbus = options.dbus, bus = "system" })
  local state = morf.state({ available = false, accelerometer = false, orientation = "undefined",
    proximity = false, near = false })
  local sensors = { state = state }
  local claimed, near_claimed = false, false

  local function read()
    if not client.has_owner(NAME) then
      state.available, state.accelerometer, state.orientation = false, false, "undefined"
      state.proximity, state.near = false, false
      return
    end
    local p = client.get_all(NAME, PATH, NAME)
    state.available = p ~= nil
    state.accelerometer = p ~= nil and p.HasAccelerometer == true
    state.orientation = p and p.AccelerometerOrientation or "undefined"
    state.proximity = p ~= nil and p.HasProximity == true
    state.near = p ~= nil and p.ProximityNear == true
  end

  --- Starts the readings; idempotent. `done(ok, err)`.
  function sensors.claim(done)
    if claimed then return true end
    claimed = true
    return client.call_async(NAME, PATH, NAME, "ClaimAccelerometer", {}, TIMEOUT, function(reply, err)
      if reply == nil then claimed = false end
      if done then done(reply ~= nil, err) end
    end)
  end

  --- Stops them; idempotent.
  function sensors.release(done)
    if not claimed then return true end
    claimed = false
    return client.call_async(NAME, PATH, NAME, "ReleaseAccelerometer", {}, TIMEOUT, function(reply, err)
      if done then done(reply ~= nil, err) end
    end)
  end

  --- Starts the proximity readings; idempotent. `done(ok, err)`.
  function sensors.claim_proximity(done)
    if near_claimed then return true end
    near_claimed = true
    return client.call_async(NAME, PATH, NAME, "ClaimProximity", {}, TIMEOUT, function(reply, err)
      if reply == nil then near_claimed = false end
      if done then done(reply ~= nil, err) end
    end)
  end

  --- Stops them; idempotent. Nothing reads as near once they stop.
  function sensors.release_proximity(done)
    if not near_claimed then return true end
    near_claimed = false
    state.near = false
    return client.call_async(NAME, PATH, NAME, "ReleaseProximity", {}, TIMEOUT, function(reply, err)
      if done then done(reply ~= nil, err) end
    end)
  end

  client.watch_name(NAME, function()
    claimed, near_claimed = false, false
    read()
  end)
  client.on_properties(NAME, PATH, function(_, changed)
    if changed.HasAccelerometer ~= nil then state.accelerometer = changed.HasAccelerometer == true end
    if changed.AccelerometerOrientation ~= nil then state.orientation = changed.AccelerometerOrientation end
    if changed.HasProximity ~= nil then state.proximity = changed.HasProximity == true end
    if changed.ProximityNear ~= nil and near_claimed then state.near = changed.ProximityNear == true end
  end)
  read()
  return sensors
end

return M
