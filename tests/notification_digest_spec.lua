-- The scheduled summary: what an app's rule holds back, when it comes, what it
-- says, and what a person can do with it. Own notifications through the model
-- and a clock of the spec's.
--     tools/test.sh tests/notification_digest_spec.lua
local test = morf.test

local HOST = [[
  local ui = require("morf.ui")
  local W, H = tonumber(morf.env("TEST_WIDTH")), tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height = H
  package.loaded.services = { here = function() return true end, installed = function() return false end,
    output = function() return "HEADLESS-1" end }
  package.loaded.bar = { desk = function() return 0, 0, W, H end }
  package.loaded["lib.services.notifications"] = { serve = function()
    return { open = function() return false end, close = function() end }
  end }
  local focus = require("focus_model")
  local clock = tonumber(morf.env("TEST_CLOCK"))
  focus.now = function() return clock end
  local notifs = require("notifs")
  local history = require("notification_history")
  local digest = require("notification_digest")
  local rules = require("notification_rules")
  local config = require("config")
  local page = history.build(W, function() return H end)
  ui.Item { width = W, height = H, notifs.drawer.panel, page, notifs.overlay() }
  morf.ipc.push = function(text) return notifs.push(morf.json.decode(text)) end
  morf.ipc.shown = function()
    local out = {}
    for _, n in ipairs(notifs.shown()) do out[#out + 1] = { summary = n.summary, body = n.body, actions = #(n.actions or {}) } end
    return out
  end
  morf.ipc.count = function() return #notifs.history:get() end
  morf.ipc.set = function(key, text) return config.set(key, morf.json.decode(text)) end
  morf.ipc.rule = function(app, field, text) return rules.set(app, field, morf.json.decode(text)) end
  morf.ipc.at = function(hm, days)
    local h, m = hm:match("(%d+):(%d+)")
    local date = morf.time.date(clock)
    local base = morf.time.time { year = date.year, month = date.month, day = date.day, hour = tonumber(h), minute = tonumber(m) }
    clock = morf.time.add(base, { days = tonumber(days or 0) })
  end
  morf.ipc.card = function()
    local s = history.digest()
    if not s then return false end
    local out = { total = s.total, conversations = {}, apps = {} }
    for i, row in ipairs(s.conversations) do out.conversations[i] = { title = row.title, app = row.app, count = #row.items } end
    for i, row in ipairs(s.apps) do out.apps[i] = { title = row.title, count = #row.items, latest = row.latest.summary } end
    return out
  end
  morf.ipc.waiting = function() return history.digest_waiting() or false end
  morf.ipc.undo = function() return notifs.undo:get() end
  morf.ipc.restore = function() return notifs.restore() end
  morf.ipc.focus = function(on)
    if on == "yes" then focus.start("dnd") else focus.stop() end
  end
  morf.ipc.flush = function() notifs.flush() end
  morf.ipc.read = function() notifs.read() end
  morf.ipc.open_group = function(key) return history.is_open(key) end
  morf.ipc.press = function(kind, i)
    local s = history.digest()
    history.digest_open(s[kind][tonumber(i)])
  end
  morf.ipc.next_due = function(hm)
    local h, m = hm:match("(%d+):(%d+)")
    local date = morf.time.date(clock)
    local at = morf.time.time { year = date.year, month = date.month, day = date.day, hour = tonumber(h), minute = tonumber(m) }
    return { last = morf.time.format("%H:%M", digest.last_due(at)), next = morf.time.format("%H:%M", digest.next_due(at)) }
  end
  local fires, tick = 0, digest.tick
  digest.tick = function(...)
    local came = tick(...)
    if came then fires = fires + 1 end
    return came
  end
  morf.ipc.fires = function() return fires end
]]

local serial = 0
local function load(style, size, store)
  serial = serial + 1
  local w, h = (size or { 408, 900 })[1], (size or { 408, 900 })[2]
  local clock = 1793520000
  test.load("../shell/init.lua", { source = HOST, size = { w, h }, env = { EVA_STYLE = style or "material", EVA_DRY_RUN = "1", TZ = "UTC",
    TEST_WIDTH = tostring(w), TEST_HEIGHT = tostring(h), TEST_CLOCK = tostring(clock), EVA_NOTIFICATION_STORE = store or "",
    EVA_SETTINGS = morf.fs.join(morf.env("XDG_CACHE_HOME"), "notification-digest-" .. serial .. ".json") } })
end
local function json(value) return morf.json.encode(value) end
local function push(spec) return test.ipc("push", json(spec)) end
local function clean()
  test.eq(#test.logs("error"), 0)
  test.eq(#test.logs("warn"), 0)
end
local function held(app) test.ipc("rule", app, "digest", "true") end
-- Past a tick of the 30-second clock.
local function tick() test.advance(30100) end

test.describe("the scheduled summary", function()
  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. ": holds a noisy app, then hands it over with conversations first", function()
      load(style)
      held("News") held("Signal")
      test.ipc("at", "12:00")
      push { app = "News", summary = "Headline", body = "Words" }
      push { app = "News", summary = "Another", body = "More words" }
      push { app = "Signal", summary = "Kate", body = "Lunch?", category = "im.received" }
      push { app = "Signal", summary = "Kate", body = "Or tea?", category = "im.received" }
      push { app = "Signal", summary = "Sam", body = "Hello", category = "im.received" }
      test.advance(300)
      test.eq(test.ipc("shown"), {}, "nothing pops while it waits")
      test.eq(test.ipc("waiting"), { count = 5, next = "18:00" })
      test.truthy(test.find { id = "digest-waiting-row", visible = true })
      test.ipc("at", "18:00")
      tick()
      local shown = test.ipc("shown")
      test.eq(shown[1].summary, "5 notifications for you")
      test.eq(shown[1].body, "2 conversations · News")
      test.eq(shown[1].actions, 1, "it says how to get to them")
      local card = test.ipc("card")
      test.eq(card.total, 5)
      test.eq(#card.conversations, 2)
      test.eq(card.conversations[1].title, "Sam")
      test.eq(card.conversations[2].title, "Kate")
      test.eq(card.conversations[2].count, 2)
      test.eq(card.apps[1].title, "News")
      test.eq(card.apps[1].count, 2)
      test.eq(card.apps[1].latest, "Another")
      test.settle(300)
      test.truthy(test.find { id = "digest-conversation-heading", visible = true })
      test.truthy(test.find { id = "digest-conversation-2", visible = true })
      test.truthy(test.find { id = "digest-app-1", visible = true })
      test.falsy(test.find { id = "digest-waiting-row", visible = true })
      test.eq(test.ipc("waiting"), false)
      if morf.env("EVA_THEME_SNAPSHOTS") == "1" then test.snapshot(style .. "-digest.png") end
      clean()
    end)
  end

  test.it("a reply field makes a conversation of an app with no category", function()
    load()
    held("Chat")
    test.ipc("at", "12:00")
    push { app = "Chat", summary = "Kate", body = "Hi", actions = { { key = "inline-reply", label = "Reply" } } }
    test.advance(100)
    test.ipc("at", "18:00")
    tick()
    test.eq(test.ipc("card").conversations[1].title, "Kate")
    clean()
  end)

  test.it("catches a time it slept through, once", function()
    load()
    held("News")
    test.ipc("at", "12:00")
    push { app = "News", summary = "One" }
    test.advance(100)
    -- The machine sleeps past 18:00 and wakes the next morning at 07:30.
    test.ipc("at", "07:30", 1)
    tick()
    test.eq(test.ipc("shown")[1].summary, "1 notification for you")
    test.ipc("at", "07:31", 0)
    tick()
    tick()
    test.eq(test.ipc("fires"), 1, "not a second one")
    clean()
  end)

  test.it("waits while a Focus holds notices back", function()
    load()
    held("News")
    test.ipc("at", "12:00")
    push { app = "News", summary = "One" }
    test.advance(100)
    test.ipc("focus", "yes")
    test.ipc("at", "18:00")
    tick()
    test.eq(test.ipc("card"), false)
    test.eq(#test.ipc("shown"), 0)
    test.ipc("focus", "no")
    tick()
    test.eq(test.ipc("card").total, 1)
    test.truthy(#test.ipc("shown") >= 1)
    clean()
  end)

  test.it("says nothing when nothing waits, and the next time still comes", function()
    load()
    held("News")
    test.ipc("at", "18:00")
    tick()
    test.eq(test.ipc("shown"), {})
    test.eq(test.ipc("card"), false)
    test.ipc("at", "19:00")
    push { app = "News", summary = "Late" }
    test.advance(100)
    test.ipc("at", "08:00", 1)
    tick()
    test.eq(test.ipc("card").total, 1)
    clean()
  end)

  test.it("what the panel already showed earns no notice, but the card has it", function()
    load()
    held("News")
    test.ipc("at", "12:00")
    push { app = "News", summary = "Seen" }
    test.advance(100)
    test.ipc("at", "13:00")
    test.ipc("read")
    test.ipc("at", "18:00")
    tick()
    test.eq(test.ipc("shown"), {})
    test.eq(test.ipc("card").total, 1)
    clean()
  end)

  test.it("takes the times from the setting, and a bad one is skipped", function()
    load()
    test.ipc("set", "notifications.digest_times", json { "07:15", "nonsense", "25:00", "21:30" })
    test.advance(20)
    test.eq(test.ipc("next_due", "12:00"), { last = "07:15", next = "21:30" })
    test.eq(test.ipc("next_due", "06:00"), { last = "21:30", next = "07:15" })
    held("News")
    test.ipc("set", "notifications.digest_times", "[]")
    test.ipc("at", "12:00")
    push { app = "News", summary = "One" }
    test.advance(100)
    test.eq(test.ipc("waiting"), { count = 1 })
    clean()
  end)

  test.it("shows it now, ahead of its time", function()
    load()
    held("News")
    test.ipc("at", "12:00")
    push { app = "News", summary = "One" }
    test.settle(300)
    test.click("digest-now")
    test.settle(200)
    test.eq(test.ipc("card").total, 1)
    test.eq(test.ipc("waiting"), false)
    test.eq(test.ipc("shown"), {}, "a press needs no notice")
    clean()
  end)

  test.it("Done puts the card away and the history keeps them", function()
    load()
    held("News")
    test.ipc("at", "12:00")
    push { app = "News", summary = "One" }
    test.advance(100)
    test.ipc("at", "18:00")
    tick()
    test.settle(300)
    test.click("digest-done")
    test.settle(200)
    test.eq(test.ipc("card"), false)
    test.eq(test.ipc("count"), 1)
    clean()
  end)

  test.it("clears as one batch a person can take back", function()
    load()
    held("News") held("Mail")
    test.ipc("at", "12:00")
    push { app = "News", summary = "One" }
    push { app = "Mail", summary = "Two" }
    test.advance(100)
    test.ipc("at", "18:00")
    tick()
    test.settle(300)
    test.click("digest-clear")
    test.settle(900)
    test.eq(test.ipc("count"), 0)
    test.eq(test.ipc("card"), false)
    test.eq(test.ipc("undo").label, "Cleared the summary")
    test.truthy(test.ipc("restore"))
    test.eq(test.ipc("count"), 2)
    clean()
  end)

  test.it("something dismissed from the history leaves the card, and a press opens its group", function()
    load()
    held("News")
    test.ipc("at", "12:00")
    push { app = "News", summary = "One" }
    test.advance(100)
    test.ipc("at", "18:00")
    tick()
    test.eq(test.ipc("open_group", "News"), false)
    test.ipc("press", "apps", "1")
    test.advance(50)
    test.eq(test.ipc("open_group", "News"), true)
    clean()
  end)

  test.it("hides what the app's rule hides", function()
    load()
    held("Bank")
    test.ipc("rule", "Bank", "hide", "true")
    test.ipc("at", "12:00")
    push { app = "Bank", summary = "Balance", body = "1000" }
    test.advance(100)
    test.ipc("at", "18:00")
    tick()
    test.settle(300)
    test.truthy(test.find { text = "New notification", visible = true })
    test.falsy(test.find { text = "1000", visible = true })
    clean()
  end)

  test.it("does not swallow what the history would not keep", function()
    load()
    held("News")
    test.ipc("set", "notifications.history.enabled", "false")
    test.advance(20)
    push { app = "News", summary = "Now" }
    test.advance(200)
    test.eq(test.ipc("shown")[1].summary, "Now")
    clean()
  end)

  test.it("remembers its card and its place through a restart", function()
    local store = morf.fs.join(morf.env("XDG_CACHE_HOME"), "digest-store-" .. serial .. ".json")
    morf.fs.remove(store)
    morf.fs.remove(store .. ".digest")
    load(nil, nil, store)
    held("News")
    test.ipc("at", "12:00")
    push { app = "News", summary = "One" }
    test.advance(100)
    test.ipc("at", "18:00")
    tick()
    test.eq(test.ipc("card").total, 1)
    test.ipc("flush")
    local saved = morf.fs.read(store .. ".digest")
    test.falsy(saved:find("One", 1, true), "no words reach its file")
    test.truthy(morf.json.decode(saved).card.to > 0)
  end)

  test.it("fits a phone", function()
    load("tsugumori", { 412, 915 })
    held("Signal")
    test.ipc("at", "12:00")
    push { app = "Signal", summary = "Kate", body = "A long message that has to be cut at the edge of the card and no later", category = "im" }
    test.advance(100)
    test.ipc("at", "18:00")
    tick()
    test.settle(300)
    local box = test.get("digest")
    test.truthy(box.x >= 0 and box.x + box.width <= 412)
    clean()
  end)
end)
