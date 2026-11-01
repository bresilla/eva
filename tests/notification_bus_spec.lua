-- The notification server as a sender meets it: morf's library and eva's seam on
-- a recording stand-in for the bus. tools/see/notify-bus.steps runs the same
-- paths on a real session bus.
--
--     morf test --no-dbus tests/notification_bus_spec.lua
local test = morf.test

local HOST = [[
  local ui = require("morf.ui")
  local W, H = tonumber(morf.env("TEST_WIDTH")), tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height = H
  package.loaded.services = { here = function() return true end, ringer = nil,
    installed = function() return false end }
  package.loaded.bar = { desk = function() return 10, 10, W - 20, H - 20 end }

  -- The bus: calls in through `handler`, what the server says kept in `sent`.
  local handler, sent, replies, serial = nil, {}, {}, 0
  local service = {}
  function service:on_call(fn) handler = fn end
  function service:reply(id, value) replies[id] = value end
  function service:reply_error(id, name) replies[id] = { error = name } end
  function service:emit(_, _, member, args)
    local plain = {}
    for i, value in ipairs(args) do plain[i] = type(value) == "table" and value.value or value end
    sent[#sent + 1] = { member = member, args = plain }
  end
  function service:close() end
  morf.dbus.serve = function() return service, "owned" end
  local function call(member, arguments)
    serial = serial + 1
    handler { member = member, id = serial, arguments = arguments }
    return replies[serial]
  end
  local function notify(spec)
    local actions = {}
    for _, word in ipairs(spec.actions or {}) do actions[#actions + 1] = word end
    local answer = call("Notify", { spec.app or "App", spec.replaces or 0, spec.icon or "", spec.summary or "S",
      spec.body or "", actions, spec.hints or {}, spec.timeout or -1 })
    return answer.value
  end

  local notifs = require("notifs")
  local history = require("notification_history")
  local rules = require("notification_rules")
  local config = require("config")
  local focus = require("focus_model")
  local clock = 1790000000
  focus.now = function() return clock end
  local C = require("theme").color
  local page = history.build(W - 40, function() return H - 40 end)
  local presentation = require("presentation")
  local shown_page = morf.signal("test.page", false)
  ui.Item { width = W, height = H,
    ui.Rect { width = W, height = H, color = function() return C.surface end },
    ui.Item { x = 10, y = 10, width = W - 20, height = H - 20,
      ui.Sdf { anchors = { fill = true }, fill_color = function() return C.surfaceContainer end, notifs.drawer.shape },
      notifs.drawer.panel },
    ui.Item { x = 20, y = 20, width = W - 40, height = H - 40, visible = function() return shown_page:get() end, page },
  }
  morf.ipc.notify = function(text) return notify(morf.json.decode(text)) end
  morf.ipc.close = function(id) return call("CloseNotification", { tonumber(id) }) ~= nil end
  morf.ipc.inhibit = function() return call("Inhibit", { "app", "why", {} }).value end
  morf.ipc.uninhibit = function(cookie) call("UnInhibit", { tonumber(cookie) }) return true end
  morf.ipc.caps = function() return call("GetCapabilities", {}).value end
  morf.ipc.sent = function() return sent end
  morf.ipc.state = function()
    local ids, summaries = {}, {}
    for _, n in ipairs(notifs.shown()) do ids[#ids + 1] = n.id summaries[#summaries + 1] = n.summary end
    return { ids = ids, summaries = summaries, history = notifs.history:get(), snoozed = notifs.snoozed:get(),
      dismissed = notifs.dismissed:get(), undo = notifs.undo:get(), badge = notifs.badge:get(),
      answers = notifs.answers:get(), open = notifs.drawer.open:get(), status = notifs.status() }
  end
  morf.ipc.invoke = function(id, key) return notifs.invoke(tonumber(id), key) end
  morf.ipc.reply = function(id, text) return notifs.reply(tonumber(id), text) end
  morf.ipc.dismiss = function(id) notifs.dismiss(tonumber(id)) end
  morf.ipc.forget = function(id) notifs.forget(tonumber(id)) end
  morf.ipc.clear = function() return notifs.clear() end
  morf.ipc.clear_app = function(key) return notifs.clear_app(key) end
  morf.ipc.clear_silent = function() return notifs.clear_silent() end
  morf.ipc.restore = function() return notifs.restore() end
  morf.ipc.bring_back = function(id) return notifs.bring_back(tonumber(id)) end
  morf.ipc.snooze = function(id, value) return notifs.snooze(tonumber(id), tonumber(value) or value) end
  morf.ipc.wake = function(id) notifs.wake(tonumber(id)) end
  morf.ipc.read = function() notifs.read() end
  morf.ipc.flush = function() notifs.flush() end
  morf.ipc.rule = function(app, field, text) return rules.set(app, field, morf.json.decode(text)) end
  morf.ipc.mute = function(app, seconds) rules.mute(app, tonumber(seconds), clock) end
  morf.ipc.set = function(key, text) return config.set(key, morf.json.decode(text)) end
  morf.ipc.rules_apps = function() return rules.apps() end
  morf.ipc.clock = function(seconds) clock = clock + tonumber(seconds) return clock end
  morf.ipc.show_page = function(on)
    shown_page:set(on == "yes")
    presentation.set("sidebar.notifications", on == "yes")
    notifs.covered:set(on == "yes")
  end
]]

local loads = 0
local function load(style, env)
  loads = loads + 1
  local all = { EVA_STYLE = style or "material", TEST_WIDTH = "1100", TEST_HEIGHT = "750",
    EVA_SETTINGS = morf.fs.join(morf.env("XDG_CACHE_HOME"), "notification-bus-" .. loads .. ".json") }
  for key, value in pairs(env or {}) do all[key] = value end
  test.load("../shell/init.lua", { source = HOST, size = { 1100, 750 }, env = all })
end
local function json(value) return morf.json.encode(value) end
local function notify(spec) return test.ipc("notify", json(spec)) end
local function state() return test.ipc("state") end
local function member(name)
  for _, entry in ipairs(test.ipc("sent")) do
    if entry.member == name then return entry end
  end
end
local function clean()
  test.eq(#test.logs("error"), 0)
  test.eq(#test.logs("warn"), 0, "warnings")
end

test.it("a press reaches the sender as ActionInvoked, then closes", function()
  load()
  local id = notify { app = "Mail", summary = "New mail", actions = { "default", "Open", "archive", "Archive" } }
  test.advance(600)
  test.eq(test.get("notification-action-1-1-box").visible, true, "the Archive button is not drawn")
  test.click("notification-action-1-1") test.advance(300)
  local action = member("ActionInvoked")
  test.truthy(action, "the sender heard nothing")
  test.eq(action.args, { id, "archive" })
  test.eq(member("NotificationClosed").args, { id, 2 })
  clean()
end)

test.it("a press on the body runs the default action and only that", function()
  load()
  local id = notify { summary = "Open me", actions = { "default", "Open" } }
  test.advance(600)
  test.click("notification-1") test.advance(300)
  test.eq(member("ActionInvoked").args, { id, "default" })
  clean()
end)

test.it("a body with no default action dismisses, as it always has", function()
  load()
  local id = notify { summary = "Plain" }
  test.advance(600)
  test.click("notification-1") test.advance(600)
  test.falsy(member("ActionInvoked"))
  test.eq(member("NotificationClosed").args, { id, 2 })
  clean()
end)

test.it("a resident notification stays after its button", function()
  load()
  local id = notify { summary = "Playing", actions = { "skip", "Skip" }, hints = { resident = true } }
  test.advance(600)
  test.ipc("invoke", tostring(id), "skip") test.advance(100)
  test.truthy(member("ActionInvoked"))
  test.falsy(member("NotificationClosed"))
  test.eq(state().ids, { id })
  clean()
end)

test.it("the reply field sends NotificationReplied", function()
  load()
  local id = notify { summary = "Ada", body = "Lunch?", actions = { "inline-reply", "Reply" }, hints = { category = "im.received" } }
  test.advance(600)
  test.click("notification-action-1-1") test.advance(100)
  test.truthy(test.find { id = "notification-reply-1", visible = true }, "no reply field")
  test.click("notification-reply-1") test.advance(50)
  test.type("Yes, noon") test.advance(50)
  test.key("Return") test.advance(100)
  local reply = member("NotificationReplied")
  test.truthy(reply, "the sender heard no reply")
  test.eq(reply.args, { id, "Yes, noon" })
  test.eq(member("NotificationClosed").args, { id, 2 })
  clean()
end)

test.it("Escape takes the reply field away and sends nothing", function()
  load()
  notify { summary = "Ada", actions = { "inline-reply", "Reply" } }
  test.advance(600)
  test.click("notification-action-1-1") test.advance(100)
  test.click("notification-reply-1") test.advance(50)
  test.type("no") test.key("Escape") test.advance(100)
  test.falsy(member("NotificationReplied"))
  test.falsy(test.find { id = "notification-reply-1", visible = true })
  clean()
end)

test.it("GetCapabilities tells what is drawn, and sound only when sounds are on", function()
  load()
  local caps = test.ipc("caps")
  for _, word in ipairs { "actions", "body-markup", "body-hyperlinks", "icon-static", "inline-reply", "persistence" } do
    test.contains(caps, word)
  end
  for _, word in ipairs(caps) do test.ne(word, "sound") end
  test.ipc("set", "notifications.sounds", "true") test.advance(50)
  test.contains(test.ipc("caps"), "sound")
  clean()
end)

test.it("Inhibit quiets popups until the last cookie goes", function()
  load()
  local one, two = test.ipc("inhibit"), test.ipc("inhibit")
  test.advance(50)
  test.truthy(state().status.quiet)
  notify { summary = "Held back" } test.advance(600)
  test.eq(#state().ids, 0)
  test.eq(#state().history, 1)
  test.ipc("uninhibit", tostring(one)) test.advance(50)
  test.truthy(state().status.quiet)
  test.ipc("uninhibit", tostring(two)) test.advance(50)
  test.falsy(state().status.quiet)
  clean()
end)

test.it("the newest stands first, whichever way it arrived", function()
  load()
  local one = notify { app = "One", summary = "First" }
  local two = notify { app = "Two", summary = "Second" }
  test.advance(600)
  test.eq(state().ids, { two, one })
  clean()
end)

test.it("a replacement updates its card and history in place", function()
  load()
  local id = notify { app = "Files", summary = "Copying", hints = { value = 10 } }
  notify { app = "Other", summary = "Between" }
  test.advance(400)
  notify { app = "Files", summary = "Copying", replaces = id, hints = { value = 70 }, body = "Almost" }
  test.advance(400)
  local list = state().history
  test.eq(#list, 2, "a replacement made a second record")
  test.eq(list[1].id, id)
  test.eq(list[1].hints.value, 70)
  test.eq(list[1].body, "Almost")
  clean()
end)

test.it("a job reports how long is left once it has moved", function()
  load()
  local id = notify { app = "Files", summary = "Copying", hints = { value = 10 } }
  test.advance(100)
  test.ipc("clock", "10")
  notify { app = "Files", summary = "Copying", replaces = id, hints = { value = 20 } }
  test.advance(600)
  test.contains(test.text_of(test.get("notification-1")), "1 min left")
  clean()
end)

test.it("buttons outlive the popup and go quiet when the sender does", function()
  load()
  local id = notify { summary = "Later", actions = { "default", "Open", "act", "Act" } }
  test.advance(600)
  test.eq(state().ids, { id })
  test.advance(5400)
  test.eq(#state().ids, 0, "the popup outstayed its time")
  test.falsy(member("NotificationClosed"), "it closed while its buttons were wanted")
  test.truthy(state().answers[tostring(id)])
  test.ipc("invoke", tostring(id), "act") test.advance(100)
  test.eq(member("ActionInvoked").args, { id, "act" })
  clean()
end)

test.it("a sender that set its own time expires on it, buttons or none", function()
  load()
  local id = notify { summary = "Timed", timeout = 2000, actions = { "act", "Act" } }
  test.advance(2200)
  test.eq(member("NotificationClosed").args, { id, 1 })
  clean()
end)

test.it("a kept notification closes when its keep is over", function()
  load(nil, nil)
  test.ipc("set", "notifications.keep_actions", "9000")
  local id = notify { summary = "Later", actions = { "act", "Act" } }
  test.advance(5200)
  test.falsy(member("NotificationClosed"))
  test.advance(9200)
  test.eq(member("NotificationClosed").args, { id, 1 })
  clean()
end)

test.it("CloseNotification keeps the record, without its buttons", function()
  load()
  local id = notify { summary = "Recalled", actions = { "act", "Act" } }
  test.advance(300)
  test.ipc("close", tostring(id)) test.advance(100)
  test.eq(#state().history, 1)
  test.falsy(state().answers[tostring(id)])
  test.eq(member("NotificationClosed").args, { id, 3 })
  clean()
end)

test.it("hovering holds a popup and leaving lets it go", function()
  load()
  notify { summary = "Stay" }
  test.advance(600)
  local card = test.get("notification-1")
  test.move(card.x + 40, card.y + 40) test.advance(50)
  test.advance(9000)
  test.eq(#state().ids, 1, "it expired under the pointer")
  test.leave() test.advance(100)
  test.advance(5200)
  test.eq(#state().ids, 0, "it never went after the pointer left")
  clean()
end)

test.it("a third card from one app folds, and opens out", function()
  load()
  for i = 1, 3 do notify { app = "Chat", summary = "Message " .. i } end
  notify { app = "Other", summary = "Else" }
  test.advance(600)
  test.eq(state().summaries, { "Else", "Message 3" })
  test.truthy(test.find { id = "notification-fold-2", visible = true })
  test.click("notification-fold-2") test.advance(100)
  test.eq(state().summaries, { "Else", "Message 3", "Message 2", "Message 1" })
  clean()
end)

test.it("dismissing a folded card takes its whole stack", function()
  load()
  for i = 1, 3 do notify { app = "Chat", summary = "Message " .. i, urgency = 2, hints = { urgency = 2 } } end
  test.advance(600)
  test.eq(#state().ids, 1)
  test.click("notification-1") test.advance(800)
  test.eq(#state().ids, 0)
  clean()
end)

test.it("a right click and a long press open the tools", function()
  load()
  notify { summary = "Tools", hints = { urgency = 2 } }
  test.advance(600)
  local card = test.get("notification-1")
  local x, y = card.x + 200, card.y + 30
  test.click(x, y, { button = "right" }) test.advance(100)
  test.truthy(test.find { id = "notification-tool-1-1", visible = true }, "a right click did nothing")
  test.click(x, y, { button = "right" }) test.advance(100)
  test.falsy(test.find { id = "notification-tool-1-1", visible = true })
  test.move(x, y) test.press(x, y) test.advance(700) test.release(x, y) test.advance(100)
  test.truthy(test.find { id = "notification-tool-1-1", visible = true }, "a long press did nothing")
  test.eq(#state().ids, 1, "the long press also dismissed it")
  clean()
end)

test.it("the card's tools snooze, and it comes back", function()
  load()
  local id = notify { summary = "Later please", hints = { urgency = 2 } }
  test.advance(600)
  test.click("notification-tools-1") test.advance(100)
  test.click("notification-tool-1-1") test.advance(50)
  test.click("notification-tool-1-1") test.advance(100)
  test.eq(#state().ids, 0, "snoozing left the popup")
  test.eq(#state().snoozed, 1)
  test.eq(#state().history, 0)
  test.advance(900 * 1000 + 500)
  test.eq(#state().snoozed, 0, "it did not wake")
  test.eq(#state().ids, 1, "it came back without a popup")
  test.eq(#state().history, 1)
  test.eq(state().history[1].summary, "Later please")
  test.eq(member("NotificationClosed").args, { id, 1 }, "a snoozed card with no buttons has nothing to keep open")
  clean()
end)

test.it("waking early brings it straight back", function()
  load()
  local id = notify { summary = "Sooner", actions = { "act", "Act" } }
  test.advance(300)
  test.ipc("snooze", tostring(id), "3600") test.advance(100)
  test.eq(#state().ids, 0)
  test.ipc("wake", tostring(id)) test.advance(100)
  test.eq(state().ids, { id }, "the live notification did not return")
  clean()
end)

test.it("clearing can be taken back, buttons and all", function()
  load()
  local id = notify { app = "One", summary = "Keep me", actions = { "act", "Act" } }
  notify { app = "Two", summary = "Me too" }
  test.advance(300)
  test.ipc("clear") test.advance(100)
  test.eq(#state().history, 0)
  test.eq(state().undo.count, 2)
  test.falsy(member("NotificationClosed"), "the sender was told before the undo lapsed")
  test.truthy(test.ipc("restore")) test.advance(100)
  test.eq(#state().history, 2)
  test.falsy(state().undo)
  test.truthy(state().answers[tostring(id)])
  test.ipc("invoke", tostring(id), "act") test.advance(100)
  test.truthy(member("ActionInvoked"), "the restored button does not work")
  clean()
end)

test.it("an undo lapses, and then the senders hear", function()
  load()
  local id = notify { summary = "Going" }
  test.advance(300)
  test.ipc("clear") test.advance(8200)
  test.falsy(state().undo)
  test.eq(member("NotificationClosed").args, { id, 2 })
  test.falsy(test.ipc("restore"))
  clean()
end)

test.it("Clear app takes one sender and leaves the rest", function()
  load()
  notify { app = "One", summary = "A" } notify { app = "One", summary = "B" } notify { app = "Two", summary = "C" }
  test.advance(300)
  test.eq(test.ipc("clear_app", "One"), 2)
  test.eq(#state().history, 1)
  test.eq(state().history[1].app, "Two")
  test.eq(state().undo.label, "Cleared One")
  clean()
end)

test.it("Clear silent leaves what asked for attention", function()
  load()
  notify { app = "Quiet", summary = "Low", hints = { urgency = 0 } }
  notify { app = "Loud", summary = "Normal" }
  test.advance(300)
  test.eq(test.ipc("clear_silent"), 1)
  test.eq(#state().history, 1)
  test.eq(state().history[1].app, "Loud")
  clean()
end)

test.it("what still runs survives Clear all", function()
  load()
  notify { app = "Music", summary = "Playing", hints = { resident = true } }
  notify { app = "Files", summary = "Copying", hints = { value = 40 } }
  notify { app = "Mail", summary = "Done" }
  test.advance(300)
  test.eq(test.ipc("clear"), 1)
  test.eq(#state().history, 2)
  clean()
end)

test.it("a dismissed entry can be brought back", function()
  load()
  local id = notify { summary = "Oops" }
  test.advance(300)
  test.ipc("forget", tostring(id)) test.advance(50)
  test.eq(#state().dismissed, 1)
  test.ipc("clock", "1")
  test.truthy(test.ipc("bring_back", tostring(id)))
  test.eq(#state().history, 1)
  test.eq(#state().dismissed, 0)
  clean()
end)

test.it("the badge counts, and reading empties it", function()
  load()
  notify { app = "One", summary = "A" }
  notify { app = "One", summary = "B", hints = { urgency = 2 } }
  notify { app = "Two", summary = "C", hints = { urgency = 0 } }
  test.advance(200)
  local badge = state().badge
  test.eq(badge.count, 3)
  test.eq(badge.unread, 3)
  test.eq(badge.critical, 1)
  test.eq(badge.apps.One, 2)
  test.eq(#badge.icons, 1, "a silent app stands in the status icons")
  test.eq(badge.icons[1].key, "One")
  test.ipc("clock", "5") test.ipc("read") test.advance(100)
  test.eq(state().badge.unread, 0)
  test.eq(state().badge.count, 3)
  clean()
end)

test.it("rules: muted, unseen, and in the history", function()
  load()
  test.ipc("rule", "Chat", "mute", "true")
  notify { app = "Chat", summary = "Muted" } test.advance(600)
  test.eq(#state().ids, 0)
  test.eq(#state().history, 1)
  clean()
end)

test.it("rules: a timed mute runs out", function()
  load()
  test.ipc("mute", "Chat", "3600")
  notify { app = "Chat", summary = "Muted" } test.advance(300)
  test.eq(#state().ids, 0)
  test.ipc("clock", "3601")
  notify { app = "Chat", summary = "Heard" } test.advance(300)
  test.eq(#state().ids, 1)
  clean()
end)

test.it("rules: no popup, and nothing kept", function()
  load()
  test.ipc("rule", "Bar", "popup", "false")
  test.ipc("rule", "Gone", "history", "false")
  notify { app = "Bar", summary = "Quiet" } test.advance(300)
  test.eq(#state().ids, 0)
  test.eq(#state().history, 1)
  notify { app = "Gone", summary = "Passing" } test.advance(300)
  test.eq(#state().ids, 1)
  test.eq(#state().history, 1)
  clean()
end)

test.it("rules: an urgency override changes how long it stays", function()
  load()
  test.ipc("rule", "Pager", "urgency", "2")
  notify { app = "Pager", summary = "Up" } test.advance(9000)
  test.eq(#state().ids, 1, "an app raised to critical expired")
  clean()
end)

test.it("rules: match by desktop entry, and an app's own timeout", function()
  load()
  test.ipc("rule", "org.example.Chat", "timeout", "1000")
  notify { app = "Chat", summary = "Short", hints = { ["desktop-entry"] = "org.example.Chat" } }
  test.advance(600)
  test.eq(#state().ids, 1)
  test.advance(700)
  test.eq(#state().ids, 0)
  clean()
end)

test.it("rules: buttons hidden whole or one by one", function()
  load()
  test.ipc("rule", "A", "hidden_actions", json { "spam" })
  notify { app = "A", summary = "One", actions = { "spam", "Spam", "keep", "Keep" } } test.advance(600)
  local text = test.text_of(test.get("notification-action-1")):lower()
  test.contains(text, "keep")
  test.falsy(text:find("spam", 1, true), "a hidden action was drawn")
  test.ipc("rule", "B", "actions", "false")
  notify { app = "B", summary = "Two", actions = { "keep", "Keep" } } test.advance(600)
  test.falsy(test.find { id = "notification-action-1", visible = true }, "buttons turned off still show")
  clean()
end)

test.it("a content rule follows the words, on any app", function()
  load()
  test.ipc("set", "notifications.rules", json { { app = "*", category = "", match = "[Ss]ale", mute = true } })
  notify { app = "Shop", summary = "Big sale" } test.advance(300)
  test.eq(#state().ids, 0)
  notify { app = "Shop", summary = "Your order" } test.advance(300)
  test.eq(#state().ids, 1)
  clean()
end)

test.it("a rule for one category leaves the app's others alone", function()
  load()
  test.ipc("set", "notifications.rules", json { { app = "Mail", category = "email.arrived", match = "", mute = true } })
  notify { app = "Mail", summary = "New", hints = { category = "email.arrived" } } test.advance(300)
  test.eq(#state().ids, 0)
  notify { app = "Mail", summary = "Bounced", hints = { category = "email.bounced" } } test.advance(300)
  test.eq(#state().ids, 1)
  clean()
end)

test.it("a bad pattern in a rule breaks nothing", function()
  load()
  test.ipc("set", "notifications.rules", json { { app = "*", category = "", match = "[unclosed", mute = true } })
  notify { summary = "Fine" } test.advance(300)
  test.eq(#state().ids, 1)
  clean()
end)

test.it("apps that notify are remembered for the settings, newest first", function()
  load()
  notify { app = "One", summary = "A", hints = { category = "im" } }
  notify { app = "Two", summary = "B" }
  notify { app = "One", summary = "C", hints = { category = "email" } }
  test.advance(100)
  local apps = test.ipc("rules_apps")
  test.eq(apps[1].key, "One")
  test.eq(apps[1].categories, { "im", "email" })
  clean()
end)

test.it("history has shelves: messages first, silent last", function()
  load()
  notify { app = "Quiet", summary = "Low", hints = { urgency = 0 } }
  notify { app = "Mail", summary = "Normal" }
  notify { app = "Chat", summary = "Ada", hints = { category = "im.received" } }
  test.advance(200)
  test.ipc("show_page", "yes") test.advance(2400)
  test.eq(test.get("sidebar-group-app-1").text, "Chat")
  test.eq(test.get("sidebar-group-app-3").text, "Quiet")
  test.truthy(test.find { id = "sidebar-shelf-1", visible = true })
  test.truthy(test.find { id = "sidebar-clear-silent", visible = true })
  clean()
end)

test.it("a long history stays within the engine's budget", function()
  load()
  for i = 1, 240 do notify { app = "App " .. (i % 14), summary = "Message " .. i, body = "Code 4821 https://example.org", timeout = 1 } end
  test.advance(400)
  test.ipc("show_page", "yes") test.advance(2400)
  test.eq(#state().history, 200, "the cap did not hold")
  test.click("sidebar-group-expand-1") test.advance(800)
  test.ipc("show_page", "no") test.advance(200)
  clean()
end)
