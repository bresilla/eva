-- The notification store: what survives a restart, what never reaches the file.
--
--     morf test --no-dbus tests/notification_store_spec.lua
local test = morf.test

local HOST = [[
  local ui = require("morf.ui")
  morf.surface.height = 700
  package.loaded.services = { here = function() return true end, installed = function() return false end }
  package.loaded.bar = { desk = function() return 10, 10, 1080, 680 end }
  package.loaded["lib.services.notifications"] = { serve = function(options)
    local open = {}
    local function push() local list = {} for _, n in pairs(open) do list[#list + 1] = n end options.on_change(list) end
    morf.ipc.server = function(id, summary, transient)
      open[tonumber(id)] = { id = tonumber(id), app = "Server", summary = summary, body = "", urgency = 1,
        transient = transient == "transient", actions = {} }
      push()
    end
    return { open = function(id) return open[id] ~= nil end,
      dismiss = function(id) open[id] = nil push() end, expire = function(id) open[id] = nil push() end }
  end }
  local focus = require("focus_model")
  local clock = tonumber(morf.env("TEST_CLOCK") or morf.time.now())
  focus.now = function() return clock end
  local notifs = require("notifs")
  ui.Item { width = 1100, height = 700, ui.Item { visible = false, notifs.drawer.panel } }
  morf.ipc.push = function(summary, kind)
    return notifs.push { app = "App", summary = summary, body = "Body of " .. summary, transient = kind == "transient",
      urgency = kind == "critical" and 2 or 1, actions = kind == "buttons" and { { key = "a", label = "A" } } or nil }
  end
  morf.ipc.flush = function() notifs.flush() end
  morf.ipc.snooze = function(id, seconds) return notifs.snooze(tonumber(id), tonumber(seconds)) end
  morf.ipc.history = function() return notifs.history:get() end
  morf.ipc.snoozed = function() return notifs.snoozed:get() end
  morf.ipc.shown = function() return #notifs.shown() end
  morf.ipc.set = function(key, value) return require("config").set(key, morf.json.decode(value)) end
  morf.ipc.clock = function(by) clock = clock + tonumber(by) return clock end
]]

local serial, START = 0, math.floor(morf.time.now())
local function paths()
  serial = serial + 1
  local dir = morf.env("XDG_CACHE_HOME")
  return morf.fs.join(dir, "notification-store-" .. serial .. ".json"), morf.fs.join(dir, "notification-store-settings-" .. serial .. ".json")
end
local function load(store, settings, clock)
  test.load("../shell/init.lua", { source = HOST, size = { 1100, 700 },
    env = { EVA_NOTIFICATION_STORE = store, EVA_SETTINGS = settings, TEST_CLOCK = clock and tostring(clock) or nil } })
end
local function restart(store, settings, clock)
  test.ipc("flush")
  load(store, settings, clock)
  test.advance(50)
end

test.it("the history outlives a restart, and transient ones do not", function()
  local store, settings = paths()
  load(store, settings)
  test.ipc("push", "Kept") test.ipc("push", "Passing", "transient") test.ipc("push", "Also kept")
  test.advance(100)
  restart(store, settings)
  local list = test.ipc("history")
  test.eq(#list, 2)
  test.eq(list[1].summary, "Kept")
  test.eq(list[2].summary, "Also kept")
  test.eq(list[2].body, "Body of Also kept")
  test.eq(#test.logs("warn"), 0)
end)

test.it("a transient hint from the bus stays out of the file", function()
  local store, settings = paths()
  load(store, settings)
  test.ipc("server", "1", "On the bus", "transient")
  test.ipc("server", "2", "Kept from the bus")
  test.advance(100)
  restart(store, settings)
  local list = test.ipc("history")
  test.eq(#list, 1)
  test.eq(list[1].summary, "Kept from the bus")
end)

test.it("a restored record and a new id never collide", function()
  local store, settings = paths()
  load(store, settings)
  test.ipc("server", "1", "Before the restart") test.advance(100)
  restart(store, settings)
  test.ipc("server", "1", "After the restart") test.advance(100)
  local list = test.ipc("history")
  test.eq(#list, 2, "the new notification replaced the restored one")
  test.eq(list[1].summary, "Before the restart")
  test.eq(list[2].summary, "After the restart")
end)

test.it("a restored record has no buttons left to press", function()
  local store, settings = paths()
  load(store, settings)
  test.ipc("push", "Had buttons", "buttons") test.advance(100)
  restart(store, settings)
  test.eq(test.ipc("history")[1].actions, nil)
end)

test.it("the file holds no more than the cap", function()
  local store, settings = paths()
  load(store, settings)
  test.ipc("set", "notifications.history.limit", "5") test.advance(50)
  for i = 1, 9 do test.ipc("push", "Message " .. i) end
  test.advance(100)
  restart(store, settings)
  local list = test.ipc("history")
  test.eq(#list, 5)
  test.eq(list[1].summary, "Message 5")
  test.eq(list[5].summary, "Message 9")
end)

test.it("what is too old is gone after a restart", function()
  local store, settings = paths()
  load(store, settings, START)
  test.ipc("set", "notifications.history.days", "1") test.advance(50)
  test.ipc("push", "Old") test.advance(100)
  restart(store, settings, START + 2 * 86400)
  test.eq(#test.ipc("history"), 0)
end)

test.it("switching the history off keeps nothing, on disk either", function()
  local store, settings = paths()
  load(store, settings)
  test.ipc("push", "Before") test.advance(100)
  test.ipc("set", "notifications.history.enabled", "false") test.advance(100)
  test.ipc("push", "During") test.advance(100)
  test.eq(#test.ipc("history"), 0)
  restart(store, settings)
  test.eq(#test.ipc("history"), 0)
end)

test.it("a snooze outlives a restart and comes back on time", function()
  local store, settings = paths()
  load(store, settings, START)
  local id = test.ipc("push", "Snoozed", "critical") test.advance(100)
  test.truthy(test.ipc("snooze", tostring(id), "600")) test.advance(100)
  test.eq(#test.ipc("snoozed"), 1)
  restart(store, settings, START + 100)
  test.eq(#test.ipc("snoozed"), 1, "the snooze was lost")
  test.eq(test.ipc("shown"), 0)
  test.advance(495 * 1000)
  test.eq(#test.ipc("snoozed"), 1)
  test.advance(10 * 1000)
  test.eq(#test.ipc("snoozed"), 0, "it did not wake")
  test.eq(test.ipc("shown"), 1)
end)

test.it("a snooze that ran out while the shell was down wakes at once", function()
  local store, settings = paths()
  load(store, settings, START)
  local id = test.ipc("push", "Overdue", "critical") test.advance(100)
  test.ipc("snooze", tostring(id), "60") test.advance(100)
  restart(store, settings, START + 3600)
  test.advance(100)
  test.eq(#test.ipc("snoozed"), 0)
  test.eq(test.ipc("shown"), 1)
end)

test.it("a one-time code never reaches the disk", function()
  local store, settings = paths()
  load(store, settings)
  test.ipc("push", "Your code is 482913") test.advance(100)
  test.ipc("flush")
  local text = morf.fs.read(store)
  test.falsy(text:find("482913", 1, true), "the code is on the disk")
  test.eq(#test.ipc("history"), 1, "the running history lost it")
  test.contains(test.ipc("history")[1].summary, "482913")
  restart(store, settings)
  test.eq(test.ipc("history")[1].summary, "One-time code")
end)

test.it("a damaged file costs a warning, not the shell", function()
  local store, settings = paths()
  morf.fs.write(store, "{ this is not json")
  load(store, settings)
  test.advance(50)
  test.eq(#test.ipc("history"), 0)
  test.ipc("push", "Fine") test.advance(50)
  test.eq(#test.ipc("history"), 1)
  test.eq(#test.logs("error"), 0)
end)

test.it("nothing is written under test without a store named", function()
  test.load("../shell/init.lua", { source = HOST, size = { 1100, 700 },
    env = { EVA_SETTINGS = morf.fs.join(morf.env("XDG_CACHE_HOME"), "notification-store-none.json") } })
  test.ipc("push", "Nowhere") test.advance(1200)
  test.ipc("flush")
  test.falsy(morf.fs.exists(morf.paths.state("notifications.json")))
end)
