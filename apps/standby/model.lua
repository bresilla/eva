-- eva-standby's state: which view shows, night mode, the screen held awake through
-- the shell's verb, and power for `--when-charging`. The clock, the alarms and the
-- cities are eva-clock's own. No nodes.
local morf = require("morf")
local sys = require("common.sys")
local lib = require("lib.services.alarm")
local clock = require("clock.model")
local status = require("battery_status_model")

local M = {
  view = morf.signal("standby.view", 1),
  night = morf.signal("standby.night", false),
  seconds = morf.signal("standby.seconds", 0),
  power = morf.signal("standby.power", ""),
  message = morf.signal("standby.message", ""),
  leaving = morf.signal("standby.leaving", false),
  held = morf.signal("standby.held", false),
  alarm = clock.alarm,
  world = clock.world,
  clock = clock,
}

M.VIEWS = { "clock", "world", "alarm" }
-- Minutes a hold of the screen lasts, and minutes between taking it again.
M.LEASE = 15
M.RENEW = 10

local function prefs() return sys.state("standby", "prefs.json") end

local function keep()
  sys.save(prefs(), { view = M.view:get(), night = M.night:get() })
end

--- The hands' angles for a time of day, in degrees from twelve: hour, minute,
--- second. They only grow through a day.
function M.angles(hour, minute, second)
  local total = hour * 3600 + minute * 60 + second
  return total / 120, total / 10, total * 6
end

local last, days = nil, 0

local function read_clock(words)
  local hour, minute, second = words:match("(%d+):(%d+):(%d+)")
  if not hour then return end
  local total = tonumber(hour) * 3600 + tonumber(minute) * 60 + tonumber(second)
  if last and total < last then days = days + 1 end
  last = total
  M.seconds:set(total + days * 86400)
end

--- Follows the wall clock: seconds that never run backwards, for the hands, the
--- first reading from the formatted time.
function M.follow_clock()
  read_clock(morf.time.format("%H:%M:%S"))
  morf.effect("standby.seconds", function() read_clock(morf.time.clock:get()) end)
end

function M.select(name)
  for index, key in ipairs(M.VIEWS) do
    if key == name then
      M.view:set(index)
      keep()
      return true
    end
  end
  return false
end

--- Goes `step` views along, round the ends.
function M.step(step)
  M.view:set((M.view:get() - 1 + step) % #M.VIEWS + 1)
  keep()
end

function M.set_night(on)
  M.night:set(on)
  keep()
end

--- The next thing to ring, in words: `{ time, label, left }`, or nil. A tracked
--- read, on the minute.
function M.next_alarm()
  morf.time.minute_clock:get()
  local item = M.alarm.next()
  if not item then return nil end
  local label = item.label ~= "" and item.label or (item.kind == "timer" and "Timer" or "Alarm")
  return { time = morf.time.format("%H:%M", item.at), label = label,
    left = "in " .. lib.span(math.max(60, item.at - lib.now())) }
end

--- A saved city's time, on the minute.
function M.city_time(entry)
  morf.time.minute_clock:get()
  return M.clock.city_time(entry)
end

local renewing

-- Marks the screen held, and asks the shell for it.
local function hold()
  M.held:set(true)
  sys.shell({ "awake", "on", tostring(M.LEASE) }, nil, function(reply, why)
    if reply == nil and why ~= "dry run" then M.message:set("No shell: the screen may sleep") end
  end)
end

--- Holds the screen awake, unless something else already does.
function M.hold_screen()
  sys.shell({ "awake", "state" }, { read = true }, function(state)
    if type(state) == "table" and state.on then return end
    hold()
    renewing = morf.time.timer(M.RENEW * 60000, hold, true)
  end)
end

--- Lets the screen go, and ends.
function M.quit()
  if M.leaving:get() then return true end
  M.leaving:set(true)
  if renewing then renewing:cancel() renewing = nil end
  if not M.held:get() then
    morf.quit()
    return true
  end
  sys.shell({ "awake", "off" }, nil, function() morf.quit() end)
  return true
end

-- UPower, or EVA_FAKE_BATTERY's stand-in: nil where there is neither.
local function upower()
  local fake = morf.env("EVA_FAKE_BATTERY")
  if fake and fake ~= "" and fake ~= "0" then return status.stand_in(fake) end
  local ok, service = pcall(function() return require("lib.services.upower").connect() end)
  return ok and service or nil
end

--- Shows the power, and with `leave` ends when it is unplugged. A machine with
--- no battery reads as on mains.
function M.watch_power(leave)
  M.upower = upower()
  morf.effect("standby.power", function()
    local now = status.read(M.upower or {})
    M.power:set(now.present and status.describe(now) or "")
    if leave and now.present and not now.plugged then M.quit() end
  end)
end

--- Reads what it shows and takes the screen. `words` are `eva-standby`'s.
function M.start(words)
  local held = sys.load(prefs(), {})
  if tonumber(held.view) and M.VIEWS[held.view] then M.view:set(held.view) end
  M.night:set(held.night == true)
  local leave = false
  for _, word in ipairs(words) do
    if word == "--when-charging" then leave = true
    elseif word == "--night" then M.night:set(true) end
  end
  M.alarm.load()
  M.world:set(sys.load(sys.state("clock", "world.json"), {}))
  M.watches = { morf.fs.watch(sys.state("clock", "world.json"), function()
    M.world:set(sys.load(sys.state("clock", "world.json"), {}))
  end) }
  M.follow_clock()
  M.watch_power(leave)
  M.hold_screen()
end

return M
