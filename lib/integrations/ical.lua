-- iCalendar (RFC 5545) as far as a calendar page needs it: events, their
-- times in any zone, repeats, reminders and meeting links, read and written
-- back. No I/O.
--
--   local calendar = ical.parse(text)
--     --> { name, color, events = { { uid, summary, location, description, url,
--     --     start, finish, all_day, rule, rule_text, except, recurrence, alarms,
--     --     no_alarm, color, status } } }
--   ical.occurrences(calendar.events, from, to)
--     --> { { event, at, ends, all_day } }, sorted, seconds since the epoch
--   ical.edit_event(text, uid, recurrence, change, now)
--     --> the file with that event changed, every other line as it was
--
-- A `change` names what to set: `summary`, `location`, `description`, `start`,
-- `finish` (parsed times; false drops the end), `rule` (RRULE text, "" drops
-- it) and `alarms` (seconds before; false turns the default reminder off).
local morf = require("morf")
local M = { MAX_STEPS = 4000 }

local SECONDS = { W = 604800, D = 86400, H = 3600, M = 60, S = 1 }

-- ------------------------------------------------------------- civil dates --

-- Days since the epoch of a proleptic Gregorian date.
local function days_from_civil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = y // 400
  local yoe = y - era * 400
  local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

local function civil_from_days(z)
  z = z + 719468
  local era = z // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp + (mp < 10 and 3 or -9)
  return yoe + era * 400 + (m <= 2 and 1 or 0), m, d
end

-- 1 for Monday through 7 for Sunday.
local function weekday(days) return (days + 3) % 7 + 1 end

local function month_length(y, m)
  return days_from_civil(m == 12 and y + 1 or y, m == 12 and 1 or m + 1, 1) - days_from_civil(y, m, 1)
end

M.days_from_civil, M.civil_from_days = days_from_civil, civil_from_days

-- ------------------------------------------------------------ content lines --

--- Long lines joined back together.
function M.unfold(text) return (tostring(text):gsub("\r\n", "\n"):gsub("\n[ \t]", "")) end

--- Text values with their escapes taken out.
function M.unescape(value)
  return (value:gsub("\\(.)", function(c)
    if c == "n" or c == "N" then return "\n" end
    return c
  end))
end

-- A line as its name, its parameters and its value: a colon in quotes is not
-- the one that ends the parameters.
local function content_line(line)
  local name, rest = line:match("^([%w%-]+)(.*)$")
  if not name then return nil end
  local params, at, quoted = {}, 1, false
  local stop
  for i = 1, #rest do
    local c = rest:sub(i, i)
    if c == '"' then quoted = not quoted
    elseif c == ":" and not quoted then stop = i break end
  end
  if not stop then return nil end
  for pair in rest:sub(1, stop - 1):gmatch(";([^;]+)") do
    local key, value = pair:match("^([^=]+)=(.*)$")
    if key then params[key:upper()] = value:gsub('^"(.*)"$', "%1") end
    at = at + 1
  end
  return name:upper(), params, rest:sub(stop + 1)
end

--- A DATE or DATE-TIME value: `{ year, month, day, hour, minute, second,
--- date, zone }`, with `zone` "utc", a TZID, or nil for floating time.
function M.parse_time(value, params)
  local y, m, d, H, N, S, z = value:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)(Z?)")
  if y then
    return { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(H), minute = tonumber(N),
      second = tonumber(S), zone = z == "Z" and "utc" or (params and params.TZID) or nil }
  end
  y, m, d = value:match("^(%d%d%d%d)(%d%d)(%d%d)")
  if y then
    return { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0, minute = 0, second = 0, date = true }
  end
end

--- A DURATION value in seconds; negative where it says so.
function M.parse_duration(value)
  local sign, body = tostring(value):match("^([%+%-]?)P(.+)$")
  if not body then return nil end
  local total = 0
  for amount, unit in body:gsub("T", ""):gmatch("(%d+)([WDHMS])") do total = total + tonumber(amount) * SECONDS[unit] end
  return sign == "-" and -total or total
end

--- An instant from a parsed time: in its zone, or local where it has none or
--- names one this machine does not know.
function M.epoch(time)
  local fields = { year = time.year, month = time.month, day = time.day, hour = time.hour, minute = time.minute, second = time.second }
  if time.zone == "utc" then return morf.time.time(fields, { utc = true }) end
  if time.zone then
    local ok, value = pcall(morf.time.time, fields, { tz = time.zone })
    if ok then return value end
  end
  return morf.time.time(fields)
end

local function parse_rule(value)
  local rule = { interval = 1 }
  for key, item in value:gmatch("([%w]+)=([^;]+)") do
    key = key:upper()
    if key == "FREQ" then rule.freq = item:upper()
    elseif key == "INTERVAL" then rule.interval = math.max(1, tonumber(item) or 1)
    elseif key == "COUNT" then rule.count = tonumber(item)
    elseif key == "UNTIL" then rule.until_time = M.parse_time(item)
    elseif key == "BYDAY" then
      rule.days = {}
      for ordinal, name in item:gmatch("([%+%-]?%d*)(%u%u)") do
        rule.days[#rule.days + 1] = { ordinal = tonumber(ordinal), day = ({ MO = 1, TU = 2, WE = 3, TH = 4, FR = 5, SA = 6, SU = 7 })[name] }
      end
    elseif key == "BYMONTHDAY" then
      rule.month_days = {}
      for number in item:gmatch("%-?%d+") do rule.month_days[#rule.month_days + 1] = tonumber(number) end
    elseif key == "BYMONTH" then
      rule.months = {}
      for number in item:gmatch("%d+") do rule.months[tonumber(number)] = true end
    end
  end
  return rule.freq and rule or nil
end

--- The events of a calendar. `spend(n)`, when given, is told the work done:
--- a poll.job's, so a long file does not hold the loop.
function M.parse(text, spend)
  local calendar = { events = {} }
  local event, alarm
  local depth = {}
  for line in (M.unfold(text) .. "\n"):gmatch("(.-)\n") do
    if spend then spend(8) end
    local name, params, value = content_line(line)
    if name == "BEGIN" then
      depth[#depth + 1] = value
      if value == "VEVENT" then event = { alarms = {}, except = {} }
      elseif value == "VALARM" and event then alarm = {} end
    elseif name == "END" then
      depth[#depth] = nil
      if value == "VEVENT" and event then
        if event.start then calendar.events[#calendar.events + 1] = event end
        event = nil
      elseif value == "VALARM" and event and alarm then
        if alarm.none then event.no_alarm = true
        elseif alarm.trigger and alarm.trigger <= 0 then event.alarms[#event.alarms + 1] = -alarm.trigger end
        alarm = nil
      end
    elseif alarm then
      if name == "ACTION" then alarm.none = value:upper() == "NONE"
      elseif name == "TRIGGER" and (params.RELATED or "START") == "START" then alarm.trigger = M.parse_duration(value) end
    elseif event then
      if name == "UID" then event.uid = value
      elseif name == "SUMMARY" then event.summary = M.unescape(value)
      elseif name == "LOCATION" then event.location = M.unescape(value)
      elseif name == "DESCRIPTION" then event.description = M.unescape(value)
      elseif name == "URL" then event.url = value
      elseif name == "STATUS" then event.status = value:upper()
      elseif name == "COLOR" then event.color = value
      elseif name == "CONFERENCE" or name == "X-GOOGLE-CONFERENCE" or name == "X-MICROSOFT-SKYPETEAMSMEETINGURL" then
        event.conference = value
      elseif name == "DTSTART" then
        event.start = M.parse_time(value, params)
        event.all_day = event.start ~= nil and event.start.date == true
      elseif name == "DTEND" then event.finish = M.parse_time(value, params)
      elseif name == "DURATION" then event.duration = M.parse_duration(value)
      elseif name == "RRULE" then event.rule, event.rule_text = parse_rule(value), value
      elseif name == "RECURRENCE-ID" then event.recurrence = M.parse_time(value, params)
      elseif name == "EXDATE" then
        for item in value:gmatch("[^,]+") do
          local time = M.parse_time(item, params)
          if time then event.except[M.epoch(time)] = true end
        end
      end
    elseif #depth == 1 then
      if name == "X-WR-CALNAME" or name == "NAME" then calendar.name = M.unescape(value)
      elseif name == "COLOR" or name == "X-APPLE-CALENDAR-COLOR" then calendar.color = value end
    end
  end
  return calendar
end

-- ---------------------------------------------------------------- repeating --

-- The days of a month a monthly or yearly rule falls on.
local function days_in_month(rule, event, y, m)
  local out = {}
  local length = month_length(y, m)
  if rule.month_days then
    for _, day in ipairs(rule.month_days) do
      local real = day > 0 and day or length + day + 1
      if real >= 1 and real <= length then out[#out + 1] = real end
    end
  elseif rule.days then
    local first = days_from_civil(y, m, 1)
    for _, by in ipairs(rule.days) do
      local matches = {}
      for day = 1, length do
        if weekday(first + day - 1) == by.day then matches[#matches + 1] = day end
      end
      if by.ordinal then
        local at = by.ordinal > 0 and by.ordinal or #matches + by.ordinal + 1
        if matches[at] then out[#out + 1] = matches[at] end
      else
        for _, day in ipairs(matches) do out[#out + 1] = day end
      end
    end
  elseif event.start.day <= length then
    out[1] = event.start.day
  end
  table.sort(out)
  return out
end

-- Calls `visit(days)` for each day a rule falls on, from the event's first, in
-- order, until `visit` answers true.
local function walk(event, visit)
  local rule, start = event.rule, event.start
  local first = days_from_civil(start.year, start.month, start.day)
  if rule.freq == "DAILY" then
    local day = first
    while true do
      local _, m = civil_from_days(day)
      if (not rule.months or rule.months[m]) and visit(day) then return end
      day = day + rule.interval
    end
  elseif rule.freq == "WEEKLY" then
    local monday = first - (weekday(first) - 1)
    while true do
      local offsets = {}
      for _, by in ipairs(rule.days or { { day = weekday(first) } }) do offsets[#offsets + 1] = by.day - 1 end
      table.sort(offsets)
      for _, offset in ipairs(offsets) do
        if monday + offset >= first and visit(monday + offset) then return end
      end
      monday = monday + 7 * rule.interval
    end
  elseif rule.freq == "MONTHLY" then
    local y, m = start.year, start.month
    while true do
      if not rule.months or rule.months[m] then
        for _, day in ipairs(days_in_month(rule, event, y, m)) do
          local at = days_from_civil(y, m, day)
          if at >= first and visit(at) then return end
        end
      end
      m = m + rule.interval
      while m > 12 do y, m = y + 1, m - 12 end
    end
  elseif rule.freq == "YEARLY" then
    local y = start.year
    while true do
      local months = {}
      for month in pairs(rule.months or { [start.month] = true }) do months[#months + 1] = month end
      table.sort(months)
      for _, m in ipairs(months) do
        for _, day in ipairs(days_in_month(rule, event, y, m)) do
          local at = days_from_civil(y, m, day)
          if at >= first and visit(at) then return end
        end
      end
      y = y + rule.interval
    end
  end
end

local function length_of(event)
  if event.finish then return M.epoch(event.finish) - M.epoch(event.start) end
  if event.duration then return event.duration end
  return event.all_day and 86400 or 0
end

-- This event's instances between `from` and `to`.
local function expand(event, from, to, out, overridden, spend)
  if event.status == "CANCELLED" then return end
  local length = length_of(event)
  local function add(at)
    if at + math.max(length, 1) > from and at < to and not event.except[at] and not overridden[(event.uid or "") .. ":" .. at] then
      out[#out + 1] = { event = event, at = at, ends = at + length, all_day = event.all_day == true }
    end
  end
  if not event.rule then add(M.epoch(event.start)) return end
  local limit = event.rule.until_time and M.epoch(event.rule.until_time) or math.huge
  local last_day = math.floor(to / 86400) + 2
  local before = math.floor(from / 86400) - 2 - math.ceil(length / 86400)
  local seen, steps = 0, 0
  local time = { hour = event.start.hour, minute = event.start.minute, second = event.start.second,
    zone = event.start.zone, date = event.start.date }
  walk(event, function(day)
    steps = steps + 1
    if spend then spend(2) end
    if day > last_day or steps > M.MAX_STEPS then return true end
    seen = seen + 1
    if event.rule.count and seen > event.rule.count then return true end
    if day >= before then
      time.year, time.month, time.day = civil_from_days(day)
      local at = M.epoch(time)
      if at > limit then return true end
      add(at)
    end
    return false
  end)
end

--- Every instance of `events` that touches `from`..`to`, soonest first. A
--- moved or changed instance stands in for the one its rule would give.
function M.occurrences(events, from, to, spend)
  local overridden = {}
  for _, event in ipairs(events) do
    if event.recurrence then overridden[(event.uid or "") .. ":" .. M.epoch(event.recurrence)] = true end
  end
  local out = {}
  for _, event in ipairs(events) do expand(event, from, to, out, overridden, spend) end
  table.sort(out, function(a, b)
    if a.at ~= b.at then return a.at < b.at end
    return (a.event.summary or "") < (b.event.summary or "")
  end)
  return out
end

-- ------------------------------------------------------------------ meetings --

local MEETINGS = { "meet%.google%.com/", "%.zoom%.us/", "//zoom%.us/", "teams%.microsoft%.com/", "teams%.live%.com/",
  "%.webex%.com/", "meet%.jit%.si/", "whereby%.com/", "%.gotomeeting%.com/", "%.chime%.aws/", "app%.slack%.com/huddle" }

local function meeting_in(text)
  for url in tostring(text or ""):gmatch("https?://[^%s<>\"'\\]+") do
    for _, pattern in ipairs(MEETINGS) do
      if url:find(pattern) then return (url:gsub("[%.,;:!%?%)]+$", "")) end
    end
  end
end

--- The address to join an event at, or nil.
function M.meeting_link(event)
  return meeting_in(event.conference) or meeting_in(event.url) or meeting_in(event.location) or meeting_in(event.description)
end

-- ------------------------------------------------------------------- writing --

--- A text value with its escapes put in.
function M.escape(text)
  return (tostring(text):gsub("\\", "\\\\"):gsub(";", "\\;"):gsub(",", "\\,"):gsub("\r?\n", "\\n"))
end

--- A line folded at 75 octets, never inside a character.
function M.fold(line)
  if #line <= 75 then return line end
  local out, at, limit = {}, 1, 75
  while at <= #line do
    local stop = math.min(#line, at + limit - 1)
    while stop < #line and (line:byte(stop + 1) & 0xC0) == 0x80 do stop = stop - 1 end
    out[#out + 1] = line:sub(at, stop)
    at, limit = stop + 1, 74
  end
  return table.concat(out, "\r\n ")
end

local function civil(time) return ("%04d%02d%02d"):format(time.year, time.month, time.day) end
local function stamp(time)
  return civil(time) .. ("T%02d%02d%02d"):format(time.hour or 0, time.minute or 0, time.second or 0)
end

--- A time property: a date, UTC, in its TZID, or floating.
function M.time_line(name, time)
  if time.date then return name .. ";VALUE=DATE:" .. civil(time) end
  if time.zone == "utc" then return name .. ":" .. stamp(time) .. "Z" end
  if time.zone then
    local zone = time.zone:find("[:;,]") and ('"' .. time.zone .. '"') or time.zone
    return ("%s;TZID=%s:%s"):format(name, zone, stamp(time))
  end
  return name .. ":" .. stamp(time)
end

--- The instant `at` as a parsed time, in the zone and value type of `like`.
function M.time_at(at, like)
  like = like or {}
  local options = like.zone == "utc" and { utc = true } or like.zone and { tz = like.zone } or nil
  local ok, date = pcall(morf.time.date, at, options)
  if not ok then date = morf.time.date(at) end
  return { year = date.year, month = date.month, day = date.day, hour = date.hour, minute = date.minute,
    second = date.second, zone = like.zone, date = like.date }
end

--- An RRULE value: `freq` as RFC 5545 names it, ending on `last` ("YYYY-MM-DD"
--- or nil), in the value type `start` has.
function M.rule_text(freq, last, start)
  local text = "FREQ=" .. freq
  local y, m, d = tostring(last or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y then return text end
  local day = { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 23, minute = 59, second = 59 }
  if start and start.date then return text .. ";UNTIL=" .. civil(day) end
  if start and start.zone then return text .. ";UNTIL=" .. stamp(M.time_at(M.epoch(day), { zone = "utc" })) .. "Z" end
  return text .. ";UNTIL=" .. stamp(day)
end

-- The lines of an event's reminders: `false` turns the default off (RFC 9074).
local function alarm_lines(alarms)
  if alarms == false then
    return { "BEGIN:VALARM", "ACTION:NONE", "TRIGGER;VALUE=DATE-TIME:19760401T005545Z", "END:VALARM" }
  end
  local out = {}
  for _, seconds in ipairs(alarms or {}) do
    local minutes = seconds // 60
    out[#out + 1] = "BEGIN:VALARM"
    out[#out + 1] = "ACTION:DISPLAY"
    out[#out + 1] = "DESCRIPTION:Reminder"
    out[#out + 1] = minutes == 0 and "TRIGGER:PT0S" or ("TRIGGER:-PT%dM"):format(minutes)
    out[#out + 1] = "END:VALARM"
  end
  return out
end

-- A file as its logical lines, each keeping its folds, endings taken off.
local function lines_of(text)
  local out = {}
  for line in (tostring(text):gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do
    if line:match("^[ \t]") and #out > 0 then out[#out] = out[#out] .. "\r\n" .. line
    elseif line ~= "" then out[#out + 1] = line end
  end
  return out
end

local function text_of(lines) return table.concat(lines, "\r\n") .. "\r\n" end

local function parsed(line)
  local name, params, value = content_line((line:gsub("\r\n[ \t]", "")))
  return name or "", params or {}, value or ""
end

-- Each VEVENT of `lines`: `{ first, last, uid, recurrence }`, `recurrence` the
-- instant a moved instance stands in for.
local function blocks(lines)
  local out, block, alarm = {}, nil, false
  for index, line in ipairs(lines) do
    local name, params, value = parsed(line)
    if name == "BEGIN" and value:upper() == "VEVENT" then block = { first = index }
    elseif name == "END" and value:upper() == "VEVENT" and block then
      block.last = index
      out[#out + 1] = block
      block = nil
    elseif block then
      if name == "BEGIN" and value:upper() == "VALARM" then alarm = true
      elseif name == "END" and value:upper() == "VALARM" then alarm = false
      elseif not alarm and name == "UID" then block.uid = value
      elseif not alarm and name == "RECURRENCE-ID" then
        local time = M.parse_time(value, params)
        block.recurrence = time and M.epoch(time) or nil
      end
    end
  end
  return out
end

local function matching(lines, uid, recurrence)
  for _, block in ipairs(blocks(lines)) do
    if block.uid == uid and block.recurrence == recurrence then return block end
  end
end

local RESTAMPED = { DTSTAMP = true, ["LAST-MODIFIED"] = true, SEQUENCE = true }

-- What `change` wants of a VEVENT: by property, its new line or false to drop it.
local function wanted_lines(change)
  local wanted = {}
  local function text(name, value)
    if value ~= nil then wanted[name] = value ~= "" and M.fold(name .. ":" .. M.escape(value)) end
  end
  text("SUMMARY", change.summary)
  text("LOCATION", change.location)
  text("DESCRIPTION", change.description)
  if change.description ~= nil then wanted["X-ALT-DESC"] = false end
  if change.start then wanted.DTSTART = M.time_line("DTSTART", change.start) end
  if change.finish ~= nil then
    wanted.DTEND = change.finish and M.time_line("DTEND", change.finish)
    wanted.DURATION = false
  end
  if change.rule ~= nil then wanted.RRULE = change.rule ~= "" and ("RRULE:" .. change.rule) end
  if change.recurrence then wanted["RECURRENCE-ID"] = change.recurrence end
  if change.single then wanted.RRULE, wanted.EXDATE = false, false end
  return wanted
end

-- A VEVENT's inner lines as `change` leaves them: what it names replaced where
-- it stands, every other line kept, reminders last as RFC 5545 orders them.
local function revised(body, change, now)
  local wanted, placed, out, alarms = wanted_lines(change), {}, {}, {}
  local in_alarm, sequence = false, 0
  for _, line in ipairs(body) do
    local name, _, value = parsed(line)
    if name == "BEGIN" and value:upper() == "VALARM" then in_alarm = true end
    if in_alarm then
      if change.alarms == nil then alarms[#alarms + 1] = line end
      if name == "END" and value:upper() == "VALARM" then in_alarm = false end
    elseif RESTAMPED[name] then
      if name == "SEQUENCE" then sequence = tonumber(value) or 0 end
    elseif wanted[name] ~= nil then
      if wanted[name] and not placed[name] then out[#out + 1] = wanted[name] end
      placed[name] = true
    else
      out[#out + 1] = line
    end
  end
  local tail = {}
  for name, line in pairs(wanted) do
    if line and not placed[name] then tail[#tail + 1] = line end
  end
  table.sort(tail)
  for _, line in ipairs(tail) do out[#out + 1] = line end
  local moment = stamp(M.time_at(now, { zone = "utc" })) .. "Z"
  out[#out + 1] = "DTSTAMP:" .. moment
  out[#out + 1] = "LAST-MODIFIED:" .. moment
  out[#out + 1] = "SEQUENCE:" .. (sequence + 1)
  if change.alarms ~= nil then alarms = alarm_lines(change.alarms) end
  for _, line in ipairs(alarms) do out[#out + 1] = line end
  return out
end

local function slice(lines, first, last)
  local out = {}
  for index = first, last do out[#out + 1] = lines[index] end
  return out
end

local function splice(lines, first, last, middle)
  local out = {}
  for index = 1, first - 1 do out[#out + 1] = lines[index] end
  for _, line in ipairs(middle) do out[#out + 1] = line end
  for index = last + 1, #lines do out[#out + 1] = lines[index] end
  return out
end

local function vevent(change, uid, now)
  local body = revised({ "UID:" .. uid }, change, now)
  table.insert(body, 1, "BEGIN:VEVENT")
  body[#body + 1] = "END:VEVENT"
  return body
end

-- A block's lines with its inner part rebuilt by `change`.
local function rebuilt(lines, block, change, now)
  local body = revised(slice(lines, block.first + 1, block.last - 1), change, now)
  table.insert(body, 1, lines[block.first])
  body[#body + 1] = lines[block.last]
  return body
end

--- A whole calendar file holding one new event; `name` is its calendar's.
function M.new_file(change, uid, now, name)
  local lines = { "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//eva//calendar//EN" }
  if name then lines[#lines + 1] = M.fold("X-WR-CALNAME:" .. M.escape(name)) end
  for _, line in ipairs(vevent(change, uid, now)) do lines[#lines + 1] = line end
  lines[#lines + 1] = "END:VCALENDAR"
  return text_of(lines)
end

--- `text` with a new event in it, or nil and why.
function M.add_event(text, change, uid, now)
  local lines = lines_of(text)
  for index = #lines, 1, -1 do
    local name, _, value = parsed(lines[index])
    if name == "END" and value:upper() == "VCALENDAR" then
      return text_of(splice(lines, index, index - 1, vevent(change, uid, now)))
    end
  end
  return nil, "This file is not a calendar."
end

--- `text` with one event changed, every property `change` does not name kept.
--- `recurrence` picks a moved instance, nil the event itself.
function M.edit_event(text, uid, recurrence, change, now)
  local lines = lines_of(text)
  local block = matching(lines, uid, recurrence)
  if not block then return nil, "This event is no longer in its calendar." end
  return text_of(splice(lines, block.first, block.last, rebuilt(lines, block, change, now)))
end

--- `text` with one instance of a repeating event changed on its own: a copy of
--- the event, `original` the instant it replaces and `like` the event's DTSTART.
function M.override_event(text, uid, original, like, change, now)
  local lines = lines_of(text)
  local master = matching(lines, uid, nil)
  if not master then return nil, "This event is no longer in its calendar." end
  local copy = { single = true, recurrence = M.time_line("RECURRENCE-ID", M.time_at(original, like)) }
  for key, value in pairs(change) do copy[key] = value end
  return text_of(splice(lines, master.last + 1, master.last, rebuilt(lines, master, copy, now)))
end

--- `text` with one instance of a repeating event taken out: an EXDATE on the
--- event, and the moved copy of that instance gone.
function M.except_event(text, uid, original, like, now)
  local lines = lines_of(text)
  local moved = matching(lines, uid, original)
  if moved then lines = splice(lines, moved.first, moved.last, {}) end
  local master = matching(lines, uid, nil)
  if not master then return nil, "This event is no longer in its calendar." end
  local body = rebuilt(lines, master, {}, now)
  table.insert(body, 2, M.time_line("EXDATE", M.time_at(original, like)))
  return text_of(splice(lines, master.first, master.last, body))
end

--- `text` without the event `uid` or its moved instances, and how many events
--- it still holds.
function M.remove_event(text, uid)
  local lines = lines_of(text)
  local all, found, kept = blocks(lines), false, 0
  for index = #all, 1, -1 do
    if all[index].uid == uid then
      found = true
      lines = splice(lines, all[index].first, all[index].last, {})
    else
      kept = kept + 1
    end
  end
  if not found then return nil, "This event is no longer in its calendar." end
  return text_of(lines), kept
end

return M
