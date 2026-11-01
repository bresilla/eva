-- The charge limit and adaptive charging: state and actions, no nodes.
--
-- `battery.limit` is the person's (100 for none, 0 leaves the kernel's as it
-- is) and is written where this session may. With `battery.adaptive` it waits at HOLD
-- through the WINDOW before `battery.ready` (minutes after midnight), and goes
-- on to the limit in time to reach it by then.
--
-- `route()` says what this machine allows: "file" (the kernel's threshold is
-- writable here), "upower" (UPower's own switch over fixed thresholds),
-- "locked" (the kernel has one, this session may not write it) or "" (none).
local morf = require("morf")
local config = require("config")
local charger = require("lib.services.charger")

local M = { HOLD = 80, LOWEST = charger.LOWEST, WINDOW = 480, LEAD = 60, STEP = 5, TICK = 300000, READY_STEP = 30 }

local route = morf.signal("eva.charge.route", "")
local threshold = morf.signal("eva.charge.upower", {})
M.message = morf.signal("eva.charge.message", "")
local written, ticker

local function dry()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end
local function upower() return require("services").upower end
local function stand_in()
  local u = upower()
  return u ~= nil and u.power_supply ~= nil
end
local function dir()
  local u = upower()
  return u and u.power_supply or charger.DIR
end

-- UPower's path for the machine's own battery, or nil.
local function battery_path()
  local u = upower()
  local rows = u and u.state and u.state.devices
  for i = 1, rows and rows.len and rows:len() or 0 do
    local row = rows:get(i)
    if row.kind == "battery" and row.power_supply ~= false then return row.path end
  end
end

--- What the kernel's limit should be. `c`: `limit`, `adaptive`, `plugged`,
--- `now` and `ready` (minutes after midnight), `size` (Wh), `watts`.
function M.target(c)
  if not c.adaptive or not c.plugged or c.limit <= M.HOLD then return c.limit end
  local left = (c.ready - c.now) % 1440
  if left > M.WINDOW then return c.limit end
  local need = charger.seconds_to(M.HOLD, c.limit, c.size, c.watts) / 60
  if need <= 0 then need = M.LEAD end
  return left <= need and c.limit or M.HOLD
end

local function minutes_now()
  local h, m = morf.time.format("%H:%M"):match("(%d+):(%d+)")
  return tonumber(h) * 60 + tonumber(m)
end

local function chosen() return tonumber(config.get("battery.limit")) or 0 end

--- The limit: the person's, else the kernel's, 100 for none.
function M.limit()
  local set = chosen()
  if set > 0 then return set end
  return charger.read(dir()).limit or 100
end

--- Whether adaptive charging is on.
function M.adaptive() return config.get("battery.adaptive") == true end

--- Minutes after midnight it should be done by.
function M.ready() return tonumber(config.get("battery.ready")) or 420 end

--- The time it should be done by, in words.
function M.ready_text()
  local at = M.ready()
  return ("%02d:%02d"):format(at // 60, at % 60)
end

--- What this machine allows.
function M.route() return route:get() end

--- Whether a charge limit is on.
function M.on()
  if route:get() == "upower" then return threshold:get().enabled == true end
  return M.limit() < 100
end

--- Writes the limit the moment calls for, if it differs from the kernel's. A
--- limit nobody set here is left as it stands.
function M.apply()
  if route:get() ~= "file" or (chosen() <= 0 and not M.adaptive()) then return end
  local u = upower()
  local status = require("battery_status_model").read(u)
  local feed = charger.read(dir())
  local want = M.target { limit = M.limit(), adaptive = M.adaptive(), plugged = status.plugged, now = minutes_now(),
    ready = M.ready(), size = feed.capacity, watts = feed.watts }
  if want == written or (written == nil and want == feed.limit) then return end
  written = want
  if dry() and not stand_in() then
    morf.log("info", ("eva: charge limit %d (dry run)"):format(want))
    return
  end
  local ok, why = charger.set_limit(want, dir())
  M.message:set(ok and "" or tostring(why))
  if not ok then written = nil end
  if u and u.moved then u.moved() end
end

--- Sets the limit, to the nearest step.
function M.set_limit(value)
  value = math.floor((tonumber(value) or 100) / M.STEP + 0.5) * M.STEP
  config.set("battery.limit", math.max(M.LOWEST, math.min(100, value)))
end

--- Turns the limit on at HOLD, or off; through UPower where that is the way.
function M.set_on(on)
  if route:get() ~= "upower" then return M.set_limit(on and M.HOLD or 100) end
  if dry() then morf.log("info", "eva: charge limit " .. tostring(on) .. " (dry run)") return end
  charger.upower(battery_path()).enable(on, function(ok, why)
    M.message:set(ok and "" or tostring(why))
    if ok then threshold:set(charger.upower(battery_path()).get()) end
  end)
end

function M.set_adaptive(on) config.set("battery.adaptive", on == true) end

--- Moves the ready time by `minutes`, round the clock.
function M.step_ready(minutes) config.set("battery.ready", (M.ready() + minutes) % 1440) end

--- What the page says about what this session may do.
function M.note()
  local kind = route:get()
  if kind == "upower" then
    local t = threshold:get()
    return ("UPower holds it between %s%% and %s%%; a level of your own needs write access to the kernel's threshold.")
      :format(tostring(t.start or "?"), tostring(t.stop or "?"))
  end
  if kind == "locked" then
    return "The kernel has a charge limit, but this session may not write it. programs.eva.hardware.chargeLimit grants that."
  end
  return ""
end

--- Finds out what this machine allows.
function M.probe()
  if stand_in() then
    route:set(charger.limit_file(dir()) and "file" or "")
    return
  end
  charger.writable(function(ok)
    if ok then return route:set("file") end
    local state = charger.upower(battery_path()).get()
    if state.supported then
      threshold:set(state)
      route:set("upower")
    else
      route:set(charger.limit_file(dir()) and "locked" or "")
    end
  end, dir())
end

--- Starts keeping the kernel's limit to the settings, on the primary screen.
function M.start()
  if morf.window.primary and not morf.window.primary() then return end
  M.probe()
  morf.effect("eva.charge.apply", function()
    local kind, adaptive = route:get(), M.adaptive()
    M.limit() M.ready()
    M.apply()
    local want = adaptive and kind == "file"
    if want and not ticker then
      ticker = morf.time.timer(M.TICK, M.apply, true)
    elseif not want and ticker then
      ticker:cancel()
      ticker = nil
    end
  end)
end

return M
