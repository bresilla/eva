-- eva-clock: the words it takes, the store, the two ways of ringing, the bar's
-- indicator reading it, the window, and the command line. A ring through the
-- shell's notifications server for real is tools/see/clock.steps'.
--
--     morf test --no-dbus tests/clock_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
-- Monday 2 November 2026, 10:00 UTC.
local MONDAY = 1793613600

local HOST = [[
  local morf = require("morf")
  local ui = require("morf.ui")
  ui.Item { width = 1, height = 1 }
  local lib = require("lib.services.alarm")
  local a = lib.new { ring = true }
  a.load()
  morf.ipc.parse = function(...)
    local item, why = lib.parse(table.concat({ ... }, " "))
    return item or { why = why }
  end
  morf.ipc.add = function(...)
    local item, why = a.add(table.concat({ ... }, " "))
    return item or { why = why }
  end
  morf.ipc.state = function()
    return { items = a.items:get(), ongoing = a.ongoing:get(), armed = a.armed(), rang = a.rang:get(),
      message = a.message:get() }
  end
  morf.ipc.remove = function(id) a.remove(id) return true end
  morf.ipc.set = function(id, on) a.set(id, on == "on") return true end
  morf.ipc.extend = function(id, seconds) a.extend(id, tonumber(seconds)) return true end
  morf.ipc.snooze = function(id, minutes) a.snooze(id, minutes) return true end
  morf.ipc.finish = function(id) a.finish(id) return true end
  morf.ipc.sync = function() a.sync() return true end
  morf.ipc.words = function(n)
    return { span = lib.span(tonumber(n)), running = lib.running(tonumber(n)) }
  end
]]

local function fresh(name)
  local state = morf.env("XDG_STATE_HOME") .. "/clock-" .. name .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  return state
end

local function host(name, env)
  local full = { XDG_STATE_HOME = fresh(name), EVA_DRY_RUN = "1", EVA_NOW = tostring(MONDAY), EVA_ALARM_ENGINE = "local" }
  for key, value in pairs(env or {}) do full[key] = value end
  test.load("../shell/init.lua", { source = HOST, env = full })
  return full
end

-- ---------------------------------------------------------------- the words --

test.it("takes a timer however it is said", function()
  host("timers")
  local cases = {
    { "timer 12 min pasta", 720, "pasta" },
    { "12 minutes pasta", 720, "pasta" },
    { "pasta in 12 min", 720, "pasta" },
    { "timer 5", 300, "" },
    { "1h30 bread", 5400, "bread" },
    { "1 h 30 m bread", 5400, "bread" },
    { "90s tea", 90, "tea" },
    { "half an hour nap", 1800, "nap" },
    { "an hour", 3600, "" },
  }
  for _, case in ipairs(cases) do
    local item = test.ipc("parse", case[1])
    test.eq(item.kind, "timer", case[1])
    test.eq(item.seconds, case[2], case[1])
    test.eq(item.label, case[3], case[1])
  end
end)

test.it("takes an alarm however it is said", function()
  host("alarms")
  local cases = {
    { "at 6pm", 18, 0, "" },
    { "6pm call mum", 18, 0, "call mum" },
    { "at 18:30 standup", 18, 30, "standup" },
    { "7:45 am", 7, 45, "" },
    { "12am", 0, 0, "" },
    { "12pm", 12, 0, "" },
    { "at noon lunch", 12, 0, "lunch" },
    { "midnight", 0, 0, "" },
  }
  for _, case in ipairs(cases) do
    local item = test.ipc("parse", case[1])
    test.eq(item.kind, "alarm", case[1])
    test.eq(item.hour, case[2], case[1])
    test.eq(item.minute, case[3], case[1])
    test.eq(item.label, case[4], case[1])
  end
end)

test.it("takes the days", function()
  host("days")
  test.eq(#test.ipc("parse", "every weekday 7:30 gym").days, 5)
  test.eq(test.ipc("parse", "every weekday 7:30 gym").label, "gym")
  test.eq(#test.ipc("parse", "every day at 8").days, 7)
  test.eq(#test.ipc("parse", "weekends 9am").days, 2)
  test.eq(#test.ipc("parse", "every tue thu 18:00").days, 2)
  test.eq(test.ipc("parse", "tuesdays 18:00").days[1], 2)
  test.eq(test.ipc("parse", "at 6pm").days, nil)
  local today, tomorrow = test.ipc("parse", "at 23:59"), test.ipc("parse", "tomorrow at 23:59")
  test.truthy(tomorrow.at - today.at > 86000)
end)

test.it("says what it needs when the words make no time", function()
  host("nonsense")
  test.contains(test.ipc("parse", "pasta").why, "timer 12 min pasta")
  test.contains(test.ipc("parse", "").why, "at 6pm")
end)

test.it("writes a span and a running clock", function()
  host("spans")
  test.eq(test.ipc("words", "720").span, "12 min")
  test.eq(test.ipc("words", "5400").span, "1 h 30 min")
  test.eq(test.ipc("words", "692").running, "11:32")
  test.eq(test.ipc("words", "3725").running, "1:02:05")
end)

-- ---------------------------------------------------------------- the store --

test.it("keeps what is set, across a start", function()
  local env = host("store")
  local item = test.ipc("add", "timer 12 min pasta")
  test.eq(item.at, MONDAY + 720)
  test.load("../shell/init.lua", { source = HOST, env = env })
  local state = test.ipc("state")
  test.eq(#state.items, 1)
  test.eq(state.items[1].label, "pasta")
  test.truthy(state.armed)
  test.eq((morf.fs.stat(env.XDG_STATE_HOME .. "/eva/clock/alarms.json").mode or 0) & 63, 0)
end)

test.it("says what is running and what is armed", function()
  host("signals")
  test.falsy(test.ipc("state").armed)
  local timer = test.ipc("add", "timer 5 min")
  local alarm = test.ipc("add", "at 18:00")
  local state = test.ipc("state")
  test.truthy(state.armed)
  test.eq(#state.ongoing, 1)
  test.eq(state.ongoing[1].id, timer.id)
  test.ipc("set", alarm.id, "off")
  test.ipc("remove", timer.id)
  test.falsy(test.ipc("state").armed)
end)

test.it("follows a store another process wrote", function()
  local env = host("follow")
  test.ipc("add", "timer 5 min elsewhere")
  local list = morf.json.decode(morf.fs.read(env.XDG_STATE_HOME .. "/eva/clock/alarms.json"))
  list[#list + 1] = { id = "other", kind = "timer", label = "other", on = true, at = MONDAY + 60, seconds = 60 }
  morf.fs.write(env.XDG_STATE_HOME .. "/eva/clock/alarms.json", morf.json.encode(list), { atomic = true })
  test.wait(function() return #test.ipc("state").items == 2 end, 3000, "the store was followed")
end)

test.it("a snoozed repeating alarm keeps repeating", function()
  host("snooze")
  local alarm = test.ipc("add", "every day 7:30 gym")
  test.ipc("snooze", alarm.id, "9")
  local state = test.ipc("state")
  test.eq(#state.items, 2)
  local kinds = {}
  for _, item in ipairs(state.items) do kinds[item.kind] = item end
  test.eq(#kinds.alarm.days, 7)
  test.eq(kinds.timer.at, MONDAY + 540)
  test.eq(kinds.timer.label, "gym")
end)

test.it("a timer goes when it has rung, a one-off alarm goes off", function()
  host("finish")
  local timer, alarm = test.ipc("add", "timer 1 min"), test.ipc("add", "at 18:00")
  test.ipc("finish", timer.id)
  test.ipc("finish", alarm.id)
  local state = test.ipc("state")
  test.eq(#state.items, 1)
  test.falsy(state.items[1].on)
  test.falsy(state.armed)
end)

-- -------------------------------------------------------------------- ringing --

test.it("keeps the time itself where there is no systemd", function()
  host("local")
  local timer = test.ipc("add", "timer 1 min tea")
  test.advance(59000)
  test.eq(#test.ipc("state").rang, 0)
  test.advance(2000)
  test.eq(test.ipc("state").rang[1], timer.id)
  test.eq(#test.ipc("state").items, 0)
  test.eq(#test.runs(), 0)
end)

test.it("a change to the store leaves the running wait alone", function()
  local env = host("rearm")
  local timer = test.ipc("add", "timer 1 min tea")
  test.advance(30000)
  local path = env.XDG_STATE_HOME .. "/eva/clock/alarms.json"
  local list = morf.json.decode(morf.fs.read(path))
  list[#list + 1] = { id = "later", kind = "timer", label = "", on = true, at = MONDAY + 600, seconds = 600 }
  morf.fs.write(path, morf.json.encode(list), { atomic = true })
  test.wait(function() return #test.ipc("state").items == 2 end, 3000, "the store was followed")
  test.advance(31000)
  test.eq(test.ipc("state").rang[1], timer.id)
end)

test.it("makes a timer unit of each entry with systemd", function()
  host("units", { EVA_ALARM_ENGINE = "systemd", EVA_DRY_RUN = "0" })
  test.stub_run("systemctl", { code = 0 })
  test.stub_run("systemd-run", { code = 0 })
  local item = test.ipc("add", "every weekday 7:30 gym")
  test.settle(200)
  local argv
  for _, run in ipairs(test.runs()) do
    if run[1] == "systemd-run" then argv = table.concat(run, " ") end
  end
  test.truthy(argv)
  test.contains(argv, "--user")
  test.contains(argv, "--unit=eva-alarm-" .. item.id)
  test.contains(argv, "--on-calendar=Mon,Tue,Wed,Thu,Fri *-*-* 07:30:00")
  test.contains(argv, "fire " .. item.id .. " gym")
  test.advance(100000)
  test.eq(#test.ipc("state").rang, 0)
end)

test.it("a unit carries what it needs of the session", function()
  host("carried", { EVA_ALARM_ENGINE = "systemd", EVA_DRY_RUN = "0", PATH = "/some/bin:/other/bin",
    WAYLAND_DISPLAY = "wayland-7", EVA_ALARM_SOUND = "/a/sound.oga" })
  test.stub_run("systemctl", { code = 0 })
  test.stub_run("systemd-run", { code = 0 })
  test.ipc("add", "timer 5 min")
  test.settle(200)
  local argv
  for _, run in ipairs(test.runs()) do
    if run[1] == "systemd-run" then argv = run end
  end
  local before = {}
  for _, word in ipairs(argv) do
    if word == "--" then break end
    before[word] = true
  end
  test.truthy(before["--setenv=PATH=/some/bin:/other/bin"])
  test.truthy(before["--setenv=WAYLAND_DISPLAY=wayland-7"])
  test.truthy(before["--setenv=EVA_ALARM_SOUND=/a/sound.oga"])
end)

test.it("takes the unit away with the entry", function()
  host("disarm", { EVA_ALARM_ENGINE = "systemd", EVA_DRY_RUN = "0" })
  test.stub_run("systemctl", { code = 0 })
  test.stub_run("systemd-run", { code = 0 })
  local item = test.ipc("add", "timer 5 min")
  test.settle(200)
  test.clear_stubs()
  test.stub_run("systemctl", { code = 0 })
  test.ipc("remove", item.id)
  test.settle(200)
  local last = test.runs()[#test.runs()]
  test.contains(table.concat(last, " "), "stop eva-alarm-" .. item.id .. ".timer")
end)

test.it("puts lost units back, and rings what came due", function()
  local env = host("sync", { EVA_ALARM_ENGINE = "systemd", EVA_DRY_RUN = "1" })
  local list = {
    { id = "late", kind = "timer", label = "late", on = true, seconds = 60, at = MONDAY - 30 },
    { id = "long", kind = "timer", label = "long", on = true, seconds = 60, at = MONDAY - 9000 },
    { id = "later", kind = "timer", label = "later", on = true, seconds = 60, at = MONDAY + 600 },
  }
  morf.fs.write(env.XDG_STATE_HOME .. "/eva/clock/alarms.json", morf.json.encode(list), { atomic = true, parents = true })
  test.load("../shell/init.lua", { source = HOST, env = env })
  test.ipc("sync")
  local state = test.ipc("state")
  test.eq(state.rang[1], "late")
  test.contains(state.message, "Missed")
  test.eq(#state.items, 1)
  test.eq(state.items[1].id, "later")
end)

-- ----------------------------------------------------------------- the shell --

test.it("services.alarm is what the bar's indicator reads", function()
  local state = fresh("bar")
  morf.fs.write(state .. "/eva/clock/alarms.json", morf.json.encode {
    { id = "a", kind = "alarm", label = "", on = true, hour = 7, minute = 0, at = MONDAY + 3600 },
  }, { parents = true })
  test.load("../shell/init.lua", { env = { XDG_STATE_HOME = state, EVA_DRY_RUN = "1", EVA_NOW = tostring(MONDAY),
    EVA_ALARM_ENGINE = "local" }, source = [[
    local morf = require("morf")
    local ui = require("morf.ui")
    ui.Item { width = 1, height = 1 }
    local services = require("services")
    services.alarm.load()
    morf.ipc.indicators = function()
      local keys = {}
      for _, item in ipairs(require("status_model").read(services)) do keys[#keys + 1] = item.key end
      return table.concat(keys, ",")
    end
  ]] })
  test.contains(test.ipc("indicators"), "alarm")
end)

-- ---------------------------------------------------------------- the window --

local function window(style, name)
  local state = fresh(name)
  local appearance = state .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style, font = "" })
  test.load("../apps/clock/app.lua", { env = { XDG_STATE_HOME = state, EVA_DRY_RUN = "1", EVA_NOW = tostring(MONDAY),
    EVA_ALARM_ENGINE = "local", EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule",
    EVA_APPEARANCE = appearance } })
  test.settle(400)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("adds what is said, and lands on its page, in " .. style, function()
    window(style, "add-" .. style)
    test.click("clock-add")
    test.type("timer 5 min tea")
    test.settle(200)
    test.contains(test.get({ id = "clock-hint" }).text, "Timer 5 min · tea")
    test.key("Return")
    test.settle(400)
    test.eq(test.ipc("state").items[1].label, "tea")
    test.eq(test.get({ id = "clock-timer-label-1" }).text, "tea")
    test.eq(test.get({ id = "clock-timer-left-1" }).text, "5:00")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("runs a stopwatch and counts its laps", function()
  window("material", "watch")
  test.ipc("tab", "stopwatch")
  test.ipc("watch", "start")
  test.truthy(test.ipc("state").running)
  test.ipc("watch", "lap")
  test.ipc("watch", "lap")
  test.eq(#test.ipc("state").laps, 2)
  test.ipc("watch", "stop")
  test.falsy(test.ipc("state").running)
  test.ipc("watch", "reset")
  test.eq(#test.ipc("state").laps, 0)
  test.eq(test.ipc("state").elapsed, 0)
end)

test.it("adds a city by its name or its zone, and refuses neither", function()
  window("material", "world")
  test.truthy(test.ipc("city", "Tokyo"))
  test.truthy(test.ipc("city", "New York"))
  test.truthy(test.ipc("city", "Europe/Rome"))
  test.falsy(test.ipc("city", "Atlantis"))
  local world = test.ipc("state").world
  test.eq(#world, 3)
  test.eq(world[1].zone, "Asia/Tokyo")
  test.eq(world[2].zone, "America/New_York")
  test.settle(100)
  test.contains(test.get({ id = "clock-city-time-1" }).text, ":")
end)

-- ---------------------------------------------------------- the command line --

local function clock(args, env)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/clock-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"), "EVA_ALARM_SOUND=/sound.oga" }
  for _, word in ipairs(env or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/clock/cli"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or ""
end

test.it("plain words become a job", function()
  test.contains(clock { "timer", "12", "min", "pasta" }, "job/app.lua -- clock add timer 12 min pasta")
  test.contains(clock { "at", "6pm" }, "job/app.lua -- clock add at 6pm")
end)

test.it("rings through the notifications server, and Stop ends it", function()
  local calls = clock({ "fire", "abc", "Pasta" }, { "STUB_NOTIFY=stop" })
  test.contains(calls, "notify-send --app-name=eva --urgency=critical --category=alarm")
  test.contains(calls, "Pasta")
  test.contains(calls, "job/app.lua -- clock done abc")
end)

test.it("Snooze rings it again", function()
  local calls = clock({ "fire", "abc", "Pasta" }, { "STUB_NOTIFY=snooze" })
  test.contains(calls, "job/app.lua -- clock snooze abc")
end)

test.it("plays the sound while it rings", function()
  test.contains(clock({ "fire", "abc", "Pasta" }, { "STUB_NOTIFY=stop", "STUB_NOTIFY_WAIT=0.4" }), "pw-play /sound.oga")
end)
