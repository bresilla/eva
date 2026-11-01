-- The night light, the one implementation behind the quick settings tile and
-- eva-nightlight: Hyprland's hyprsunset, told what to do with
-- `hyprctl hyprsunset temperature N` and `hyprctl hyprsunset identity`, a
-- daemon that is not up yet being started through the compositor; the sun's
-- times for a place; and the commands both surfaces take.
--
--   local night = require("lib.services.nightlight").new { run = morf.process.run }
--   night.apply(true, 4000)
local morf = require("morf")

local M = { COOLEST = 6000, WARMEST = 2500, STEP = 100, DEFAULT = 4000, EVERY = 300000 }

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

-- ----------------------------------------------------------------- the sun --

local function rad(d) return d * math.pi / 180 end
local function deg(r) return r * 180 / math.pi end
local function wrap(v, m) return v - m * math.floor(v / m) end

-- The hour in UTC the sun crosses the horizon, or "day" or "night" where it
-- stays above or below it.
local function crossing(rising, lat, lon, day)
  local t = day + ((rising and 6 or 18) - lon / 15) / 24
  local anomaly = 0.9856 * t - 3.289
  local long = wrap(anomaly + 1.916 * math.sin(rad(anomaly)) + 0.020 * math.sin(2 * rad(anomaly)) + 282.634, 360)
  local right = wrap(deg(math.atan(0.91764 * math.sin(rad(long)), math.cos(rad(long)))), 360)
  right = (right + math.floor(long / 90) * 90 - math.floor(right / 90) * 90) / 15
  local sine = 0.39782 * math.sin(rad(long))
  local cosine = math.cos(math.atan(sine, math.sqrt(1 - sine * sine)))
  local hour = (math.cos(rad(90.833)) - sine * math.sin(rad(lat))) / (cosine * math.cos(rad(lat)))
  if hour > 1 then return "night" end
  if hour < -1 then return "day" end
  local angle = deg(math.atan(math.sqrt(1 - hour * hour), hour))
  if rising then angle = 360 - angle end
  return wrap(angle / 15 + right - 0.06571 * t - 6.622 - lon / 15, 24)
end

--- The day of the year in UTC at unix time `now`, from 1.
function M.day_of_year(now)
  local days, year = math.floor(now / 86400), 1970
  while true do
    local long = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
    local length = long and 366 or 365
    if days < length then return days + 1 end
    days, year = days - length, year + 1
  end
end

--- Sunrise and sunset in UTC hours, or "day" or "night" alone where the sun
--- stays.
function M.sun(lat, lon, day)
  local rise = crossing(true, lat, lon, day)
  if type(rise) == "string" then return rise end
  return rise, crossing(false, lat, lon, day)
end

--- "day" or "night" at unix time `now`.
function M.period(lat, lon, now)
  local rise, set = M.sun(lat, lon, M.day_of_year(now))
  if type(rise) == "string" then return rise end
  local hour = (now % 86400) / 3600
  local day
  if rise < set then day = hour >= rise and hour < set else day = hour >= rise or hour < set end
  return day and "day" or "night"
end

--- `hours` as a clock, "07:42".
function M.clock(hours)
  local minutes = math.floor(hours * 60 + 0.5)
  return ("%02d:%02d"):format((minutes // 60) % 24, minutes % 60)
end

--- The time now: EVA_NOW where a test sets it.
function M.now() return tonumber(morf.env("EVA_NOW")) or math.floor(morf.time.now()) end

--- Latitude and longitude written in `where`, or nil.
function M.coordinates(where)
  local lat, lon = tostring(where or ""):match("^%s*(-?%d+%.?%d*)%s*[, ]%s*(-?%d+%.?%d*)%s*$")
  if lat then return tonumber(lat), tonumber(lon) end
end

--- Where the sun is reckoned for: EVA_NIGHTLIGHT_PLACE, or the shell's weather
--- place.
function M.where(config)
  return morf.env("EVA_NIGHTLIGHT_PLACE") or (config and config.get("services.weather_location")) or ""
end

--- `done(lat, lon)` for `where`, a name being looked up by the weather's own
--- lookup; `done(nil, why)` when it cannot be placed.
function M.place(where, done)
  if where == "" then done(nil, "no place: set services.weather_location") return end
  local lat, lon = M.coordinates(where)
  if lat then done(lat, lon) return end
  local weather = require("lib.integrations.weather").new { location = where, fallback = false }
  local answered = false
  local give_up = morf.time.timer(20000, function()
    if not answered then answered = true done(nil, "cannot find " .. where) end
  end, false)
  morf.effect("nightlight.place." .. where, function()
    weather:get()
    if answered or not weather.latitude then return end
    answered = true
    give_up:cancel()
    done(weather.latitude, weather.longitude)
  end)
end

-- ---------------------------------------------------------------- commands --

--- Runs one command on `device` (shell/quick_hardware.lua's night light) and
--- answers in words, or nil and why. Both surfaces come through here.
function M.command(device, how, value)
  if how == "on" then
    if value then device.set_temperature(value) end
    device.set(true)
    return "on"
  elseif how == "off" then
    device.set(false)
    return "off"
  elseif how == "toggle" then
    if value then device.set_temperature(value) end
    device.set(not device.on())
    return device.on() and "on" or "off"
  elseif how == nil or how == "status" then
    return device.on() and "on" or "off"
  elseif how == "temperature" then
    if value then device.set_temperature(value) end
    return tostring(device.temperature())
  elseif how == "follow" then
    if value ~= nil then device.set_follow(value == "on" or value == true) end
    return device.follow() and "on" or "off"
  end
  return nil, "unknown command: " .. tostring(how)
end

--- Follows the sun once: `done(period)`, or `done(nil, why)`.
function M.decide(device, where, done)
  M.place(where, function(lat, lon)
    if not lat then done(nil, lon) return end
    local period = M.period(lat, lon, M.now())
    device.set(period == "night")
    done(period)
  end)
end

--- The sun's times at `where` in words: `done(text)`, or `done(nil, why)`.
function M.times(where, done)
  M.place(where, function(lat, lon)
    if not lat then done(nil, lon) return end
    local rise, set = M.sun(lat, lon, M.day_of_year(M.now()))
    if rise == "day" then done("the sun does not set today")
    elseif rise == "night" then done("the sun does not rise today")
    else done(("sunrise %s\nsunset %s"):format(M.clock(rise), M.clock(set))) end
  end)
end

--- `eva-nightlight`'s command with no shell running, as a job: the shell's own
--- device in a windowless process. `done(text, why)` when it is over.
function M.job(args, done)
  local config = require("config")
  local device = require("quick_hardware").nightlight()
  local how = args[1]
  if how == "times" then M.times(M.where(config), done) return end
  if how == "auto" then M.decide(device, M.where(config), done) return end
  if how == "daemon" then
    local function again()
      M.decide(device, M.where(config), function(_, why)
        if why then morf.log("warn", "eva-nightlight: " .. tostring(why)) end
      end)
    end
    again()
    morf.time.timer(M.EVERY, again, true)
    return
  end
  local text, why = M.command(device, how, args[2])
  -- The device's effect tells the daemon a moment after the change.
  morf.time.timer(400, function() done(text, why) end, false)
end

return M
