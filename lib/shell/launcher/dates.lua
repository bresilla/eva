-- Dates and clocks as people write them: "next friday", "in 3 weeks", "10am utc
-- in tokyo", "days until 2027-01-01", "1700000000". Times are read with
-- morf.time, which knows every zone; `now` is an argument.

local morf = require("morf")

local M = {}

local WEEKDAYS = { sunday = 0, monday = 1, tuesday = 2, wednesday = 3, thursday = 4, friday = 5, saturday = 6,
  sun = 0, mon = 1, tue = 2, wed = 3, thu = 4, fri = 5, sat = 6 }
local MONTHS = { january = 1, february = 2, march = 3, april = 4, may = 5, june = 6, july = 7, august = 8,
  september = 9, october = 10, november = 11, december = 12, jan = 1, feb = 2, mar = 3, apr = 4, jun = 6, jul = 7,
  aug = 8, sep = 9, sept = 9, oct = 10, nov = 11, dec = 12 }
local UNITS = { s = "seconds", sec = "seconds", secs = "seconds", second = "seconds", seconds = "seconds",
  m = "minutes", min = "minutes", mins = "minutes", minute = "minutes", minutes = "minutes",
  h = "hours", hr = "hours", hrs = "hours", hour = "hours", hours = "hours",
  d = "days", day = "days", days = "days", w = "weeks", week = "weeks", weeks = "weeks",
  month = "months", months = "months", y = "years", year = "years", years = "years" }
local SECONDS = { seconds = 1, minutes = 60, hours = 3600, days = 86400, weeks = 604800 }

-- Zones people say by name; every other city comes from the zone database.
local ALIASES = {
  utc = "UTC", gmt = "UTC", z = "UTC", bst = "Europe/London", cet = "Europe/Paris", cest = "Europe/Paris",
  eet = "Europe/Athens", est = "America/New_York", edt = "America/New_York", cst = "America/Chicago",
  cdt = "America/Chicago", mst = "America/Denver", mdt = "America/Denver", pst = "America/Los_Angeles",
  pdt = "America/Los_Angeles", jst = "Asia/Tokyo", kst = "Asia/Seoul", ist = "Asia/Kolkata", aest = "Australia/Sydney",
  nyc = "America/New_York", la = "America/Los_Angeles", sf = "America/Los_Angeles", delhi = "Asia/Kolkata",
  mumbai = "Asia/Kolkata", beijing = "Asia/Shanghai", washington = "America/New_York", ["san francisco"] = "America/Los_Angeles",
  ["são paulo"] = "America/Sao_Paulo", zurich = "Europe/Zurich", munich = "Europe/Berlin",
}
local REGIONS = { "Africa", "America", "Antarctica", "Asia", "Atlantic", "Australia", "Europe", "Indian", "Pacific" }

local cities

local function zone_folder()
  local tzdir = morf.env and morf.env("TZDIR")
  for _, folder in ipairs { tzdir or "", "/usr/share/zoneinfo", "/etc/zoneinfo", "/run/current-system/sw/share/zoneinfo" } do
    if folder ~= "" and morf.fs.is_dir(folder) then return folder end
  end
end

local function read_cities()
  if cities then return cities end
  cities = {}
  local folder = zone_folder()
  if not folder then return cities end
  for _, region in ipairs(REGIONS) do
    local ok, entries = pcall(morf.fs.list, folder .. "/" .. region)
    if ok and type(entries) == "table" then
      for _, entry in ipairs(entries) do
        if entry.name and not entry.is_dir then
          cities[entry.name:lower():gsub("_", " ")] = region .. "/" .. entry.name
        end
      end
    end
  end
  return cities
end

--- The zone `name` means: an abbreviation, a city, or a zone's own name; nil
--- when it is none of them.
function M.zone(name)
  local key = tostring(name or ""):lower():gsub("_", " "):match("^%s*(.-)%s*$")
  if key == "" then return nil end
  if key == "local" or key == "here" then return "local" end
  if ALIASES[key] then return ALIASES[key] end
  if read_cities()[key] then return read_cities()[key] end
  if name:find("/", 1, true) and pcall(morf.time.date, 0, { tz = name }) then return name end
  return nil
end

--- `seconds` in the fewest words: "1h 20m", "45s".
function M.span(seconds)
  seconds = math.floor(math.abs(seconds))
  local d, h, m, s = seconds // 86400, seconds % 86400 // 3600, seconds % 3600 // 60, seconds % 60
  local out = {}
  if d > 0 then out[#out + 1] = d .. "d" end
  if h > 0 then out[#out + 1] = h .. "h" end
  if m > 0 then out[#out + 1] = m .. "m" end
  if s > 0 or #out == 0 then out[#out + 1] = s .. "s" end
  return table.concat(out, " ")
end

--- Seconds in a duration: "5m", "1h 30m", "90 seconds", "2 hours 5 minutes",
--- "1:30" (minutes and seconds), a bare number being minutes. The second
--- value is what follows it, as words.
function M.duration(text)
  text = tostring(text or ""):match("^%s*(.-)%s*$")
  local minutes, seconds, after = text:match("^(%d+):(%d%d)%f[%D]%s*(.*)$")
  if minutes then return tonumber(minutes) * 60 + tonumber(seconds), after end
  local total, rest, found = 0, text, false
  while true do
    local number, unit, tail = rest:match("^(%d+%.?%d*)%s*(%a+)%s*(.*)$")
    local name = unit and UNITS[unit:lower()]
    local size = name and SECONDS[name]
    if not size then break end
    total, rest, found = total + tonumber(number) * size, tail, true
  end
  if found then return math.floor(total), rest end
  local bare, tail = text:match("^(%d+%.?%d*)%s*(.*)$")
  if bare then return math.floor(tonumber(bare) * 60), tail end
  return nil
end

--- The time `hour:minute` given as "10", "10:30", "10am" or "2:15pm", and
--- what follows it; nil when the text does not start with a clock.
function M.clock(text)
  local h, m, meridian, rest = text:lower():match("^%s*(%d%d?):(%d%d)%s*([ap]m)%f[%A]%s*(.*)$")
  if not h then h, meridian, rest = text:lower():match("^%s*(%d%d?)%s*([ap]m)%f[%A]%s*(.*)$") m = "0" end
  if not h then h, m, rest = text:lower():match("^%s*(%d%d?):(%d%d)%f[%D]%s*(.*)$") end
  if not h then return nil end
  local hour = tonumber(h)
  if meridian == "pm" and hour < 12 then hour = hour + 12 end
  if meridian == "am" and hour == 12 then hour = 0 end
  if hour > 23 or tonumber(m) > 59 then return nil end
  return hour, tonumber(m), rest
end

local function at_midnight(t) return morf.time.start_of(t, "day") end

local function weekday_after(now, weekday, strictly)
  local today = morf.time.date(now).weekday % 7
  local ahead = (weekday - today) % 7
  if ahead == 0 and strictly then ahead = 7 end
  return morf.time.add(at_midnight(now), { days = ahead })
end

local function dated(year, month, day)
  local ok, t = pcall(morf.time.time, { year = year, month = month, day = day })
  if ok then return t end
end

--- The instant `text` names, or nil. `now` is the time it is said at.
function M.parse(text, now)
  now = now or morf.time.now()
  local s = tostring(text or ""):lower():match("^%s*(.-)%s*$")
  if s == "" or s == "now" then return now end
  if s == "today" then return at_midnight(now) end
  if s == "tomorrow" then return morf.time.add(at_midnight(now), { days = 1 }) end
  if s == "yesterday" then return morf.time.add(at_midnight(now), { days = -1 }) end
  if s:match("^%d%d%d%d%d%d%d%d%d%d$") then return tonumber(s) end
  if s:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d$") then return tonumber(s) // 1000 end
  local bare = s:match("^(%a+)$")
  if bare and WEEKDAYS[bare] then return weekday_after(now, WEEKDAYS[bare], true) end
  local next_day = s:match("^next%s+(%a+)$") or s:match("^this%s+(%a+)$")
  if next_day and WEEKDAYS[next_day] then return weekday_after(now, WEEKDAYS[next_day], true) end
  local base, span = s:match("^(%a+)%s+in%s+(.+)$")
  if base and WEEKDAYS[base] then
    local n, unit = span:match("^(%d+)%s*(%a+)$")
    local name = unit and UNITS[unit]
    if name then return morf.time.add(weekday_after(now, WEEKDAYS[base], true), { [name] = tonumber(n) }) end
  end
  local n, unit = s:match("^in%s+(%d+)%s*(%a+)$")
  if n and UNITS[unit] then return morf.time.add(now, { [UNITS[unit]] = tonumber(n) }) end
  n, unit = s:match("^(%d+)%s*(%a+)%s+ago$")
  if n and UNITS[unit] then return morf.time.add(now, { [UNITS[unit]] = -tonumber(n) }) end
  local year, month, day = s:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
  if year then return dated(tonumber(year), tonumber(month), tonumber(day)) end
  local this_year = morf.time.date(now).year
  local d, name, y = s:match("^(%d%d?)%s+(%a+)%s*(%d*)$")
  if not d then name, d, y = s:match("^(%a+)%s+(%d%d?),?%s*(%d*)$") end
  if d and MONTHS[name] then
    local chosen = dated(y ~= "" and tonumber(y) or this_year, MONTHS[name], tonumber(d))
    if chosen and y == "" and chosen < at_midnight(now) then
      chosen = dated(this_year + 1, MONTHS[name], tonumber(d))
    end
    return chosen
  end
  local parsed = morf.time.parse(tostring(text):match("^%s*(.-)%s*$"))
  return parsed
end

--- "in 3 days" or "2 hours ago" for `t`, from `now`.
function M.relative(t, now)
  now = now or morf.time.now()
  local gap = t - now
  local size = math.abs(gap)
  local words
  if size < 60 then return "now" end
  if size < 3600 then words = (size // 60) .. " min"
  elseif size < 86400 then words = (size // 3600) .. " h"
  elseif size < 86400 * 60 then words = (size // 86400) .. " days"
  elseif size < 86400 * 730 then words = (size // (86400 * 30)) .. " months"
  else words = (size // (86400 * 365)) .. " years" end
  return gap > 0 and ("in " .. words) or (words .. " ago")
end

--- The whole days from `now` until `t`, counting midnights.
function M.days_between(now, t)
  return math.floor((at_midnight(t) - at_midnight(now)) / 86400 + 0.5)
end

--- The time in `zone` (morf.time's name, or "local") at `t`, spelled for a row.
function M.in_zone(t, zone)
  local options = zone ~= "local" and { tz = zone } or nil
  return morf.time.format("%H:%M", t, options), morf.time.format("%a %-d %b %Y", t, options),
    morf.time.format("%Z (UTC%:z)", t, options)
end

--- The instant of clock `hour:minute` today, as `zone` counts it.
function M.clock_in_zone(hour, minute, zone, now)
  local options = zone ~= "local" and { tz = zone } or nil
  local day = morf.time.date(now or morf.time.now(), options)
  return morf.time.time({ year = day.year, month = day.month, day = day.day, hour = hour, minute = minute }, options)
end

return M
