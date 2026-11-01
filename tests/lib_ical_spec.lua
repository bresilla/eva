-- iCalendar: parsing, zones, repeats, overrides, meeting links.
--     morf test --no-dbus tests/lib_ical_spec.lua
local test = morf.test
local HOST = [[
  local ical = require("lib.integrations.ical")
  morf.ipc.parse = function(text)
    local calendar = ical.parse(text)
    local out = { name = calendar.name, color = calendar.color, events = {} }
    for i, event in ipairs(calendar.events) do
      out.events[i] = { summary = event.summary, location = event.location, description = event.description, all_day = event.all_day,
        uid = event.uid, status = event.status, alarms = event.alarms, color = event.color, link = ical.meeting_link(event) or "" }
    end
    return out
  end
  morf.ipc.times = function(text, from, to)
    local out = {}
    for i, item in ipairs(ical.occurrences(ical.parse(text).events, tonumber(from), tonumber(to))) do
      out[i] = { at = item.at, ends = item.ends, all_day = item.all_day, summary = item.event.summary }
    end
    return out
  end
  morf.ipc.utc = function(y, m, d, H, N) return morf.time.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(H), minute = tonumber(N or 0) }, { utc = true }) end
  morf.ipc.duration = function(text) return ical.parse_duration(text) end
  morf.ipc.civil = function(y, m, d) return { ical.civil_from_days(ical.days_from_civil(tonumber(y), tonumber(m), tonumber(d))) } end
]]
local function wrap(body) return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" .. body .. "\r\nEND:VCALENDAR\r\n" end
local function event(lines) return wrap("BEGIN:VEVENT\r\n" .. table.concat(lines, "\r\n") .. "\r\nEND:VEVENT") end
local function utc(...) return test.ipc("utc", ...) end
local function ats(rows)
  local out = {}
  for i, row in ipairs(rows) do out[i] = row.at end
  return out
end

test.describe("ical", function()
  test.before_each(function() test.load { source = HOST } end)

  test.it("reads a calendar's name and an event's fields", function()
    local out = test.ipc("parse", wrap("X-WR-CALNAME:Work\r\nCOLOR:teal\r\n" ..
      "BEGIN:VEVENT\r\nUID:1\r\nSUMMARY:Review\\, with notes\r\nLOCATION:Room 2\\;3\r\n" ..
      "DESCRIPTION:Line one\\nLine two\r\nDTSTART:20261102T100000Z\r\nCOLOR:red\r\nEND:VEVENT"))
    test.eq(out.name, "Work")
    test.eq(out.color, "teal")
    test.eq(out.events[1].summary, "Review, with notes")
    test.eq(out.events[1].location, "Room 2;3")
    test.eq(out.events[1].description, "Line one\nLine two")
    test.eq(out.events[1].color, "red")
  end)

  test.it("joins folded lines", function()
    local out = test.ipc("parse", event { "SUMMARY:A very long", " title indeed", "DTSTART:20261102T100000Z" })
    test.eq(out.events[1].summary, "A very longtitle indeed")
  end)

  test.it("skips a VEVENT that has no start, and reads a colon inside quotes", function()
    local out = test.ipc("parse", wrap("BEGIN:VEVENT\r\nSUMMARY:No time\r\nEND:VEVENT\r\n" ..
      'BEGIN:VEVENT\r\nSUMMARY:Timed\r\nORGANIZER;CN="A: B":mailto:a@b.test\r\nDTSTART:20261102T100000Z\r\nEND:VEVENT'))
    test.eq(#out.events, 1)
    test.eq(out.events[1].summary, "Timed")
  end)

  test.it("places a time in its own zone, across the clock change", function()
    -- Amsterdam: +2 in summer, +1 from 25 October 2026.
    local text = event { "DTSTART;TZID=Europe/Amsterdam:20260701T100000", "DTEND;TZID=Europe/Amsterdam:20260701T110000" }
    test.eq(test.ipc("times", text, utc(2026, 6, 30, 0), utc(2026, 7, 2, 0))[1].at, utc(2026, 7, 1, 8))
    text = event { "DTSTART;TZID=Europe/Amsterdam:20261102T100000" }
    test.eq(test.ipc("times", text, utc(2026, 11, 1, 0), utc(2026, 11, 3, 0))[1].at, utc(2026, 11, 2, 9))
  end)

  test.it("reads zones far from this machine's own", function()
    -- At most one of these is the zone the specs run in.
    for _, case in ipairs { { "Asia/Tokyo", 1 }, { "America/New_York", 15 }, { "Pacific/Auckland", -3 } } do
      local text = event { "DTSTART;TZID=" .. case[1] .. ":20261102T100000" }
      local day = case[2] < 0 and 1 or 2
      local hour = case[2] < 0 and 24 + case[2] or case[2]
      test.eq(test.ipc("times", text, utc(2026, 10, 30, 0), utc(2026, 11, 5, 0))[1].at, utc(2026, 11, day, hour), case[1])
    end
  end)

  test.it("treats a floating time as this machine's, and an unknown zone likewise", function()
    local floating = test.ipc("times", event { "DTSTART:20261102T100000" }, utc(2026, 10, 30, 0), utc(2026, 11, 5, 0))[1].at
    local unknown = test.ipc("times", event { "DTSTART;TZID=Not/AZone:20261102T100000" }, utc(2026, 10, 30, 0), utc(2026, 11, 5, 0))[1].at
    test.eq(unknown, floating)
  end)

  test.it("keeps a repeat at its wall-clock time past a clock change", function()
    local text = event { "DTSTART;TZID=Europe/Amsterdam:20261019T090000", "RRULE:FREQ=WEEKLY;COUNT=3" }
    test.eq(ats(test.ipc("times", text, utc(2026, 10, 1, 0), utc(2026, 12, 1, 0))),
      { utc(2026, 10, 19, 7), utc(2026, 10, 26, 8), utc(2026, 11, 2, 8) })
  end)

  test.it("reads an all-day event, its end exclusive", function()
    local text = event { "DTSTART;VALUE=DATE:20261102", "DTEND;VALUE=DATE:20261104" }
    local rows = test.ipc("times", text, utc(2026, 11, 1, 0), utc(2026, 11, 8, 0))
    test.eq(rows[1].all_day, true)
    test.eq(rows[1].ends - rows[1].at, 2 * 86400)
  end)

  test.it("takes a duration in place of an end", function()
    local text = event { "DTSTART:20261102T100000Z", "DURATION:PT1H30M" }
    local row = test.ipc("times", text, utc(2026, 11, 2, 0), utc(2026, 11, 3, 0))[1]
    test.eq(row.ends - row.at, 5400)
    test.eq(test.ipc("duration", "-P1DT2H"), -93600)
    test.eq(test.ipc("duration", "P2W"), 1209600)
  end)

  test.it("repeats daily, weekly, monthly and yearly", function()
    test.eq(#test.ipc("times", event { "DTSTART:20261101T090000Z", "RRULE:FREQ=DAILY;COUNT=4" },
      utc(2026, 10, 1, 0), utc(2027, 1, 1, 0)), 4)
    test.eq(ats(test.ipc("times", event { "DTSTART:20261102T090000Z", "RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=3" },
      utc(2026, 11, 1, 0), utc(2026, 12, 1, 0))), { utc(2026, 11, 2, 9), utc(2026, 11, 4, 9), utc(2026, 11, 9, 9) })
    test.eq(ats(test.ipc("times", event { "DTSTART:20261102T090000Z", "RRULE:FREQ=MONTHLY;INTERVAL=2;COUNT=2" },
      utc(2026, 11, 1, 0), utc(2027, 6, 1, 0))), { utc(2026, 11, 2, 9), utc(2027, 1, 2, 9) })
    test.eq(ats(test.ipc("times", event { "DTSTART:20261102T090000Z", "RRULE:FREQ=YEARLY;COUNT=2" },
      utc(2026, 1, 1, 0), utc(2029, 1, 1, 0))), { utc(2026, 11, 2, 9), utc(2027, 11, 2, 9) })
  end)

  test.it("skips a month too short for the day", function()
    test.eq(ats(test.ipc("times", event { "DTSTART:20270131T090000Z", "RRULE:FREQ=MONTHLY;COUNT=2" },
      utc(2027, 1, 1, 0), utc(2027, 5, 1, 0))), { utc(2027, 1, 31, 9), utc(2027, 3, 31, 9) })
  end)

  test.it("reads the nth weekday of a month, from either end", function()
    test.eq(ats(test.ipc("times", event { "DTSTART:20261110T090000Z", "RRULE:FREQ=MONTHLY;BYDAY=2TU;COUNT=2" },
      utc(2026, 11, 1, 0), utc(2027, 2, 1, 0))), { utc(2026, 11, 10, 9), utc(2026, 12, 8, 9) })
    test.eq(ats(test.ipc("times", event { "DTSTART:20261127T090000Z", "RRULE:FREQ=MONTHLY;BYDAY=-1FR;COUNT=2" },
      utc(2026, 11, 1, 0), utc(2027, 2, 1, 0))), { utc(2026, 11, 27, 9), utc(2026, 12, 25, 9) })
  end)

  test.it("stops at UNTIL, and counts COUNT from the first, not from the window", function()
    test.eq(#test.ipc("times", event { "DTSTART:20261101T090000Z", "RRULE:FREQ=DAILY;UNTIL=20261103T090000Z" },
      utc(2026, 10, 1, 0), utc(2027, 1, 1, 0)), 3)
    test.eq(#test.ipc("times", event { "DTSTART:20200101T090000Z", "RRULE:FREQ=DAILY;COUNT=5" },
      utc(2026, 1, 1, 0), utc(2027, 1, 1, 0)), 0)
    test.eq(#test.ipc("times", event { "DTSTART:20200101T090000Z", "RRULE:FREQ=WEEKLY" },
      utc(2026, 11, 1, 0), utc(2026, 11, 8, 0)), 1, "a rule with no end reaches any date")
  end)

  test.it("leaves out EXDATE, and a moved instance stands in for its own", function()
    local text = wrap("BEGIN:VEVENT\r\nUID:r\r\nSUMMARY:Standup\r\nDTSTART:20261102T090000Z\r\n" ..
      "RRULE:FREQ=DAILY;COUNT=3\r\nEXDATE:20261103T090000Z\r\nEND:VEVENT\r\n" ..
      "BEGIN:VEVENT\r\nUID:r\r\nSUMMARY:Standup moved\r\nRECURRENCE-ID:20261104T090000Z\r\nDTSTART:20261104T150000Z\r\nEND:VEVENT")
    local rows = test.ipc("times", text, utc(2026, 11, 1, 0), utc(2026, 11, 10, 0))
    test.eq(ats(rows), { utc(2026, 11, 2, 9), utc(2026, 11, 4, 15) })
    test.eq(rows[2].summary, "Standup moved")
  end)

  test.it("leaves out a cancelled event", function()
    test.eq(#test.ipc("times", event { "DTSTART:20261102T090000Z", "STATUS:CANCELLED" },
      utc(2026, 11, 1, 0), utc(2026, 11, 3, 0)), 0)
  end)

  test.it("reads alarms as seconds before", function()
    local out = test.ipc("parse", wrap("BEGIN:VEVENT\r\nDTSTART:20261102T090000Z\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nEND:VALARM\r\n" ..
      "BEGIN:VALARM\r\nTRIGGER:-P1D\r\nEND:VALARM\r\nEND:VEVENT"))
    test.eq(out.events[1].alarms, { 900, 86400 })
  end)

  test.it("finds a meeting link wherever it is written", function()
    local function link(lines)
      local all = { "DTSTART:20261102T090000Z" }
      for _, line in ipairs(lines) do all[#all + 1] = line end
      return test.ipc("parse", event(all)).events[1].link
    end
    test.eq(link { "LOCATION:https://meet.google.com/abc-defg-hij" }, "https://meet.google.com/abc-defg-hij")
    test.eq(link { "DESCRIPTION:Join here: https://acme.zoom.us/j/123?pwd=x\\nThanks." }, "https://acme.zoom.us/j/123?pwd=x")
    test.eq(link { "DESCRIPTION:<https://teams.microsoft.com/l/meetup-join/19%3ameeting>" }, "https://teams.microsoft.com/l/meetup-join/19%3ameeting")
    test.eq(link { "X-GOOGLE-CONFERENCE:https://meet.google.com/xyz" }, "https://meet.google.com/xyz")
    test.eq(link { "URL:https://example.test/agenda", "LOCATION:Room 2" }, "")
  end)

  test.it("walks the calendar's dates both ways", function()
    test.eq(test.ipc("civil", 2024, 2, 29), { 2024, 2, 29 })
    test.eq(test.ipc("civil", 1969, 12, 31), { 1969, 12, 31 })
    test.eq(test.ipc("civil", 2100, 3, 1), { 2100, 3, 1 })
  end)
end)
