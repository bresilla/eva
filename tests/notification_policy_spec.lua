-- The rest of how notifications behave: timing, hiding, the summary, what a lock
-- screen may say, and what rides on arrival. Own notifications through the model;
-- the bus itself is tests/notification_bus_spec.lua.
--
--     morf test --no-dbus tests/notification_policy_spec.lua
local test = morf.test

local HOST = [[
  local ui = require("morf.ui")
  morf.surface.height = 750
  package.loaded.services = { here = function() return true end, installed = function() return false end,
    output = function() return "HEADLESS-1" end }
  package.loaded.bar = { desk = function() return 10, 10, 1080, 730 end }
  local served = 0
  package.loaded["lib.services.notifications"] = { serve = function(options)
    served = served + 1
    morf.ipc.server = function(text)
      options.on_change(morf.json.decode(text))
    end
    return { open = function() return false end, close = function() served = served - 1 end }
  end }
  local focus = require("focus_model")
  local clock = 1793520000
  focus.now = function() return clock end
  local notifs = require("notifs")
  local history = require("notification_history")
  local rules = require("notification_rules")
  local config = require("config")
  local C = require("theme").color
  local shown_page = morf.signal("test.page", false)
  local page = history.build(1060, function() return 700 end)
  local copied = ""
  morf.clipboard.set = function(value) copied = value end
  ui.Item { width = 1100, height = 750,
    ui.Rect { width = 1100, height = 750, color = function() return C.surface end },
    ui.Item { x = 10, y = 10, width = 1080, height = 730,
      ui.Sdf { anchors = { fill = true }, fill_color = function() return C.surfaceContainer end, notifs.drawer.shape },
      notifs.drawer.panel },
    ui.Item { x = 20, y = 20, width = 1060, height = 700, visible = function() return shown_page:get() end, page },
    notifs.overlay(),
  }
  morf.ipc.copied = function() return copied end
  morf.ipc.push = function(text) return notifs.push(morf.json.decode(text)) end
  morf.ipc.shown = function()
    local out = {}
    for _, n in ipairs(notifs.shown()) do out[#out + 1] = n.summary end
    return out
  end
  morf.ipc.open = function() return notifs.drawer.open:get() end
  morf.ipc.history = function() return notifs.history:get() end
  morf.ipc.set = function(key, text) return config.set(key, morf.json.decode(text)) end
  morf.ipc.rule = function(app, field, text) return rules.set(app, field, morf.json.decode(text)) end
  morf.ipc.lock = function() return notifs.lock_view() end
  morf.ipc.pulse = function() return notifs.pulse:get() end
  morf.ipc.served = function() return served end
  morf.ipc.ongoing = function(text) return notifs.ongoing(morf.json.decode(text)) end
  morf.ipc.rule_word = function(word, text) return notifs.rule_word(word, morf.json.decode(text)) end
  morf.ipc.expand = function(id) notifs.toggle(tonumber(id)) end
  morf.ipc.clock_to = function(hm)
    local h, m = hm:match("(%d+):(%d+)")
    local zero = clock - tonumber(morf.time.format("%H", clock)) * 3600 - tonumber(morf.time.format("%M", clock)) * 60
    clock = zero + tonumber(h) * 3600 + tonumber(m) * 60
  end
  morf.ipc.auto = function(word) focus.auto:set(word) end
  morf.ipc.show_page = function(on) shown_page:set(on == "yes") notifs.covered:set(on == "yes") end
  morf.ipc.dismiss_at = function(i) notifs.dismiss_at(tonumber(i)) end
]]

local serial = 0
local function load(style)
  serial = serial + 1
  test.load("../shell/init.lua", { source = HOST, size = { 1100, 750 }, env = { EVA_STYLE = style or "material",
    EVA_DRY_RUN = "1",
    EVA_SETTINGS = morf.fs.join(morf.env("XDG_CACHE_HOME"), "notification-policy-" .. serial .. ".json") } })
end
local function json(value) return morf.json.encode(value) end
local function push(spec) return test.ipc("push", json(spec)) end
local function clean()
  test.eq(#test.logs("error"), 0)
  test.eq(#test.logs("warn"), 0)
end

test.it("the time on screen follows the setting, and apps' own unless told otherwise", function()
  load()
  test.ipc("set", "notifications.timeout", "2000") test.advance(20)
  push { app = "A", summary = "Set" } test.advance(1800)
  test.eq(test.ipc("shown"), { "Set" })
  test.advance(300)
  test.eq(test.ipc("shown"), {})
  push { app = "B", summary = "Own time", timeout_ms = 900 } test.advance(1000)
  test.eq(test.ipc("shown"), {}, "an app's own time was not kept")
  test.ipc("set", "notifications.ignore_app_timeouts", "true") test.advance(20)
  push { app = "C", summary = "Overruled", timeout_ms = 900 } test.advance(1000)
  test.eq(test.ipc("shown"), { "Overruled" }, "an app's time was not ignored")
  clean()
end)

test.it("no more cards stand than asked for", function()
  load()
  test.ipc("set", "notifications.max_popups", "1") test.advance(20)
  push { app = "A", summary = "One", urgency = 2 } push { app = "B", summary = "Two", urgency = 2 }
  test.advance(600)
  test.truthy(test.find { id = "notification-1", visible = true })
  test.falsy(test.find { id = "notification-2", visible = true })
  clean()
end)

test.it("hidden content shows the app alone until it is opened", function()
  load()
  test.ipc("set", "notifications.previews", '"hide"') test.advance(20)
  local id = push { app = "Bank", summary = "Balance", body = "You have 12", urgency = 2 } test.advance(2400)
  local card = test.text_of(test.get("notification-1"))
  test.falsy(card:find("You have 12", 1, true), "the body showed")
  test.falsy(card:lower():find("balance", 1, true), "the summary showed")
  test.ipc("expand", tostring(id)) test.advance(2400)
  test.contains(test.text_of(test.get("notification-1")), "You have 12")
  clean()
end)

test.it("one app's content can be hidden alone", function()
  load()
  test.ipc("rule", "Bank", "hide", "true")
  push { app = "Bank", summary = "Secret", body = "Hidden", urgency = 2 }
  push { app = "Mail", summary = "Open", body = "Shown", urgency = 2 } test.advance(600)
  test.falsy(test.text_of(test.get("notification-2")):find("Hidden", 1, true))
  test.contains(test.text_of(test.get("notification-1")), "Shown")
  clean()
end)

test.it("sharing the screen hides what cards say", function()
  load()
  push { app = "Mail", summary = "Plain", body = "Private words", urgency = 2 } test.advance(600)
  test.contains(test.text_of(test.get("notification-1")), "Private words")
  test.ipc("auto", "sharing") test.advance(50)
  test.falsy(test.text_of(test.get("notification-1")):find("Private words", 1, true), "the words stayed on a shared screen")
  clean()
end)

test.it("a dismissed popup can leave the history as well", function()
  load()
  test.ipc("set", "notifications.history.keep_dismissed", "false") test.advance(20)
  push { app = "A", summary = "Gone", urgency = 2 } test.advance(600)
  test.ipc("dismiss_at", "1") test.advance(500)
  test.eq(#test.ipc("history"), 0)
  clean()
end)

test.it("a held-back app waits for the summary at its time", function()
  load()
  test.ipc("rule", "News", "digest", "true")
  test.ipc("clock_to", "12:00")
  push { app = "News", summary = "One" } push { app = "News", summary = "Two" } test.advance(300)
  test.eq(test.ipc("shown"), {})
  test.eq(#test.ipc("history"), 2)
  test.ipc("clock_to", "18:00")
  test.advance(30100)
  test.eq(test.ipc("shown"), { "2 notifications for you" })
  clean()
end)

test.it("a critical one does not wait for the summary", function()
  load()
  test.ipc("rule", "News", "digest", "true")
  push { app = "News", summary = "Now", urgency = 2 } test.advance(300)
  test.eq(test.ipc("shown"), { "Now" })
  clean()
end)

test.it("a lock screen is told only what the setting allows", function()
  load()
  push { app = "Mail", summary = "Subject", body = "Words" } test.advance(100)
  local view = test.ipc("lock")
  test.eq(view.apps, { "Mail" }, "the default is the app's name")
  test.eq(#view.entries, 0)
  test.ipc("set", "notifications.lock_previews", '"all"') test.advance(20)
  test.eq(test.ipc("lock").entries[1].summary, "Subject")
  test.ipc("set", "notifications.lock_previews", '"count"') test.advance(20)
  view = test.ipc("lock")
  test.eq(view.count, 1)
  test.eq(#view.apps, 0)
  test.ipc("set", "notifications.lock_previews", '"none"') test.advance(20)
  test.eq(test.ipc("lock").count, 0)
  clean()
end)

test.it("a lock screen never gets hidden content", function()
  load()
  test.ipc("rule", "Bank", "hide", "true")
  test.ipc("set", "notifications.lock_previews", '"all"') test.advance(20)
  push { app = "Bank", summary = "Balance", body = "12" } test.advance(100)
  test.eq(#test.ipc("lock").entries, 0)
  clean()
end)

test.it("an arrival lights the screen only when asked to, and draws it", function()
  load()
  local before = test.ipc("pulse")
  push { app = "A", summary = "Quiet" } test.advance(50)
  test.eq(test.ipc("pulse"), before)
  test.ipc("set", "notifications.edge_light", "true") test.advance(20)
  push { app = "B", summary = "Lit" } test.advance(100)
  test.eq(test.ipc("pulse"), before + 1)
  test.truthy(test.get("notification-edge").opacity > 0, "the edge did not light")
  test.advance(1600)
  test.near(test.get("notification-edge").opacity, 0, .01)
  test.ipc("set", "notifications.flash", "true") test.advance(20)
  push { app = "C", summary = "Flash" } test.advance(50)
  test.truthy(test.get("notification-flash").opacity > 0, "the flash did not come")
  clean()
end)

test.it("a held-back arrival does not light the screen", function()
  load()
  test.ipc("set", "notifications.edge_light", "true")
  test.ipc("rule", "A", "mute", "true") test.advance(20)
  local before = test.ipc("pulse")
  push { app = "A", summary = "Muted" } test.advance(50)
  test.eq(test.ipc("pulse"), before)
  clean()
end)

test.it("the server comes and goes with its switch", function()
  load()
  test.advance(50)
  test.eq(test.ipc("served"), 1)
  test.ipc("set", "notifications.daemon", "false") test.advance(50)
  test.eq(test.ipc("served"), 0)
  push { app = "Eva", summary = "The shell's own still show", urgency = 2 } test.advance(600)
  test.eq(#test.ipc("shown"), 1)
  test.ipc("set", "notifications.daemon", "true") test.advance(50)
  test.eq(test.ipc("served"), 1)
  clean()
end)

test.it("a rule's command is logged, dry, with its words filled in", function()
  load()
  test.ipc("rule", "Pager", "run", json { "logger", "$APP: $SUMMARY" })
  push { app = "Pager", summary = "Up" } test.advance(50)
  local said = {}
  for _, line in ipairs(test.logs("info")) do said[#said + 1] = line.message end
  test.contains(table.concat(said, "\n"), "notification rule (dry run)")
  test.eq(#test.runs(), 0, "a dry run started a program")
  clean()
end)

test.it("a body with percent signs goes through a rule's words whole", function()
  load()
  test.eq(test.ipc("rule_word", "$APP: $BODY", json { app = "Disk", body = "100% full %1 %d" }), "Disk: 100% full %1 %d")
  test.eq(test.ipc("rule_word", "$NOPE", json {}), "$NOPE")
  clean()
end)

test.it("a job only counts as running while its sender is there", function()
  load()
  test.falsy(test.ipc("ongoing", json { id = 7, hints = { value = 40 } }))
  test.truthy(test.ipc("ongoing", json { id = 7, resident = true }))
  clean()
end)

test.it("a body's text still reads plain beneath its markup", function()
  load()
  push { app = "A", summary = "S", body = "<b>All</b> &amp; <i>done</i>", urgency = 2 } test.advance(2400)
  test.eq(test.get("notification-body-1").text, "All & done")
  clean()
end)

local function press_link(href)
  push { app = "A", summary = "S", body = ('<a href="%s">%s</a>'):format(href, string.rep("link ", 6)), urgency = 2 }
  test.advance(2400)
  local body = test.get("notification-body-1")
  test.click(body.x + 12, body.y + body.height / 2) test.advance(100)
  local said = {}
  for _, line in ipairs(test.logs("info")) do said[#said + 1] = line.message end
  return table.concat(said, "\n")
end

test.it("a press on a link opens it, and leaves the card", function()
  load()
  test.contains(press_link("https://example.org/x"), "open link (dry run): https://example.org/x")
  test.eq(#test.ipc("shown"), 1, "a press on a link also dismissed the card")
  clean()
end)

test.it("a link to the machine's own files is refused", function()
  load()
  local said = press_link("file:///etc/passwd")
  test.contains(said, "refused a notification link")
  test.falsy(said:find("open link", 1, true))
  clean()
end)

test.it("a picture that is not there falls back to the emblem", function()
  load()
  push { app = "A", summary = "S", image = "/nonexistent/picture.png", urgency = 2 } test.advance(900)
  test.truthy(test.find { id = "notification-emblem-1", visible = true })
  test.eq(#test.logs("error"), 0)
end)

test.it("a picture that is the news stands at full width", function()
  load()
  push { app = "Shots", summary = "Screenshot", image = morf.fs.join(morf.env("PWD") or ".", "tests/fixtures/wallpaper.png"), urgency = 2 }
  test.advance(600)
  test.truthy(test.find { id = "notification-preview-1", visible = true })
  clean()
end)

test.it("a message's picture is its avatar until opened", function()
  load()
  local id = push { app = "Chat", summary = "Ada", category = "im.received", image = "/tmp/face.png", urgency = 2 }
  test.advance(600)
  test.falsy(test.find { id = "notification-preview-1", visible = true })
  test.ipc("expand", tostring(id)) test.advance(300)
  test.truthy(test.find { id = "notification-preview-1", visible = true })
  test.eq(#test.logs("error"), 0)
end)

test.it("a call stands out without being critical", function()
  load()
  push { app = "Phone", summary = "Ada", category = "call.incoming" } test.advance(600)
  test.advance(9000)
  test.eq(#test.ipc("shown"), 1, "a ringing call expired")
  clean()
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " a code gets its chip, and the chip copies", function()
    load(style)
    push { app = "Bank", summary = "Your code", body = "Use 482913 to sign in", urgency = 2 } test.advance(2400)
    test.truthy(test.find { id = "notification-chip-1-1", visible = true }, "no chip for a code")
    test.click("notification-chip-1-1") test.advance(100)
    test.eq(test.ipc("copied"), "482913")
    test.eq(#test.ipc("shown"), 1, "the chip also dismissed the card")
    clean()
  end)
end
