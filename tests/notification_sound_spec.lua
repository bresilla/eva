-- Notification sounds: off until asked for, and the ring mode decides. Requests
-- go to the EVA_FAKE_SOUND file: nothing is played here.
--
--     morf test --no-dbus tests/notification_sound_spec.lua
local test = morf.test

local HOST = [[
  local ui = require("morf.ui")
  morf.surface.height = 700
  local ring = { state = morf.state { mode = morf.env("TEST_RING") or "sound" } }
  package.loaded.services = { here = function() return true end, ringer = ring, installed = function() return false end }
  package.loaded.bar = { desk = function() return 10, 10, 1080, 680 end }
  package.loaded["lib.services.notifications"] = { serve = function() return { open = function() return false end } end }
  local notifs = require("notifs")
  local focus = require("focus_model")
  local rules = require("notification_rules")
  local config = require("config")
  ui.Item { width = 1100, height = 700, ui.Item { visible = false, notifs.drawer.panel } }
  morf.ipc.push = function(text) return notifs.push(morf.json.decode(text)) end
  morf.ipc.ring = function(mode) ring.state.mode = mode end
  morf.ipc.set = function(key, text) return config.set(key, morf.json.decode(text)) end
  morf.ipc.rule = function(app, field, text) return rules.set(app, field, morf.json.decode(text)) end
  morf.ipc.focus = function(id) return focus.start(id) end
  morf.ipc.event = function(urgency) return require("lib.services.notification_sound").event(tonumber(urgency)) end
]]

local serial = 0
local function load(ring)
  serial = serial + 1
  local dir = morf.env("XDG_CACHE_HOME")
  local log = morf.fs.join(dir, "notification-sound-" .. serial .. ".log")
  morf.fs.write(log, "")
  test.load("../shell/init.lua", { source = HOST, size = { 1100, 700 }, env = { EVA_FAKE_SOUND = log, TEST_RING = ring,
    EVA_SETTINGS = morf.fs.join(dir, "notification-sound-" .. serial .. ".json") } })
  return function()
    local out = {}
    for line in morf.fs.read(log):gmatch("[^\n]+") do out[#out + 1] = line end
    return out
  end
end
local function push(spec) return test.ipc("push", morf.json.encode(spec or { app = "App", summary = "S" })) end
local function on() test.ipc("set", "notifications.sounds", "true") test.advance(30) end

test.it("no sound until sounds are on", function()
  local heard = load()
  push() test.advance(50)
  test.eq(#heard(), 0)
  on()
  push() test.advance(50)
  test.eq(#heard(), 1)
  test.contains(heard()[1], "event=message-new-instant")
end)

test.it("the event follows the urgency, at the chosen volume", function()
  local heard = load()
  on()
  test.ipc("set", "notifications.volume", "35")
  push { app = "A", summary = "Critical", urgency = 2 } test.advance(50)
  push { app = "B", summary = "Low", urgency = 0 } test.advance(50)
  test.contains(heard()[1], "event=dialog-warning")
  test.contains(heard()[1], "volume=35")
  test.contains(heard()[2], "event=message-new-email")
end)

test.it("silent plays nothing; vibrate asks for it and leaves the rest to the player", function()
  local heard = load("silent")
  on()
  push() test.advance(50)
  test.eq(#heard(), 0, "the ring mode's silent made a noise")
  test.ipc("ring", "vibrate")
  push { app = "B", summary = "S" } test.advance(50)
  test.contains(heard()[1], "ring=vibrate")
end)

test.it("a rule can ring through silent, and turn one app off", function()
  local heard = load("silent")
  on()
  test.ipc("rule", "Alarm", "ring", "true")
  push { app = "Alarm", summary = "Wake" } test.advance(50)
  test.eq(#heard(), 1)
  test.ipc("ring", "sound")
  test.ipc("rule", "Noisy", "sound", '"off"')
  push { app = "Noisy", summary = "Hush" } test.advance(50)
  test.eq(#heard(), 1, "an app set to no sound made one")
end)

test.it("a rule's own sound plays even with sounds off", function()
  local heard = load()
  test.ipc("rule", "Pager", "sound", '"bell"')
  push { app = "Pager", summary = "S" } test.advance(50)
  test.contains(heard()[1], "event=bell")
end)

test.it("a sender's hints are honoured", function()
  local heard = load()
  on()
  push { app = "A", summary = "S", hints = { ["suppress-sound"] = true } } test.advance(50)
  test.eq(#heard(), 0)
  push { app = "B", summary = "S", hints = { ["sound-name"] = "phone-incoming-call" } } test.advance(50)
  test.contains(heard()[1], "event=phone-incoming-call")
  push { app = "C", summary = "S", hints = { ["sound-file"] = "/tmp/ding.oga" } } test.advance(50)
  test.contains(heard()[2], "file=/tmp/ding.oga")
end)

test.it("an app that keeps pinging falls quiet", function()
  local heard = load()
  on()
  for i = 1, 6 do push { app = "Chat", summary = "Ping " .. i } end
  test.advance(50)
  test.eq(#heard(), 3)
  test.ipc("set", "notifications.cooldown", "false")
  push { app = "Chat", summary = "Again" } test.advance(50)
  test.eq(#heard(), 4)
end)

test.it("what a Focus mode holds back makes no sound", function()
  local heard = load()
  on()
  test.ipc("focus", "work") test.advance(50)
  push { app = "Mail", summary = "Held" } test.advance(50)
  test.eq(#heard(), 0)
  push { app = "Pager", summary = "Through", urgency = 2 } test.advance(50)
  test.eq(#heard(), 1)
end)

test.it("a muted app is silent, and a muted rule reads aloud nothing", function()
  local heard = load()
  on()
  test.ipc("rule", "Chat", "mute", "true")
  test.ipc("rule", "Chat", "announce", "true")
  push { app = "Chat", summary = "S" } test.advance(50)
  test.eq(#heard(), 0)
end)

test.it("an announcing app says who it is", function()
  local heard = load()
  test.ipc("rule", "Chat", "announce", "true")
  push { app = "Chat", summary = "Ada wrote" } test.advance(50)
  test.eq(heard()[1], "say Chat. Ada wrote")
end)

test.it("the event table", function()
  load()
  test.eq(test.ipc("event", "0"), "message-new-email")
  test.eq(test.ipc("event", "1"), "message-new-instant")
  test.eq(test.ipc("event", "2"), "dialog-warning")
end)
