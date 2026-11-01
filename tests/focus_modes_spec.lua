-- Focus modes: what each lets through, when each comes on, what it changes, and
-- where it shows. The clock is the spec's: `morf.time.now` does not follow
-- test.advance.
--
--     morf test --no-dbus tests/focus_modes_spec.lua
local test = morf.test

local HOST = [[
  local ui = require("morf.ui")
  morf.surface.height = 750
  package.loaded.services = { here = function() return true end, installed = function() return false end }
  package.loaded.bar = { desk = function() return 10, 10, 1080, 730 end }
  package.loaded["lib.services.notifications"] = { serve = function() return { open = function() return false end } end }
  local focus = require("focus_model")
  -- Noon on a Monday in the test's zone, whatever the machine's date.
  local function noon()
    local now = morf.time.now()
    local days = (tonumber(morf.time.format("%u", now)) - 1)
    local seconds = tonumber(morf.time.format("%H", now)) * 3600 + tonumber(morf.time.format("%M", now)) * 60
      + tonumber(morf.time.format("%S", now))
    return math.floor(now - seconds - days * 86400 + 12 * 3600)
  end
  local clock = noon()
  focus.now = function() return clock end
  local notifs = require("notifs")
  local triggers = require("focus_triggers")
  local status = require("status_model")
  local config = require("config")
  local calls = {}
  for name, effect in pairs(triggers.EFFECTS) do
    local value = name == "ring" and "sound" or false
    triggers.EFFECTS[name] = { read = function() return value end,
      write = function(v) value = v calls[#calls + 1] = name .. "=" .. tostring(v) end }
  end
  local C = require("theme").color
  ui.Item { width = 1100, height = 750,
    ui.Item { x = 10, y = 10, width = 1080, height = 730,
      ui.Sdf { anchors = { fill = true }, fill_color = function() return C.surfaceContainer end, notifs.drawer.shape },
      notifs.drawer.panel } }
  local seen = { apps = {}, screens = 1, outputs = {}, charging = false, gamepad = false }
  morf.ipc.push = function(app, urgency, category, summary)
    return notifs.push { app = app, summary = summary or "Hello", urgency = tonumber(urgency) or 1, category = category }
  end
  morf.ipc.shown = function()
    local out = {}
    for _, n in ipairs(notifs.shown()) do out[#out + 1] = n.summary end
    return out
  end
  morf.ipc.history = function() return #notifs.history:get() end
  morf.ipc.dnd = function(on) notifs.dnd:set(on == "yes") end
  morf.ipc.is_dnd = function() return notifs.dnd:get() end
  morf.ipc.start = function(id, seconds) return focus.start(id, { seconds = tonumber(seconds) or 0 }) end
  morf.ipc.stop = focus.stop
  morf.ipc.toggle = function() return focus.toggle() end
  morf.ipc.active = focus.active_id
  morf.ipc.status = focus.status
  morf.ipc.reason = function() return focus.reason() end
  morf.ipc.set = function(id, field, text) return focus.set(id, field, morf.json.decode(text)) end
  morf.ipc.flip = function(id, field, text) return focus.flip(id, field, morf.json.decode(text)) end
  morf.ipc.add = function(name) return focus.add(name) end
  morf.ipc.remove = function(id) return focus.remove(id) end
  morf.ipc.modes = function() local out = {} for i, m in ipairs(focus.modes()) do out[i] = m.id end return out end
  morf.ipc.at = function(hours, day)
    clock = noon() + (tonumber(hours) - 12) * 3600 + (tonumber(day) or 0) * 86400
    focus.tick(seen)
    return morf.time.format("%u %H:%M", clock)
  end
  morf.ipc.see = function(key, text) seen[key] = morf.json.decode(text) focus.tick(seen) end
  morf.ipc.calls = function() return calls end
  morf.ipc.indicators = function()
    local keys = {}
    for _, row in ipairs(status.read({})) do keys[#keys + 1] = row.key .. ":" .. row.icon end
    return keys
  end
  morf.ipc.badge = function() return notifs.badge:get() end
  morf.ipc.config = function(key, text) return config.set(key, morf.json.decode(text)) end
  morf.ipc.settle = triggers.settle
  morf.ipc.auto = function() return focus.auto:get() end
  morf.ipc.stream = function(text) return triggers.screen_stream(text) end
  morf.ipc.sharing = function() return triggers.sharing() end
]]

local loads = 0
local function load(env)
  loads = loads + 1
  local all = { EVA_SETTINGS = morf.fs.join(morf.env("XDG_CACHE_HOME"), "focus-" .. loads .. ".json") }
  for key, value in pairs(env or {}) do all[key] = value end
  test.load("../shell/init.lua", { source = HOST, size = { 1100, 750 }, env = all })
end
local function json(value) return morf.json.encode(value) end
local function clean()
  test.eq(#test.logs("error"), 0)
  test.eq(#test.logs("warn"), 0)
end

test.it("the Do not disturb switch is the mode, both ways", function()
  load()
  test.ipc("dnd", "yes") test.advance(50)
  test.eq(test.ipc("active"), "dnd")
  test.ipc("stop") test.advance(50)
  test.falsy(test.ipc("is_dnd"))
  test.ipc("start", "dnd") test.advance(50)
  test.truthy(test.ipc("is_dnd"))
  test.ipc("start", "work") test.advance(50)
  test.falsy(test.ipc("is_dnd"), "a named mode is not Do not disturb")
  clean()
end)

test.it("a mode holds back the ordinary and lets the critical through", function()
  load()
  test.ipc("start", "work") test.advance(50)
  test.ipc("push", "Mail", "1", "", "Ordinary") test.advance(600)
  test.eq(test.ipc("shown"), {})
  test.ipc("push", "Pager", "2", "", "Urgent") test.advance(600)
  test.eq(test.ipc("shown"), { "Urgent" })
  test.eq(test.ipc("history"), 2, "what was held back left the history")
  clean()
end)

test.it("a mode's urgency floor decides, up to nothing at all", function()
  load()
  test.ipc("set", "work", "allow.urgency", "1")
  test.ipc("start", "work") test.advance(50)
  test.ipc("push", "Quiet", "0", "", "Low") test.advance(300)
  test.eq(test.ipc("shown"), {})
  test.ipc("push", "Mail", "1", "", "Normal") test.advance(300)
  test.eq(test.ipc("shown"), { "Normal" })
  test.ipc("set", "work", "allow.urgency", "3")
  test.ipc("push", "Pager", "2", "", "Critical") test.advance(300)
  test.eq(test.ipc("shown"), { "Normal" }, "a floor of nothing let a critical through")
  clean()
end)

test.it("allowed apps come through, and only those", function()
  load()
  test.ipc("flip", "work", "allow.apps", json "Slack")
  test.ipc("start", "work") test.advance(50)
  test.ipc("push", "Slack", "1", "", "Allowed") test.advance(300)
  test.ipc("push", "Mail", "1", "", "Not") test.advance(300)
  test.eq(test.ipc("shown"), { "Allowed" })
  clean()
end)

test.it("allowed people come through by name", function()
  load()
  test.ipc("set", "work", "allow.people", json { "Ada" })
  test.ipc("start", "work") test.advance(50)
  test.ipc("push", "Chat", "1", "im", "Ada Lovelace") test.advance(300)
  test.ipc("push", "Chat2", "1", "im", "Someone else") test.advance(300)
  test.eq(test.ipc("shown"), { "Ada Lovelace" })
  clean()
end)

test.it("an alarm passes, and a second call within minutes rings", function()
  load()
  test.ipc("set", "sleep", "allow.calls", "false")
  test.ipc("start", "sleep") test.advance(50)
  test.ipc("push", "Clock", "1", "x-alarm", "Wake up") test.advance(300)
  test.eq(test.ipc("shown"), { "Wake up" })
  test.ipc("push", "Phone", "1", "call.incoming", "Ada") test.advance(300)
  test.eq(test.ipc("shown"), { "Wake up" }, "a first call rang through")
  test.ipc("push", "Phone", "1", "call.incoming", "Ada") test.advance(300)
  test.eq(#test.ipc("shown"), 2, "a repeat call stayed silent")
  clean()
end)

test.it("a session runs out and says so", function()
  load()
  test.ipc("start", "work", "1800") test.advance(50)
  test.ipc("at", "12") test.eq(test.ipc("active"), "work")
  test.contains(test.ipc("status"), "until")
  test.ipc("at", "13") test.advance(50)
  test.eq(test.ipc("active"), "")
  test.eq(test.ipc("shown"), { "Work finished" })
  clean()
end)

test.it("what was held back is told once, after", function()
  load()
  test.ipc("start", "work") test.advance(50)
  test.ipc("push", "A", "1", "", "One") test.ipc("push", "B", "1", "", "Two") test.advance(300)
  test.ipc("stop") test.advance(600)
  test.eq(test.ipc("shown"), { "You missed 2 notifications" })
  clean()
end)

test.it("turning a mode on takes what is on show that it would hold back", function()
  load()
  test.ipc("push", "Mail", "1", "", "Ordinary") test.ipc("push", "Pager", "2", "", "Urgent") test.advance(300)
  test.eq(#test.ipc("shown"), 2)
  test.ipc("start", "work") test.advance(50)
  test.eq(test.ipc("shown"), { "Urgent" }, "an ordinary card stayed through Focus")
  test.eq(test.ipc("history"), 2)
  clean()
end)

test.it("a schedule turns on and off by the clock", function()
  load()
  test.ipc("set", "work", "schedule.on", "true")
  test.eq(test.ipc("at", "8"):sub(1, 1), "1")
  test.eq(test.ipc("active"), "")
  test.ipc("at", "9") test.eq(test.ipc("active"), "work")
  test.ipc("at", "16.9") test.eq(test.ipc("active"), "work")
  test.ipc("at", "17") test.eq(test.ipc("active"), "")
  clean()
end)

test.it("a schedule keeps to its days", function()
  load()
  test.ipc("set", "work", "schedule.on", "true")
  test.ipc("at", "10", "5") test.eq(test.ipc("active"), "", "Work ran on a Saturday")
  clean()
end)

test.it("a window past midnight belongs to the day it opened", function()
  load()
  test.ipc("set", "sleep", "schedule.days", json { 1 })
  test.ipc("set", "sleep", "schedule.on", "true")
  test.ipc("at", "23.5") test.eq(test.ipc("active"), "sleep", "Monday night")
  test.ipc("at", "6", "1") test.eq(test.ipc("active"), "sleep", "the small hours of Tuesday")
  test.ipc("at", "8", "1") test.eq(test.ipc("active"), "")
  test.ipc("at", "23.5", "1") test.eq(test.ipc("active"), "", "Tuesday night is not on the list")
  clean()
end)

test.it("turned off by hand, a window stays off until the next one", function()
  load()
  test.ipc("set", "work", "schedule.on", "true")
  test.ipc("at", "10") test.eq(test.ipc("active"), "work")
  test.ipc("stop") test.ipc("at", "11")
  test.eq(test.ipc("active"), "", "the schedule took it straight back")
  test.ipc("at", "10", "1") test.eq(test.ipc("active"), "work", "the next day's window did not open")
  clean()
end)

test.it("pausing a schedule keeps it without using it", function()
  load()
  test.ipc("set", "work", "schedule.on", "true")
  test.ipc("set", "work", "schedule.paused", "true")
  test.ipc("at", "10") test.eq(test.ipc("active"), "")
  clean()
end)

test.it("a schedule can wait for the charger", function()
  load()
  test.ipc("set", "sleep", "schedule.on", "true")
  test.ipc("set", "sleep", "schedule.charging", "true")
  test.ipc("at", "23.5") test.eq(test.ipc("active"), "")
  test.ipc("see", "charging", "true") test.eq(test.ipc("active"), "sleep")
  test.ipc("see", "charging", "false") test.eq(test.ipc("active"), "")
  clean()
end)

test.it("a mode comes on with an app, and goes with it", function()
  load()
  test.ipc("set", "gaming", "triggers.apps", json { "steam" })
  test.ipc("see", "apps", json { steam = true }) test.eq(test.ipc("active"), "gaming")
  test.ipc("see", "apps", json { firefox = true }) test.eq(test.ipc("active"), "")
  clean()
end)

test.it("a mode comes on with a second screen and with a controller", function()
  load()
  test.ipc("set", "work", "triggers.display", json "any")
  test.ipc("see", "screens", "2") test.eq(test.ipc("active"), "work")
  test.ipc("see", "screens", "1") test.eq(test.ipc("active"), "")
  test.ipc("set", "gaming", "triggers.gamepad", "true")
  test.ipc("see", "gamepad", "true") test.eq(test.ipc("active"), "gaming")
  clean()
end)

test.it("a mode turned on by hand is not taken away by its triggers", function()
  load()
  test.ipc("set", "gaming", "triggers.apps", json { "steam" })
  test.ipc("start", "gaming") test.ipc("see", "apps", json { firefox = true })
  test.eq(test.ipc("active"), "gaming")
  clean()
end)

test.it("a mode changes things, and puts them back as they were", function()
  load()
  test.ipc("start", "sleep") test.advance(50)
  local calls = test.ipc("calls")
  test.contains(calls, "night=true")
  test.contains(calls, "dark=true")
  test.contains(calls, "ring=silent")
  test.ipc("stop") test.advance(50)
  calls = test.ipc("calls")
  test.contains(calls, "night=false")
  test.contains(calls, "ring=sound", "the ring mode did not come back")
  clean()
end)

test.it("moving from mode to mode undoes the first", function()
  load()
  test.ipc("start", "sleep") test.advance(50)
  test.ipc("start", "gaming") test.advance(50)
  local calls = test.ipc("calls")
  test.contains(calls, "ring=sound")
  test.contains(calls, "awake=true")
  clean()
end)

test.it("named modes can be made, up to ten, and removed; Do not disturb stays", function()
  load()
  local id = test.ipc("add", "Deep work")
  test.eq(id, "deep-work")
  test.eq(test.ipc("add", "Deep work"), "deep-work-2")
  test.contains(test.ipc("modes"), "deep-work")
  test.truthy(test.ipc("remove", "deep-work"))
  test.falsy(test.ipc("remove", "dnd"))
  for i = 1, 8 do test.ipc("add", "Mode " .. i) end
  test.eq(#test.ipc("modes"), 10)
  clean()
end)

test.it("removing the mode on turns it off", function()
  load()
  test.ipc("add", "Temp") test.ipc("start", "temp") test.advance(20)
  test.ipc("remove", "temp") test.advance(20)
  test.eq(test.ipc("active"), "")
  clean()
end)

test.it("the toggle brings back the mode last chosen", function()
  load()
  test.ipc("start", "work") test.advance(20)
  test.ipc("toggle") test.eq(test.ipc("active"), "")
  test.ipc("toggle") test.eq(test.ipc("active"), "work")
  clean()
end)

test.it("a named mode has its own status indicator; Do not disturb keeps its own", function()
  load()
  test.ipc("start", "work") test.advance(50)
  test.contains(test.ipc("indicators"), "focus:work")
  test.ipc("start", "dnd") test.advance(50)
  local shown = test.ipc("indicators")
  test.contains(shown, "dnd:do_not_disturb_on")
  for _, row in ipairs(shown) do test.falsy(row:match("^focus"), "two indicators for one thing") end
  clean()
end)

test.it("a mode can hide the badges", function()
  load()
  test.ipc("push", "A") test.advance(100)
  test.falsy(test.ipc("badge").hidden)
  test.ipc("start", "sleep") test.advance(100)
  test.truthy(test.ipc("badge").hidden)
  test.ipc("stop") test.advance(100)
  test.falsy(test.ipc("badge").hidden)
  clean()
end)

test.it("sharing the screen quiets the shell when asked to", function()
  load { EVA_FAKE_FOCUS = "sharing" }
  test.ipc("settle") test.advance(50)
  test.eq(test.ipc("auto"), "sharing")
  test.eq(test.ipc("reason"), "Sharing the screen")
  test.ipc("push", "Mail", "1", "", "Private") test.advance(300)
  test.eq(test.ipc("shown"), {})
  test.ipc("config", "focus.sharing", "false") test.ipc("settle") test.advance(50)
  test.eq(test.ipc("auto"), "")
  clean()
end)

test.it("fullscreen quiets only when asked to", function()
  load { EVA_FAKE_FOCUS = "fullscreen" }
  test.ipc("settle") test.advance(50)
  test.eq(test.ipc("auto"), "", "fullscreen quiets by default")
  test.ipc("config", "focus.fullscreen", "true") test.ipc("settle") test.advance(50)
  test.eq(test.ipc("auto"), "fullscreen")
  clean()
end)

test.it("a running screen capture is told from the rest of PipeWire", function()
  load()
  test.truthy(test.ipc("stream", json { { info = { state = "running", props = { ["media.class"] = "Stream/Input/Video" } } } }))
  test.truthy(test.ipc("stream", json { { info = { state = "running",
    props = { ["media.class"] = "Video/Source", ["node.name"] = "xdph-streaming-0" } } } }))
  test.falsy(test.ipc("stream", json { { info = { state = "suspended", props = { ["media.class"] = "Stream/Input/Video" } } } }))
  test.falsy(test.ipc("stream", json { { info = { state = "running",
    props = { ["media.class"] = "Video/Source", ["node.name"] = "v4l2_input.pci-0000" } } } }), "a camera is not a share")
  test.falsy(test.ipc("stream", "not json"))
  clean()
end)

test.it("the mode on outlives a restart", function()
  local settings = morf.fs.join(morf.env("XDG_CACHE_HOME"), "focus-restart.json")
  morf.fs.write(settings, json { focus = { active = "work", source = "manual" } })
  load { EVA_SETTINGS = settings }
  test.advance(50)
  test.eq(test.ipc("active"), "work")
  test.ipc("push", "Mail", "1", "", "Held") test.advance(300)
  test.eq(test.ipc("shown"), {})
  clean()
end)
