-- Dark or light, one answer for the shell, the lock and the greeter: the
-- choice saved with the theme, and what that choice means now. "auto" is what
-- the colour tool made, "schedule" two times of day, "sun" the sunrise and
-- sunset here (the shell keeps them in the same file), and "system" the
-- desktop's own setting. A snooze holds a mode for a while, then the choice
-- resumes. EVA_THEME_MODE overrides it for a preview.
local morf = require("morf")
local themes = require("themes")
local M = { CHOICES = { "auto", "dark", "light", "schedule", "sun", "system" } }

local function explicit(value) return value == "dark" or value == "light" end
local CHOSEN = {}
for _, choice in ipairs(M.CHOICES) do CHOSEN[choice] = true end
local preferences = themes.preferences

--- "HH:MM" as minutes into the day, or nil.
function M.minutes(text)
  local hour, minute = tostring(text or ""):match("^(%d%d?):(%d%d)$")
  hour, minute = tonumber(hour), tonumber(minute)
  if not hour or hour > 23 or minute > 59 then return nil end
  return hour * 60 + minute
end

--- "light" between `from` and `to` (minutes into the day), "dark" outside,
--- across midnight too.
function M.by_clock(now, from, to)
  if from < to then return (now >= from and now < to) and "light" or "dark" end
  return (now >= from or now < to) and "light" or "dark"
end

-- The minute of the day, tracked. EVA_FAKE_CLOCK ("HH:MM") stands in for it.
local function now_minutes()
  local fake = M.minutes(morf.env("EVA_FAKE_CLOCK"))
  if fake then return fake end
  morf.time.minute_clock:get()
  return (tonumber(morf.time.format("%H")) or 0) * 60 + (tonumber(morf.time.format("%M")) or 0)
end

--- The mode a snooze holds, or nil.
function M.snoozed()
  local mode, stop = preferences.get("snooze_mode"), preferences.get("snooze_until")
  if not explicit(mode) or stop <= 0 then return nil end
  morf.time.minute_clock:get()
  return morf.time.now() < stop and mode or nil
end

--- "auto", "dark", "light", "schedule", "sun" or "system"; tracked in a binding.
function M.chosen()
  local forced = morf.env("EVA_THEME_MODE")
  if explicit(forced) then return forced end
  local saved = preferences.get("mode")
  return CHOSEN[saved] and saved or "auto"
end

local function timed(from, to, tool_mode)
  local start, stop = M.minutes(preferences.get(from)), M.minutes(preferences.get(to))
  if not start or not stop then return tool_mode == "light" and "light" or "dark" end
  return M.by_clock(now_minutes(), start, stop)
end

--- "dark" or "light", given what the colour tool made (nil without one).
function M.resolve(tool_mode)
  local chosen = M.chosen()
  if explicit(chosen) then return chosen end
  local held = M.snoozed()
  if held then return held end
  if chosen == "schedule" then return timed("light_from", "dark_from", tool_mode) end
  if chosen == "sun" then return timed("sunrise", "sunset", tool_mode) end
  if chosen == "system" then
    local scheme = morf.prefers and morf.prefers.color_scheme
    if explicit(scheme) then return scheme end
  end
  return tool_mode == "light" and "light" or "dark"
end

function M.set(mode)
  preferences.set("mode", mode)
  preferences.set("snooze_mode", "")
  preferences.set("snooze_until", 0)
  preferences.flush()
end

--- Holds `mode` for `seconds`; the choice resumes after.
function M.snooze(mode, seconds)
  preferences.set("snooze_mode", mode)
  preferences.set("snooze_until", morf.time.now() + seconds)
  preferences.flush()
end

--- The two times a schedule turns at.
function M.set_schedule(light_from, dark_from)
  if not M.minutes(light_from) or not M.minutes(dark_from) then return false end
  preferences.set("light_from", light_from)
  preferences.set("dark_from", dark_from)
  preferences.flush()
  return true
end

return M
