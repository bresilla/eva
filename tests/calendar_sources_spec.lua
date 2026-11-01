-- Calendars read from files, folders and addresses, the page built on them,
-- and reminders through the shell's notification list. Taskwarrior is stubbed.
--     morf test --no-dbus tests/calendar_sources_spec.lua
local test = morf.test
local HOST = [[
  local ui = require("morf.ui")
  local W, H = tonumber(morf.env("TEST_WIDTH")), tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height = H
  local config = require("config")
  local tasks = morf.signal("calendar.spec.tasks", {})
  local client = { tasks = tasks, error = morf.signal("calendar.spec.error", ""), busy = morf.signal("calendar.spec.busy", false),
    loaded = morf.signal("calendar.spec.loaded", true), revision = morf.signal("calendar.spec.revision", 1),
    refresh = function() return true end, watch = function() end }
  require("lib.integrations.taskwarrior").new = function() return client end
  local opened
  require("pages").settings = function(route) opened = route end
  local notes = {}
  package.loaded.notifs = { push = function(entry) notes[#notes + 1] = entry return #notes end }
  package.loaded.services = { weather = function()
    if morf.env("NO_WEATHER") == "1" then return { available = false } end
    return { available = true, units = { temperature = "°C" }, daily = { { time = morf.time.now(), high = 12.4, low = 3.6, code = 3, condition = "Overcast" } } }
  end, weather_symbol = function() return "cloud" end }
  local presentation, shown = require("presentation"), false
  local sources, reminders = require("calendar_sources"), require("calendar_reminders")
  local model
  local models = require("calendar_model")
  local new = models.new
  models.new = function(...) model = new(...) return model end
  ui.Item { width = W, height = H, require("calendar_page").build(W, function() return H end) }
  local scope = require("pages").panel_name("calendar") .. ".calendar"
  morf.ipc.show = function() presentation.set(scope, true) end
  morf.ipc.hide = function() presentation.set(scope, false) end
  morf.ipc.set = function(key, json) config.set(key, morf.json.decode(json)) end
  morf.ipc.load = sources.load
  morf.ipc.watch = function(on) sources.watch(on == "yes") end
  morf.ipc.state = function()
    local rows, list = {}, {}
    for i = 1, model.agenda:len() do rows[i] = model.agenda:get(i) end
    for i = 1, sources.sources:len() do list[i] = sources.sources:get(i) end
    local next_up = model.next_up()
    return { rows = rows, sources = list, opened = opened, next_up = next_up or false, summary = sources.summary(),
      connected = model.connected(), weather = model.weather() or false, loading = sources.loading:get(), said = sources.said:get() }
  end
  morf.ipc.count = function(day) return sources.count(day) end
  morf.ipc.day = function(i)
    for n = 1, model.days:len() do local d = model.days:get(n) if d.key == i then return d.count end end
    return -1
  end
  morf.ipc.select = function(day) model.select(day) end
  morf.ipc.today = function() return morf.time.format("%Y-%m-%d") end
  morf.ipc.at = function(hours) return morf.time.format("%Y%m%dT%H%M%S", morf.time.now() + tonumber(hours) * 3600) end
  morf.ipc.fake_tick = function(offset) return reminders.tick(morf.time.now() + tonumber(offset)) end
  morf.ipc.notes = function() return notes end
  morf.ipc.reset_fired = function() morf.fs.remove(morf.paths.state("calendar-reminders.json")) end
  morf.ipc.add_url = sources.add_url
  morf.ipc.add_path = sources.add_path
  morf.ipc.remove_first = function() return sources.remove(sources.sources:get(1)) end
  morf.ipc.host_of = sources.host_of
  morf.ipc.fetchable = sources.fetchable
  morf.ipc.running = reminders.running
  morf.ipc.start = reminders.start
]]
local count = 0
local dir
local function load(style, env, size)
  count = count + 1
  dir = ("%s/calendar-spec-%d-%d"):format(morf.env("XDG_CACHE_HOME"), count, morf.process_id or 0)
  morf.fs.mkdir(dir .. "/vdir")
  local w, h = (size or { 408, 1000 })[1], (size or { 408, 1000 })[2]
  local all = { EVA_STYLE = style or "material", EVA_SETTINGS = dir .. "/eva.json", HOME = dir, XDG_DATA_HOME = "", XDG_CONFIG_HOME = "",
    TEST_WIDTH = tostring(w), TEST_HEIGHT = tostring(h), EVA_DRY_RUN = "1" }
  for name, value in pairs(env or {}) do all[name] = value end
  test.load("../shell/init.lua", { source = HOST, size = { w, h }, env = all })
  test.ipc("reset_fired")
end
local function ics(lines)
  return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nX-WR-CALNAME:Work\r\nBEGIN:VEVENT\r\n" .. table.concat(lines, "\r\n") .. "\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
end
local function state() return test.ipc("state") end
local function read_file(lines)
  morf.fs.write(dir .. "/work.ics", ics(lines))
  test.ipc("set", "calendar.files", morf.json.encode { dir .. "/work.ics" })
  test.ipc("show")
  test.ipc("watch", "yes")
  return test.wait(function() test.advance(30) local s = state() return #s.sources > 0 and not s.loading and s end, 4000, "the calendar")
end
local function agenda_ready()
  return test.wait(function() test.advance(30) local s = state() return #s.rows > 0 and s end, 4000, "the agenda")
end
local function shot(name) if morf.env("EVA_THEME_SNAPSHOTS") == "1" then test.snapshot(name .. ".png") end end

test.describe("calendars", function()
  test.it("says no calendar is set up, offers the settings, and fetches nothing", function()
    load()
    test.ipc("show")
    test.advance(100)
    local s = state()
    test.falsy(s.connected)
    test.truthy(test.find { text = "No calendars yet" })
    test.click("planner-work-row-press")
    test.eq(state().opened, "calendars")
    test.falsy(test.ipc("start"), "reminders need a calendar")
    test.eq(#test.runs(), 0)
  end)

  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. " marks the month and lists the day, with a join button", function()
      load(style)
      local at = test.ipc("at", 2)
      local s = read_file { "UID:1", "SUMMARY:Design review", "DTSTART:" .. at, "DURATION:PT1H", "LOCATION:Room 2",
        "DESCRIPTION:Join https://meet.google.com/abc-defg-hij" }
      test.eq(s.sources[1].name, "Work")
      test.eq(s.sources[1].events, 1)
      local today = at:sub(1, 4) .. "-" .. at:sub(5, 6) .. "-" .. at:sub(7, 8)
      test.ipc("select", today)
      s = agenda_ready()
      test.eq(s.rows[1].description, "Design review")
      test.eq(s.rows[1].event, true)
      test.eq(s.rows[1].link, "https://meet.google.com/abc-defg-hij")
      test.eq(s.rows[1].kind, "Work")
      test.eq(test.ipc("count", today), 1)
      test.eq(test.ipc("day", today), 1)
      test.truthy(test.find { id = "planner-join-" .. s.rows[1].uuid })
      test.truthy(s.next_up.title == "Design review")
      test.eq(s.next_up.link, "https://meet.google.com/abc-defg-hij")
      test.truthy(test.get("planner-join-next-box").visible)
      test.truthy(s.summary:find("1 calendar", 1, true))
      shot(style .. "-calendar")
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it("mixes tasks and events by time, and shows the weather", function()
    load()
    read_file { "UID:1", "SUMMARY:Standup", "DTSTART;VALUE=DATE:" .. test.ipc("at", 0):sub(1, 8) }
    local s = agenda_ready()
    test.eq(s.rows[1].time, "All day")
    test.eq(s.weather.words, "12°C / 4°C")
    test.eq(s.weather.condition, "Overcast")
    test.truthy(test.get("planner-weather").visible)
  end)

  test.it("hides the forecast where there is none", function()
    load(nil, { NO_WEATHER = "1" })
    read_file { "UID:1", "SUMMARY:Standup", "DTSTART:" .. test.ipc("at", 1) }
    test.eq(state().weather, false)
    test.falsy(test.get("planner-weather").visible)
  end)

  test.it("reads a vdir, a file to an event", function()
    load()
    morf.fs.write(dir .. "/vdir/a.ics", ics { "UID:a", "SUMMARY:One", "DTSTART:" .. test.ipc("at", 1) })
    morf.fs.write(dir .. "/vdir/b.ics", ics { "UID:b", "SUMMARY:Two", "DTSTART:" .. test.ipc("at", 2) })
    test.ipc("set", "calendar.folders", morf.json.encode { dir .. "/vdir" })
    test.ipc("show")
    test.ipc("watch", "yes")
    local s = test.wait(function() test.advance(30) local x = state() return #x.sources > 0 and x.sources[1].events == 2 and x end, 4000, "the vdir")
    test.eq(s.sources[1].kind, "folder")
  end)

  test.it("finds what khal and vdirsyncer keep, by themselves", function()
    load()
    morf.fs.write(dir .. "/.local/share/khal/calendars/home/x.ics", ics { "UID:x", "SUMMARY:Found", "DTSTART:" .. test.ipc("at", 1) })
    test.ipc("show")
    test.ipc("watch", "yes")
    local s = test.wait(function() test.advance(30) local x = state() return #x.sources > 0 and x end, 4000, "the found calendar")
    test.eq(s.sources[1].kind, "found")
    test.truthy(s.connected)
    test.ipc("set", "calendar.discover", "false")
    test.ipc("watch", "yes")
    test.wait(function() test.advance(30) return #state().sources == 0 end, 4000, "nothing found")
  end)

  test.it("reads the folder named in a vdirsyncer config", function()
    load()
    morf.fs.write(dir .. "/.config/vdirsyncer/config", '[storage cal]\ntype = "filesystem"\npath = "' .. dir .. '/synced"\nfileext = ".ics"\n')
    morf.fs.write(dir .. "/synced/work/e.ics", ics { "UID:e", "SUMMARY:Synced", "DTSTART:" .. test.ipc("at", 1) })
    test.ipc("show")
    test.ipc("watch", "yes")
    local s = test.wait(function() test.advance(30) local x = state() return #x.sources > 0 and x end, 4000, "the synced calendar")
    test.eq(s.sources[1].events, 1)
  end)

  test.it("rereads a file another program changes", function()
    load()
    read_file { "UID:1", "SUMMARY:Before", "DTSTART:" .. test.ipc("at", 1) }
    morf.fs.write(dir .. "/work.ics", ics { "UID:1", "SUMMARY:After", "DTSTART:" .. test.ipc("at", 1) } ..
      ics { "UID:2", "SUMMARY:Added", "DTSTART:" .. test.ipc("at", 3) })
    test.wait(function() test.advance(50) local s = state() return s.sources[1] and s.sources[1].events == 2 end, 4000, "the changed file")
  end)

  test.it("says a broken path is not there", function()
    load()
    test.falsy(test.ipc("add_path", dir .. "/missing.ics"))
    test.truthy(state().said:find("Nothing is at", 1, true))
    test.falsy(test.ipc("add_url", "not an address"))
    test.truthy(state().said:find("address", 1, true))
  end)

  test.it("takes an address, showing only its host", function()
    load()
    test.eq(test.ipc("host_of", "https://cal.example.test/private/token123.ics"), "cal.example.test")
    test.eq(test.ipc("fetchable", "webcal://cal.example.test/a.ics"), "https://cal.example.test/a.ics")
  end)

  test.it("reminds at the event's own alarm, once", function()
    load()
    read_file { "UID:r", "SUMMARY:Standup", "DTSTART:" .. test.ipc("at", 1), "LOCATION:Room 2",
      "BEGIN:VALARM", "ACTION:DISPLAY", "TRIGGER:-PT15M", "END:VALARM" }
    test.wait(function() test.advance(30) return state().next_up end, 3000, "the instance")
    test.eq(test.ipc("fake_tick", 0), 0, "too early")
    test.eq(test.ipc("fake_tick", 46 * 60), 1)
    local notes = test.ipc("notes")
    test.eq(notes[1].summary, "Standup")
    test.eq(notes[1].app, "Calendar")
    test.truthy(notes[1].body:find("In 14 minutes", 1, true), notes[1].body)
    test.truthy(notes[1].body:find("Room 2", 1, true))
    test.eq(test.ipc("fake_tick", 47 * 60), 0, "not twice")
  end)

  test.it("falls back to the lead from the settings", function()
    load()
    test.ipc("set", "calendar.lead", "20")
    read_file { "UID:l", "SUMMARY:Review", "DTSTART:" .. test.ipc("at", 1) }
    test.wait(function() test.advance(30) return state().next_up end, 3000, "the instance")
    test.eq(test.ipc("fake_tick", 35 * 60), 0)
    test.eq(test.ipc("fake_tick", 41 * 60), 1)
  end)

  test.it("says nothing with reminders off", function()
    load()
    test.ipc("set", "calendar.reminders", "false")
    read_file { "UID:o", "SUMMARY:Quiet", "DTSTART:" .. test.ipc("at", 0.1) }
    test.eq(test.ipc("fake_tick", 0), 0)
  end)

  test.it("gives one morning line for the day's all-day events", function()
    load()
    read_file { "UID:d", "SUMMARY:Conference", "DTSTART;VALUE=DATE:" .. test.ipc("at", 0):sub(1, 8) }
    test.wait(function() test.advance(30) return test.ipc("count", test.ipc("today")) > 0 end, 3000, "the day")
    local first = test.ipc("fake_tick", 0)
    local hour = tonumber(morf.time.format("%H"))
    if hour >= 8 then
      test.eq(first, 1)
      test.eq(test.ipc("notes")[1].body, "Conference")
      test.eq(test.ipc("fake_tick", 60), 0, "once a day")
    end
  end)
end)
