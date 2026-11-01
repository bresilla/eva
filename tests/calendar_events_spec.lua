-- Calendar events made, changed and deleted from the page: each write lands in
-- the file the event belongs to, other programs' lines survive it, and what
-- cannot be written says so. Taskwarrior is stubbed; files live under the
-- spec's cache.
--     tools/test.sh tests/calendar_events_spec.lua
local test = morf.test
local HOST = [[
  local ui = require("morf.ui")
  local W, H = tonumber(morf.env("TEST_WIDTH")), tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height = H
  local config = require("config")
  local client = { tasks = morf.signal("cal.tasks", {}), error = morf.signal("cal.error", ""), busy = morf.signal("cal.busy", false),
    loaded = morf.signal("cal.loaded", true), revision = morf.signal("cal.revision", 1), refresh = function() return true end, watch = function() end }
  require("lib.integrations.taskwarrior").new = function() return client end
  local notes = {}
  package.loaded.notifs = { push = function(entry) notes[#notes + 1] = entry return #notes end }
  package.loaded.services = { weather = function() return { available = false } end, weather_symbol = function() return "cloud" end }
  local presentation = require("presentation")
  local sources, reminders = require("calendar_sources"), require("calendar_reminders")
  local model
  local models = require("calendar_model")
  local new = models.new
  models.new = function(...) model = new(...) return model end
  ui.Item { width = W, height = H, require("calendar_page").build(W, function() return H end) }
  local scope = require("pages").panel_name("calendar") .. ".calendar"
  presentation.set(scope, true)
  morf.ipc.set = function(key, json) config.set(key, morf.json.decode(json)) end
  morf.ipc.get = function(key) return config.get(key) end
  morf.ipc.watch = function() sources.watch(true) end
  morf.ipc.state = function()
    local rows, list = {}, {}
    for i = 1, model.agenda:len() do rows[i] = model.agenda:get(i) end
    for i = 1, sources.sources:len() do list[i] = sources.sources:get(i) end
    return { rows = rows, sources = list, loading = sources.loading:get(), mode = model.events.mode:get(),
      error = model.events.error:get(), writable = sources.writable(), repeats = model.events.draft.repeats,
      reminder = model.events.draft.reminder, until_day = model.events.draft.until_day, scope = model.events.draft.scope,
      summary = model.events.draft.summary, deleting = model.events.deleting:get(), why = model.events.locked_why:get(),
      to_day = model.events.draft.to_day, from_time = model.events.draft.from_time }
  end
  morf.ipc.select = function(day) model.select(day) end
  morf.ipc.today = function() return morf.time.format("%Y-%m-%d") end
  morf.ipc.day_after = function(days) return morf.time.format("%Y-%m-%d", morf.time.now() + tonumber(days) * 86400) end
  morf.ipc.stamp = function(days, hour)
    local date = morf.time.date(morf.time.now() + tonumber(days) * 86400)
    return ("%04d%02d%02dT%02d0000"):format(date.year, date.month, date.day, tonumber(hour))
  end
  morf.ipc.create = function(day) return model.events.create(day) end
  morf.ipc.open_row = function(index)
    local row = model.agenda:get(tonumber(index))
    return model.events.open(row.uid, row.at)
  end
  morf.ipc.draft = function(json)
    for key, value in pairs(morf.json.decode(json)) do model.events.set(key, value) end
  end
  morf.ipc.save = function() return model.events.save() end
  morf.ipc.delete = function() return model.events.delete() end
  morf.ipc.close = function() model.events.close() end
  morf.ipc.personal = function() return sources.personal_path() end
  morf.ipc.running = reminders.running
  morf.ipc.fake_tick = function(offset) return reminders.tick(morf.time.now() + tonumber(offset)) end
  morf.ipc.notes = function() return notes end
  morf.ipc.reset = function()
    morf.fs.remove(morf.paths.state("calendar-reminders.json"))
    morf.fs.remove(sources.personal_path())
  end
]]
local count = 0
local dir
local function load(style, size, env)
  count = count + 1
  dir = ("%s/calendar-events-%d-%d"):format(morf.env("XDG_CACHE_HOME"), count, morf.process_id or 0)
  morf.fs.mkdir(dir .. "/vdir")
  local w, h = (size or { 408, 1000 })[1], (size or { 408, 1000 })[2]
  local all = { EVA_STYLE = style or "material", EVA_SETTINGS = dir .. "/eva.json", HOME = dir, XDG_DATA_HOME = "", XDG_CONFIG_HOME = "",
    TEST_WIDTH = tostring(w), TEST_HEIGHT = tostring(h), EVA_DRY_RUN = "" }
  for name, value in pairs(env or {}) do all[name] = value end
  test.load("../shell/init.lua", { source = HOST, size = { w, h }, env = all })
  test.ipc("reset")
end
local function ics(blocks, name)
  return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" .. (name and ("X-WR-CALNAME:" .. name .. "\r\n") or "") .. table.concat(blocks, "") .. "END:VCALENDAR\r\n"
end
local function vevent(lines) return "BEGIN:VEVENT\r\n" .. table.concat(lines, "\r\n") .. "\r\nEND:VEVENT\r\n" end
local function state() return test.ipc("state") end
local function settled(want)
  return test.wait(function() test.advance(40) local s = state() return not s.loading and want(s) and s end, 5000, "the calendar")
end
local function read_file(lines, name)
  morf.fs.write(dir .. "/work.ics", ics({ vevent(lines) }, name or "Work"))
  test.ipc("set", "calendar.files", morf.json.encode { dir .. "/work.ics" })
  test.ipc("watch")
  return settled(function(s) return #s.sources > 0 end)
end
local function agenda(day)
  test.ipc("select", day)
  return settled(function(s) return #s.rows > 0 end)
end
local function file() return morf.fs.read(dir .. "/work.ics") end
local function has(text, part) test.truthy(text:find(part, 1, true), ("expected %q in:\n%s"):format(part, text)) end
local function lacks(text, part) test.falsy(text:find(part, 1, true), ("did not expect %q in:\n%s"):format(part, text)) end
local function json(value) return morf.json.encode(value) end

test.describe("calendar events", function()
  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. ": the page makes an event, and it lands in the calendar's file", function()
      load(style)
      local day = test.ipc("day_after", 2)
      local s = read_file { "UID:a", "SUMMARY:Standing", "DTSTART:" .. test.ipc("stamp", 2, 8), "DURATION:PT1H" }
      test.eq(s.writable[1].name, "Work")
      test.ipc("select", day)
      test.advance(50)
      test.click("planner-add-event")
      test.settle(200)
      test.eq(state().mode, "new")
      test.truthy(test.get("event-form").visible)
      test.truthy(test.get("event-title").visible)
      test.falsy(test.get("planner-scroll").visible)
      test.ipc("draft", json { summary = "Dentist, then lunch", location = "Main St", from_time = "14:30", to_time = "15:15" })
      test.click("event-save")
      test.advance(50)
      test.eq(state().mode, "", state().error)
      test.falsy(test.get("event-form").visible)
      local text = file()
      has(text, "SUMMARY:Dentist\\, then lunch")
      has(text, "LOCATION:Main St")
      has(text, "UID:a")
      s = settled(function(x) return #x.rows == 2 end)
      test.eq(s.rows[2].description, "Dentist, then lunch")
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it("writes an all-day event as dates, its last day included", function()
    load()
    read_file { "UID:a", "SUMMARY:Other", "DTSTART:" .. test.ipc("stamp", 40, 8) }
    local day, last = test.ipc("day_after", 3), test.ipc("day_after", 5)
    test.ipc("create", day)
    test.ipc("draft", json { summary = "Conference", all_day = true, to_day = last })
    test.truthy(test.ipc("save"))
    local text = file()
    has(text, "DTSTART;VALUE=DATE:" .. day:gsub("%-", ""))
    has(text, "DTEND;VALUE=DATE:" .. test.ipc("day_after", 6):gsub("%-", ""))
    local s = agenda(last)
    test.eq(s.rows[1].time, "All day")
    test.ipc("open_row", 1)
    s = state()
    test.eq(s.to_day, last, "the form shows the last day, not the day after")
  end)

  test.it("a new vdir event is a file of its own; deleting it takes the file", function()
    load()
    morf.fs.write(dir .. "/vdir/x.ics", ics { vevent { "UID:x", "SUMMARY:There", "DTSTART:" .. test.ipc("stamp", 30, 8) } })
    test.ipc("set", "calendar.folders", json { dir .. "/vdir" })
    test.ipc("watch")
    settled(function(s) return #s.sources > 0 end)
    local day = test.ipc("day_after", 2)
    test.ipc("create", day)
    test.ipc("draft", json { summary = "Own file" })
    test.truthy(test.ipc("save"))
    local names = {}
    for _, entry in ipairs(morf.fs.list(dir .. "/vdir")) do names[#names + 1] = entry.name end
    test.eq(#names, 2)
    local s = agenda(day)
    test.eq(s.rows[1].description, "Own file")
    test.ipc("open_row", 1)
    test.falsy(test.ipc("delete"), "the first press only asks")
    test.eq(#morf.fs.list(dir .. "/vdir"), 2)
    test.truthy(test.ipc("delete"))
    test.eq(#morf.fs.list(dir .. "/vdir"), 1)
  end)

  test.it("changing an event keeps every line of it eva does not know", function()
    load()
    local at = test.ipc("stamp", 2, 9)
    read_file { "UID:keep", "SUMMARY:Review", "ORGANIZER;CN=Kate:mailto:kate@example.test", "ATTENDEE;PARTSTAT=ACCEPTED:mailto:me@example.test",
      "X-CUSTOM:stays", "DTSTART:" .. at, "DTEND:" .. test.ipc("stamp", 2, 10), "SEQUENCE:4",
      "BEGIN:VALARM", "ACTION:AUDIO", "TRIGGER:-PT30M", "END:VALARM" }
    agenda(test.ipc("day_after", 2))
    test.truthy(test.ipc("open_row", 1))
    test.ipc("draft", json { summary = "Design review" })
    test.truthy(test.ipc("save"))
    local text = file()
    has(text, "SUMMARY:Design review")
    has(text, "ORGANIZER;CN=Kate:mailto:kate@example.test")
    has(text, "ATTENDEE;PARTSTAT=ACCEPTED:mailto:me@example.test")
    has(text, "X-CUSTOM:stays")
    has(text, "DTSTART:" .. at)
    has(text, "ACTION:AUDIO")
    has(text, "SEQUENCE:5")
    lacks(text, "SUMMARY:Review")
  end)

  test.it("this one moves a single instance, and all of them moves the series", function()
    load()
    local first = test.ipc("stamp", 1, 9)
    read_file { "UID:rep", "SUMMARY:Standup", "DTSTART:" .. first, "DURATION:PT30M", "RRULE:FREQ=DAILY" }
    local day = test.ipc("day_after", 3)
    agenda(day)
    test.truthy(test.ipc("open_row", 1))
    local s = state()
    test.eq(s.repeats, "DAILY")
    test.eq(s.scope, "one")
    test.ipc("draft", json { from_time = "11:00", to_time = "11:30" })
    test.truthy(test.ipc("save"))
    local text = file()
    has(text, "RECURRENCE-ID:" .. test.ipc("stamp", 3, 9))
    has(text, "DTSTART:" .. test.ipc("stamp", 3, 11))
    has(text, "RRULE:FREQ=DAILY")
    settled(function(x) return #x.rows == 1 and x.rows[1].time:find("11:00", 1, true) end)
    agenda(test.ipc("day_after", 4))
    test.truthy(test.ipc("open_row", 1))
    test.ipc("draft", json { scope = "all", from_time = "08:00", to_time = "08:30" })
    test.truthy(test.ipc("save"))
    has(file(), "DTSTART:" .. test.ipc("stamp", 1, 8))
    s = settled(function(x) return #x.rows == 1 and x.rows[1].time:find("08:00", 1, true) end)
    test.eq(s.rows[1].description, "Standup")
  end)

  test.it("deleting one instance leaves the rest; deleting all takes the event", function()
    load()
    read_file { "UID:rep", "SUMMARY:Standup", "DTSTART:" .. test.ipc("stamp", 1, 9), "RRULE:FREQ=DAILY" }
    local day = test.ipc("day_after", 2)
    agenda(day)
    test.ipc("open_row", 1)
    test.ipc("delete")
    test.truthy(test.ipc("delete"))
    has(file(), "EXDATE:" .. test.ipc("stamp", 2, 9))
    settled(function(x) return #x.rows == 0 end)
    agenda(test.ipc("day_after", 3))
    test.ipc("open_row", 1)
    test.ipc("draft", json { scope = "all" })
    test.ipc("delete")
    test.truthy(test.ipc("delete"))
    lacks(file(), "VEVENT")
    has(file(), "END:VCALENDAR")
  end)

  test.it("says a rule it cannot edit, and leaves it alone", function()
    load()
    local rule = "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=20"
    read_file { "UID:rule", "SUMMARY:Gym", "DTSTART:" .. test.ipc("stamp", 1, 9), rule }
    test.wait(function() test.advance(40) test.ipc("select", test.ipc("today")) return true end, 200, "a turn")
    local s
    for offset = 1, 14 do
      test.ipc("select", test.ipc("day_after", offset))
      test.advance(40)
      s = state()
      if #s.rows > 0 then break end
    end
    test.truthy(#s.rows > 0, "an instance")
    test.ipc("open_row", 1)
    test.ipc("draft", json { scope = "all", summary = "Gym twice" })
    test.eq(state().repeats, "custom")
    test.truthy(test.get("event-custom-rule").visible)
    test.truthy(test.ipc("save"))
    has(file(), rule)
    has(file(), "SUMMARY:Gym twice")
  end)

  test.it("an address reads, and says it cannot be written", function()
    load()
    local cached = morf.paths.cache("calendars")
    morf.fs.mkdir(cached)
    test.ipc("set", "calendar.urls", json { "https://calendar.example.test/x.ics" })
    test.ipc("watch")
    test.wait(function() test.advance(40) return #state().sources > 0 end, 3000, "the address row")
    local s = state()
    test.truthy(s.sources[1].locked ~= "", "an address is read-only")
    test.eq(#s.writable, 0)
    test.eq(#test.runs(), 0, "nothing was run")
  end)

  test.it("a file the disk will not let us write opens read-only", function()
    load()
    local at = test.ipc("stamp", 2, 9)
    local path = dir .. "/fixed.ics"
    morf.fs.write(path, ics({ vevent { "UID:f", "SUMMARY:Fixed", "DTSTART:" .. at } }, "Fixed"), { mode = 292 })
    test.ipc("set", "calendar.files", json { path })
    test.ipc("watch")
    settled(function(s) return #s.sources > 0 end)
    local s = agenda(test.ipc("day_after", 2))
    test.eq(#s.writable, 0)
    test.ipc("open_row", 1)
    s = state()
    test.eq(s.mode, "read")
    test.truthy(s.why:find("read-only", 1, true), s.why)
    test.truthy(test.get("event-details-locked").visible)
    test.falsy(test.get("event-save").visible)
    test.falsy(test.ipc("save"))
    test.falsy(test.ipc("delete"))
    test.ipc("close")
  end)

  test.it("khal's and vdirsyncer's read-only marks are honoured", function()
    load()
    morf.fs.write(dir .. "/.config/khal/config", '[calendars]\n[[fixed]]\npath = ' .. dir .. '/synced/fixed\nreadonly = True\n[[open]]\npath = ' .. dir .. '/synced/open\n')
    morf.fs.write(dir .. "/synced/fixed/e.ics", ics { vevent { "UID:e", "SUMMARY:Synced", "DTSTART:" .. test.ipc("stamp", 1, 9) } })
    morf.fs.write(dir .. "/synced/open/o.ics", ics { vevent { "UID:o", "SUMMARY:Open", "DTSTART:" .. test.ipc("stamp", 1, 9) } })
    test.ipc("watch")
    local s = settled(function(x) return #x.sources == 2 end)
    test.eq(#s.writable, 1)
    test.eq(s.writable[1].name, "open")
  end)

  test.it("with no calendar, the first event makes one and reminders start", function()
    load()
    test.falsy(test.ipc("running"))
    test.ipc("watch")
    test.advance(100)
    test.ipc("create", test.ipc("day_after", 1))
    test.ipc("draft", json { summary = "First" })
    test.truthy(test.ipc("save"), state().error)
    test.truthy(morf.fs.exists(test.ipc("personal")))
    test.eq(test.ipc("get", "calendar.files"), { test.ipc("personal") })
    test.truthy(test.ipc("running"))
    local s = settled(function(x) return #x.sources == 1 end)
    test.eq(s.sources[1].name, "Personal")
  end)

  test.it("a reminder set here is the one that rings", function()
    load()
    local day = test.ipc("day_after", 1)
    read_file { "UID:a", "SUMMARY:Other", "DTSTART:" .. test.ipc("stamp", 60, 8) }
    test.ipc("create", day)
    test.ipc("draft", json { summary = "Call", from_time = "10:00", to_time = "10:30", reminder = "1800" })
    test.truthy(test.ipc("save"))
    has(file(), "TRIGGER:-PT30M")
    local s = agenda(day)
    test.ipc("open_row", 1)
    test.eq(state().reminder, "1800")
    test.ipc("draft", json { reminder = "none" })
    test.truthy(test.ipc("save"))
    has(file(), "ACTION:NONE")
    lacks(file(), "TRIGGER:-PT30M")
    test.advance(600)
    settled(function(x) return #x.rows == 1 end)
    test.ipc("open_row", 1)
    test.eq(state().reminder, "none", "no reminder reads back as none")
    test.ipc("close")
    local rung = 0
    for offset = 0, 1560, 60 do rung = rung + test.ipc("fake_tick", offset * 60) end
    test.eq(rung, 0, "an event that turned reminders off never rings")
  end)

  test.it("an all-day event rings at its own reminder, in words for a day", function()
    load()
    local day = test.ipc("day_after", 2)
    read_file { "UID:a", "SUMMARY:Other", "DTSTART:" .. test.ipc("stamp", 60, 8) }
    test.ipc("create", day)
    test.ipc("draft", json { summary = "Holiday", all_day = true, reminder = "54000" })
    test.truthy(test.ipc("save"))
    has(file(), "TRIGGER:-PT900M")
    test.advance(600)
    settled(function(x) return x.sources[1].events == 2 end)
    local rung = 0
    for hour = 0, 40 do
      rung = rung + test.ipc("fake_tick", hour * 3600)
      if rung > 0 then break end
    end
    test.eq(rung, 1)
    local note = test.ipc("notes")[1]
    test.eq(note.summary, "Holiday")
    test.truthy(note.body:find("All day", 1, true), note.body)
  end)

  test.it("refuses what does not read, and keeps the form open", function()
    load()
    read_file { "UID:a", "SUMMARY:Other", "DTSTART:" .. test.ipc("stamp", 60, 8) }
    test.ipc("create", test.ipc("day_after", 1))
    test.falsy(test.ipc("save"))
    test.truthy(state().error:find("name", 1, true))
    test.ipc("draft", json { summary = "x", from_time = "25:00" })
    test.falsy(test.ipc("save"))
    test.truthy(state().error:find("start time", 1, true))
    test.ipc("draft", json { from_time = "11:00", to_time = "10:00" })
    test.falsy(test.ipc("save"))
    test.truthy(state().error:find("before it starts", 1, true))
    test.ipc("draft", json { to_time = "12:00", from_day = "2026-02-31" })
    test.falsy(test.ipc("save"))
    test.truthy(state().error:find("not a date", 1, true))
    test.eq(state().mode, "new")
    lacks(file(), "SUMMARY:x")
  end)

  test.it("a preview writes nothing", function()
    load(nil, nil, { EVA_DRY_RUN = "1" })
    read_file { "UID:a", "SUMMARY:Other", "DTSTART:" .. test.ipc("stamp", 60, 8) }
    local before = file()
    test.ipc("create", test.ipc("day_after", 1))
    test.ipc("draft", json { summary = "Never" })
    test.falsy(test.ipc("save"))
    test.truthy(state().error:find("preview", 1, true))
    test.eq(file(), before)
  end)

  test.it("the form fits a phone", function()
    load("material", { 412, 915 })
    read_file { "UID:a", "SUMMARY:Other", "DTSTART:" .. test.ipc("stamp", 60, 8) }
    test.ipc("create", test.ipc("today"))
    test.advance(100)
    local form = test.get("event-form")
    test.truthy(form.x >= 0 and form.x + form.width <= 412)
    test.truthy(test.get("event-save").visible)
    test.eq(#test.logs("error"), 0)
  end)
end)
