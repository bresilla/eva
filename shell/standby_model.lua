-- StandBy: a phone on charge, turned sideways, becomes a bedside screen.
-- State only: when it shows, which view, and whether it is night.
local morf = require("morf")
local config = require("config")
local M = {}

M.VIEWS = { { "clock", "Clock", "schedule" }, { "photos", "Photos", "photo_library" }, { "widgets", "Widgets", "widgets" },
  { "world", "World", "public" }, { "alarm", "Alarm", "alarm" } }
M.view = morf.signal("eva.standby.view", "clock")
-- Sent away until it is unplugged or turned; asked for by hand.
M.dismissed = morf.signal("eva.standby.dismissed", false)
M.forced = morf.signal("eva.standby.forced", false)
-- Asked for by hand: until the power goes, and at night whatever the hour.
M.while_charging = morf.signal("eva.standby.while_charging", false)
M.night_asked = morf.signal("eva.standby.night_asked", false)

--- Whether it is on charge.
function M.charging()
  local status = require("battery_status_model").read()
  return status.present == true and (status.charging or status.plugged or status.full) == true
end

--- Whether the screen lies on its side.
function M.sideways()
  morf.window.screens_revision()
  return not require("responsive").portrait()
end

--- Whether this machine has it at all: a phone has, a desk does not.
function M.able()
  return config.get("desktop.standby") == true and require("responsive").form() ~= "desk"
end

--- Whether conditions call for it.
function M.called() return M.able() and M.charging() and M.sideways() end

--- Whether it shows.
function M.showing() return M.forced:get() or (M.called() and not M.dismissed:get()) end

--- Sends it away until the conditions lapse and return.
function M.dismiss()
  M.forced:set(false)
  M.dismissed:set(true)
  M.while_charging:set(false)
  M.night_asked:set(false)
end

--- The view `delta` steps along.
function M.step(delta)
  local at = 1
  for i, view in ipairs(M.VIEWS) do if view[1] == M.view:get() then at = i end end
  M.view:set(M.VIEWS[(at - 1 + delta) % #M.VIEWS + 1][1])
end

--- Whether it is the dark part of the day, for a dim red face.
function M.night()
  if M.night_asked:get() then return true end
  local mode = require("themes.color_mode")
  local kept = require("themes").preferences
  local now = mode.minutes(morf.env("EVA_FAKE_CLOCK"))
  if not now then
    morf.time.minute_clock:get()
    now = (tonumber(morf.time.format("%H")) or 0) * 60 + (tonumber(morf.time.format("%M")) or 0)
  end
  local from, to = mode.minutes(kept.get("light_from")), mode.minutes(kept.get("dark_from"))
  if not from or not to then return false end
  return mode.by_clock(now, from, to) == "dark"
end

--- The minutes and hours as a clock draws them.
function M.clock_text(time)
  local twelve = config.get("bar.clock.twelve_hour")
  return morf.time.format(twelve and "%I:%M" or "%H:%M", time)
end

--- eva-clock's cities, `{ name, zone }`.
function M.cities()
  morf.time.minute_clock:get()
  local root = morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")
  local ok, list = pcall(function() return morf.json.decode(morf.fs.read(root .. "/eva/clock/world.json")) end)
  return ok and type(list) == "table" and list or {}
end

--- A city's time and how far it is from here, in words.
function M.city_time(entry) return require("lib.services.alarm").city_time(entry) end

--- The next thing to ring, in words: `{ time, label, left }`, or nil.
function M.next_alarm()
  morf.time.minute_clock:get()
  local item = require("services").alarm.next()
  if not item then return nil end
  local label = item.label ~= "" and item.label or (item.kind == "timer" and "Timer" or "Alarm")
  local lib = require("lib.services.alarm")
  return { time = morf.time.format("%H:%M", item.at), label = label,
    left = "in " .. lib.span(math.max(60, item.at - lib.now())) }
end

-- The next conditions start fresh once these lapse.
morf.effect("eva.standby.reset", function()
  if not M.called() then M.dismissed:set(false) end
end)

-- Asked to last while it charges, it goes with the power.
morf.effect("eva.standby.unplugged", function()
  if M.while_charging:get() and not M.charging() then M.dismiss() end
end)

-- The screen stays awake while it shows, unless something else holds it already.
local holding = false
morf.effect("eva.standby.hold", function()
  local showing = M.showing()
  if showing == holding then return end
  local settings = require("settings_model")
  if showing and settings.awake:get() then return end
  holding = showing
  settings.set_awake(showing)
end)

--- `standby [on [when-charging] [night]|off|toggle|state|VIEW]`.
function M.verb(how, ...)
  how = how or "state"
  if how == "toggle" then how = M.showing() and "off" or "on" end
  if how == "on" then
    M.forced:set(true) M.dismissed:set(false)
    for _, word in ipairs { ... } do
      if word == "when-charging" then M.while_charging:set(true)
      elseif word == "night" then M.night_asked:set(true)
      else error("`" .. tostring(word) .. "`: when-charging or night") end
    end
  elseif how == "off" then M.dismiss()
  elseif how ~= "state" then
    local known = false
    for _, view in ipairs(M.VIEWS) do known = known or view[1] == how end
    if not known then error("`" .. tostring(how) .. "`: on, off, toggle, state, or a view") end
    M.view:set(how)
  end
  return { showing = M.showing(), view = M.view:get(), called = M.called(), night = M.night() }
end

return M
