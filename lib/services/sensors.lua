-- The accelerometer, the proximity and the light sensor: iio-sensor-proxy,
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

local M = { BRIGHTNESS_STEP = 0.04, BRIGHTNESS_SETTLE = 1500 }

local NAME, PATH = "net.hadess.SensorProxy", "/net/hadess/SensorProxy"
local TIMEOUT = 5000

-- The dimmest level, and the lux a screen needs all of its light at.
local FLOOR, BRIGHT_LUX = 0.05, 10000

--- The screen's level for `lux`: the eye goes by ratios, so the scale is a log.
function M.brightness_for(lux)
  lux = math.max(0, tonumber(lux) or 0)
  return math.min(1, FLOOR + (1 - FLOOR) * math.log(1 + lux) / math.log(1 + BRIGHT_LUX))
end

--- Starts watching. `options.dbus` is the bus seam.
function M.connect(options)
  options = options or {}
  local client = dbus_client.new({ dbus = options.dbus, bus = "system" })
  local state = morf.state({ available = false, accelerometer = false, orientation = "undefined",
    proximity = false, near = false, light = false, lux = 0 })
  local sensors = { state = state }
  local claimed, near_claimed, lighting = false, false, false

  local function read()
    if not client.has_owner(NAME) then
      state.available, state.accelerometer, state.orientation = false, false, "undefined"
      state.proximity, state.near = false, false
      state.light, state.lux = false, 0
      return
    end
    local p = client.get_all(NAME, PATH, NAME)
    state.available = p ~= nil
    state.accelerometer = p ~= nil and p.HasAccelerometer == true
    state.orientation = p and p.AccelerometerOrientation or "undefined"
    state.proximity = p ~= nil and p.HasProximity == true
    state.near = p ~= nil and p.ProximityNear == true
    state.light = p ~= nil and p.HasAmbientLight == true
    state.lux = p and tonumber(p.LightLevel) or 0
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

  --- Starts the light readings; idempotent. `done(ok, err)`.
  function sensors.claim_light(done)
    if lighting then return true end
    lighting = true
    return client.call_async(NAME, PATH, NAME, "ClaimLight", {}, TIMEOUT, function(reply, err)
      if reply == nil then lighting = false end
      if done then done(reply ~= nil, err) end
    end)
  end

  --- Stops them; idempotent.
  function sensors.release_light(done)
    if not lighting then return true end
    lighting = false
    return client.call_async(NAME, PATH, NAME, "ReleaseLight", {}, TIMEOUT, function(reply, err)
      if done then done(reply ~= nil, err) end
    end)
  end

  client.watch_name(NAME, function()
    claimed, near_claimed, lighting = false, false, false
    read()
  end)
  client.on_properties(NAME, PATH, function(_, changed)
    if changed.HasAccelerometer ~= nil then state.accelerometer = changed.HasAccelerometer == true end
    if changed.AccelerometerOrientation ~= nil then state.orientation = changed.AccelerometerOrientation end
    if changed.HasProximity ~= nil then state.proximity = changed.HasProximity == true end
    if changed.ProximityNear ~= nil and near_claimed then state.near = changed.ProximityNear == true end
    if changed.HasAmbientLight ~= nil then state.light = changed.HasAmbientLight == true end
    if changed.LightLevel ~= nil then state.lux = tonumber(changed.LightLevel) or 0 end
  end)
  read()
  return sensors
end

return M
