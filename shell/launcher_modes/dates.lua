-- Dates and clocks: a date in every notation, the time anywhere, a clock moved
-- between zones, and days until a day.
local morf = require("morf")
local registry = require("lib.shell.launcher.registry")
local rows = require("lib.shell.launcher.rows")
local dates = require("lib.shell.launcher.dates")

local M = {}

local copied = rows.copy

local function date_rows(t)
  local now = morf.time.now()
  local utc = { utc = true }
  local out = {
    copied("date:local", morf.time.format("%A %-d %B %Y, %H:%M", t), dates.relative(t, now) .. "  ·  here", "event"),
    copied("date:iso", morf.time.format("%Y-%m-%dT%H:%M:%SZ", t, utc), "ISO 8601, UTC", "schedule"),
    copied("date:rfc", morf.time.format("%a, %d %b %Y %H:%M:%S %z", t), "RFC 2822", "schedule"),
    copied("date:epoch", tostring(math.floor(t)), "Unix time, seconds", "timer"),
    copied("date:epochms", tostring(math.floor(t) * 1000), "Unix time, milliseconds", "timer"),
    copied("date:week", morf.time.format("Week %V, day %j", t), "Week of the year, day of the year", "calendar_view_week"),
  }
  return out
end

local function zone_row(id, t, zone, label)
  local clock, day, name = dates.in_zone(t, zone)
  return copied(id, clock .. "  ·  " .. day, (label or zone) .. "  ·  " .. name, "schedule", clock)
end

--- The zones in a phrase: "tokyo", "10am utc in tokyo", "15:30 to oslo". Returns
--- the instant and the zones it is read in, or nil.
local function moved(text)
  local now = morf.time.now()
  local hour, minute, rest = dates.clock(text)
  if not hour then return nil end
  rest = rest:gsub("^%s+", "")
  local from, to = rest:match("^(.-)%s+[it][no]%s+(.+)$")
  if not from then to = rest:match("^[it][no]%s+(.+)$") from = "" end
  if not to then from, to = rest, "" end
  local from_zone = from ~= "" and dates.zone(from) or "local"
  local to_zone = to ~= "" and dates.zone(to) or "local"
  if not from_zone or not to_zone then return nil end
  return dates.clock_in_zone(hour, minute, from_zone, now), from_zone, to_zone
end

--- A one-line answer for a phrase with a time in it, or nil: "time in tokyo",
--- "10am utc in tokyo", "days until 2027-01-01", "unix now".
function M.answer(q)
  local text = q:lower():match("^%s*(.-)%s*$")
  local place = text:match("^time%s+in%s+(.+)$") or text:match("^time%s+at%s+(.+)$") or text:match("^(.+)%s+time$")
  if place then
    local zone = dates.zone(place)
    if zone then return (dates.in_zone(morf.time.now(), zone)) .. "  " .. place end
  end
  local day = text:match("^days%s+until%s+(.+)$") or text:match("^days%s+to%s+(.+)$")
  if day then
    local t = dates.parse(day)
    if t then return dates.days_between(morf.time.now(), t) .. " days" end
  end
  day = text:match("^days%s+since%s+(.+)$")
  if day then
    local t = dates.parse(day)
    if t then return dates.days_between(t, morf.time.now()) .. " days" end
  end
  local t, _, to = moved(text)
  if t and to and to ~= "local" then return morf.time.format("%H:%M  %a  %Z", t, { tz = to }) end
  return nil
end

registry.mode { id = "date", name = "Date", material = "event", shape = "pill", words = { "date", "epoch", "unix" },
  hint = "date next friday  ·  date 1700000000  ·  date 2027-01-01",
  search = function(term)
    local t = dates.parse(term)
    if not t then return { rows.note("date", "That reads as no date", "next friday  ·  in 3 weeks  ·  1700000000  ·  25 dec", "event") } end
    return date_rows(t)
  end }

local COMMON = { "UTC", "America/Los_Angeles", "America/New_York", "Europe/London", "Europe/Berlin", "Asia/Kolkata",
  "Asia/Shanghai", "Asia/Tokyo", "Australia/Sydney" }

registry.mode { id = "time", name = "World clock", material = "schedule", shape = "pill", words = { "time", "tz", "zone" },
  hint = "time tokyo  ·  time 10am utc in oslo",
  search = function(term)
    local now = morf.time.now()
    if term == "" then
      local out = { zone_row("time:here", now, "local", "Here") }
      for i, zone in ipairs(COMMON) do out[#out + 1] = zone_row("time:" .. i, now, zone) end
      return out
    end
    local zone = dates.zone(term)
    if zone then return { zone_row("time:zone", now, zone, term), zone_row("time:here", now, "local", "Here") } end
    local t, from, to = moved(term)
    if t then
      local out = { zone_row("time:to", t, to, to == "local" and "Here" or to) }
      if from ~= to then out[#out + 1] = zone_row("time:from", t, from, from == "local" and "Here" or from) end
      return out
    end
    return { rows.note("time", "That reads as no place or time", "tokyo  ·  10am utc in oslo  ·  15:30 to nyc", "schedule") }
  end }

registry.mode { id = "week", name = "Week number", material = "calendar_view_week", shape = "pill", words = { "week" },
  hint = "this week's number", search = function(term)
    local t = dates.parse(term) or morf.time.now()
    return { copied("week", morf.time.format("Week %V", t), morf.time.format("%A %-d %B %Y", t), "calendar_view_week",
      morf.time.format("%V", t)) }
  end }

registry.mode { id = "stamp", name = "Duration", material = "timelapse", shape = "pill", words = { "duration", "workdays" },
  hint = "duration 55h  ·  in days, and eight-hour workdays", search = function(term)
    local seconds = dates.duration(term)
    if not seconds then return { rows.note("duration", "Type a span", "55h  ·  1h 20m  ·  90 seconds", "timelapse") } end
    return {
      copied("duration:span", dates.span(seconds), "As a span", "timelapse"),
      copied("duration:hours", ("%.2f hours"):format(seconds / 3600), "In hours", "timelapse"),
      copied("duration:work", ("%.1f workdays"):format(seconds / (8 * 3600)), "In eight-hour days", "work"),
      copied("duration:seconds", tostring(seconds), "In seconds", "timelapse"),
    }
  end }

return M
