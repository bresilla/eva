-- How the bar writes the time, from `bar.clock.*`. No nodes.
local morf = require("morf")
local M = {}

M.DATES = {
  { "none", "event_busy", "None", "" },
  { "day", "calendar_view_day", "Day", "%a %-d" },
  { "short", "today", "Short", "%a %-d %b" },
  { "long", "calendar_month", "Long", "%A, %-d %B" },
  { "iso", "numbers", "ISO", "%Y-%m-%d" },
}

local function date_pattern(name)
  for _, row in ipairs(M.DATES) do if row[1] == name then return row[4] end end
  return "%a %-d %b"
end

--- The pattern of the time from `options`: `twelve_hour` and `seconds`.
function M.pattern(options)
  local minutes = options.seconds and ":%M:%S" or ":%M"
  if options.twelve_hour then return "%-I" .. minutes .. " %p" end
  return "%H" .. minutes
end

--- The time `at` in pieces: `time`, `date`, `day`, `hour`, `minute`, `second`
--- and `meridiem`. `options`, as `bar.clock` has them, with `format` taking
--- the place of the time and the date both.
function M.stamp(options, at)
  local fmt = morf.time.format
  local custom = options.format ~= nil and options.format ~= ""
  local twelve = options.twelve_hour == true
  return {
    time = fmt(custom and options.format or M.pattern(options), at),
    date = custom and "" or (function()
      local pattern = date_pattern(options.date)
      return pattern ~= "" and fmt(pattern, at) or ""
    end)(),
    day = fmt("%d", at),
    hour = fmt(twelve and "%-I" or "%H", at), minute = fmt("%M", at), second = fmt("%S", at),
    meridiem = twelve and fmt("%p", at) or "",
  }
end

--- The settings as `stamp` takes them. A tracked read.
function M.options()
  local config = require("config")
  return { twelve_hour = config.get("bar.clock.twelve_hour") == true, seconds = config.get("bar.clock.seconds") == true,
    date = config.get("bar.clock.date"), format = config.get("bar.clock.format") }
end

local WORDS = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve" }

--- The time as a person says it, to the nearest five minutes: `hour` 0..23.
function M.fuzzy(hour, minute)
  local step = math.floor(minute / 5 + 0.5) * 5
  local next_hour = WORDS[(hour % 12) % 12 + 1]
  local this_hour = WORDS[((hour - 1) % 12) + 1]
  if step == 0 then return this_hour .. " o'clock" end
  if step == 60 then return next_hour .. " o'clock" end
  if step == 15 then return "quarter past " .. this_hour end
  if step == 30 then return "half past " .. this_hour end
  if step == 45 then return "quarter to " .. next_hour end
  if step < 30 then return step .. " past " .. this_hour end
  return (60 - step) .. " to " .. next_hour
end

--- Whole days from now to `date` (`YYYY-MM-DD`), or nil for no such date.
function M.days_to(date, now)
  local y, m, d = tostring(date or ""):match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if not y then return nil end
  local at = morf.time.time { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
  return math.floor((at - (now or morf.time.now())) / 86400 + 0.5)
end

return M
