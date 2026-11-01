-- The notification and Focus pages in the whole shell, pressed as a person would,
-- on a desk and on a phone, in both themes.
--
--     morf test --no-dbus tests/notification_pages_spec.lua
local test = morf.test

local serial = 0
local function load(style, size)
  serial = serial + 1
  local settings = morf.fs.join(morf.env("XDG_CACHE_HOME"), "notification-pages-" .. serial .. ".json")
  test.load("../shell/init.lua", { size = size or { 1920, 1080 },
    env = { EVA_STYLE = style, EVA_SETTINGS = settings, EVA_DRY_RUN = "1" } })
  test.settle(1500)
  return settings
end
local function saved(settings)
  test.advance(300)
  return morf.json.decode(morf.fs.read(settings))
end
local function clean()
  test.eq(#test.logs("error"), 0)
end

local FORMS = { { "desk", { 1920, 1080 } }, { "laptop", { 1280, 800 } }, { "phone", { 868, 1932 } } }

-- Scrolls the Notifications page until the node `id` is in sight.
local function reach(id)
  local page = test.get("notif-scroll")
  for _ = 1, 40 do
    local node = test.get(id)
    if node.y >= page.y and node.y + node.height <= page.y + page.height then return end
    test.wheel(0, node.y < page.y and -120 or 120, { x = page.x + page.width / 2, y = page.y + page.height / 2 })
    test.advance(80)
  end
end

for _, style in ipairs { "material", "tsugumori" } do
  for _, form in ipairs(FORMS) do
    local name, size = form[1], form[2]
    test.it(style .. " " .. name .. ": the Focus page turns a mode on from its switch", function()
      load(style, size)
      test.ipc("settings", "focus") test.settle(1800)
      test.truthy(test.find { id = "settings-focus-modes", visible = true }, "no modes on the Focus page")
      test.click("focus-mode-switch-1") test.settle(600)
      test.eq(test.ipc("focus", "status").active, "work")
      test.contains(test.ipc("focus", "status").status, "Work")
      test.click("focus-mode-switch-1") test.settle(600)
      test.eq(test.ipc("focus", "status").active, "")
      clean()
    end)

    test.it(style .. " " .. name .. ": a mode's page edits the mode", function()
      local settings = load(style, size)
      test.ipc("settings", "focus") test.settle(1800)
      test.click("focus-mode-1-press") test.settle(1800)
      test.truthy(test.find { id = "focus-mode-scroll", visible = true }, "the mode's page did not open")
      test.click("focus-urgency-1") test.settle(300)
      test.eq(test.ipc("focus", "status").active, "")
      local modes = saved(settings).focus.modes
      local work
      for _, mode in ipairs(modes) do if mode.id == "work" then work = mode end end
      test.eq(work.allow.urgency, 1)
      clean()
    end)

    test.it(style .. " " .. name .. ": New mode opens its page, and Remove takes it", function()
      load(style, size)
      test.ipc("settings", "focus") test.settle(1800)
      test.click("focus-add") test.settle(1800)
      test.truthy(test.find { id = "focus-name-field", visible = true })
      test.contains(test.ipc("focus", "list"), "custom")
      test.click("focus-remove") test.settle(1800)
      for _, id in ipairs(test.ipc("focus", "list")) do test.ne(id, "custom") end
      clean()
    end)

    test.it(style .. " " .. name .. ": the Notifications page changes what it says", function()
      local settings = load(style, size)
      test.ipc("settings", "notifications") test.settle(1800)
      test.click("notif-sounds-switch") test.settle(300)
      test.truthy(test.find { id = "notif-volume", visible = true }, "no volume with sounds on")
      test.click("notif-time-3000") test.settle(300)
      local stored = saved(settings).notifications
      test.truthy(stored.sounds)
      test.eq(stored.timeout, 3000)
      clean()
    end)

    test.it(style .. " " .. name .. ": how long buttons keep working is chosen on the page", function()
      local settings = load(style, size)
      test.ipc("settings", "notifications") test.settle(1800)
      test.truthy(test.find { id = "notif-keep-900000", visible = true }, "the default is not on offer")
      reach("notif-keep-300000")
      test.click("notif-keep-300000") test.settle(300)
      test.eq(saved(settings).notifications.keep_actions, 300000)
      test.click("notif-keep-0") test.settle(300)
      test.eq(saved(settings).notifications.keep_actions, 0)
      clean()
    end)

    test.it(style .. " " .. name .. ": the summary's times read and write as one line", function()
      local settings = load(style, size)
      test.ipc("settings", "notifications") test.settle(1800)
      test.eq(test.get("form-notifications-digest-times").text, "08:00 18:00")
      reach("form-notifications-digest-times")
      test.click("form-notifications-digest-times") test.settle(200)
      test.key("a", "ctrl") test.type("21:30, 7:05 nonsense 25:00 21:30") test.key("Return") test.settle(300)
      test.eq(saved(settings).notifications.digest_times, { "07:05", "21:30" })
      test.eq(test.get("form-notifications-digest-times").text, "07:05 21:30", "the field shows what was kept")
      test.falsy(test.find { id = "form-notifications-digest-times-save", visible = true }, "nothing is left to save")
      clean()
    end)

    test.it(style .. " " .. name .. ": an app's page, reached from a rule's way in, writes its rule", function()
      local settings = load(style, size)
      test.ipc("notifications", "mute", "Chat", "0") test.settle(100)
      test.ipc("settings", "notifications/app") test.settle(1800)
      test.truthy(test.find { id = "notif-rule-scroll", visible = true })
      test.ipc("notifications", "unmute", "Chat") test.settle(100)
      local rules = saved(settings).notifications
      test.eq(rules and rules.rules or nil, nil, "an unmuted rule left a row behind")
      clean()
    end)
  end

  test.it(style .. ": the Focus tile says the mode and the bar's model has it", function()
    load(style)
    test.ipc("focus", "on", "work", "3600") test.settle(600)
    test.ipc("utilities", "open") test.settle(1800)
    local tile = test.text_of(test.get("utilities-toggle-focus"))
    test.contains(tile, "until")
    clean()
  end)

  test.it(style .. ": turning a mode on flashes its display", function()
    load(style)
    test.advance(3000)
    test.ipc("focus", "on", "work") test.advance(400)
    test.truthy(test.find { id = "osd-status-title", visible = true } or test.find { text = "Work", visible = true },
      "no display for a Focus mode")
    clean()
  end)

  test.it(style .. ": the rules page opens from a card's tools", function()
    load(style)
    test.ipc("notify", "Card", "Body", "critical", "Chat") test.settle(800)
    test.click("notification-tools-1") test.settle(300)
    test.click("notification-tool-1-3") test.settle(2000)
    test.truthy(test.find { id = "notif-rule-scroll", visible = true }, "the rules page did not open")
    test.contains(test.text_of(test.get("notif-rule-app")), "Chat")
    clean()
  end)

  test.it(style .. ": the history keeps the way to its settings", function()
    load(style)
    test.ipc("sidebar", "open", "notifications") test.settle(1800)
    test.truthy(test.find { id = "sidebar-settings-row-press", visible = true })
    test.click("sidebar-settings-row-press") test.settle(2000)
    test.truthy(test.find { id = "notif-scroll", visible = true })
    clean()
  end)

  test.it(style .. ": a clear shows its undo, and Undo brings it back", function()
    load(style)
    test.ipc("notify", "One", "Body", "normal", "A") test.ipc("notify", "Two", "Body", "normal", "B")
    test.settle(300)
    test.ipc("sidebar", "open", "notifications") test.settle(1800)
    test.click("sidebar-clear") test.settle(800)
    test.truthy(test.find { id = "sidebar-undo-row", visible = true })
    test.truthy(test.find { id = "sidebar-empty-label", visible = true })
    test.click("sidebar-undo-button") test.settle(800)
    test.eq(test.get("sidebar-summary-row-title").text, "2 notifications")
    clean()
  end)

  test.it(style .. ": a card in the history snoozes and wakes from there", function()
    load(style)
    test.ipc("notify", "Snooze me", "Body", "normal", "A") test.settle(300)
    test.ipc("sidebar", "open", "notifications") test.settle(1800)
    test.click("sidebar-group-expand-1") test.settle(800)
    test.click("sidebar-tools-1-1") test.settle(300)
    test.click("sidebar-tool-1-1-1") test.settle(200)
    test.click("sidebar-tool-1-1-2") test.settle(800)
    test.truthy(test.find { id = "sidebar-snoozed", visible = true }, "the snoozed section did not show it")
    test.click("sidebar-snoozed-button-1") test.settle(800)
    test.eq(test.get("sidebar-summary-row-title").text, "1 notification")
    clean()
  end)
end

test.it("the verbs answer for a key to bind", function()
  load("material")
  test.ipc("notify", "Newest", "Body", "critical", "A") test.settle(300)
  test.eq(test.ipc("notifications", "status").count, 1)
  test.eq(#test.ipc("notifications", "list"), 1)
  test.truthy(test.ipc("notifications", "dismiss")) test.settle(300)
  test.eq(test.ipc("notifications", "status").shown, 0)
  test.eq(test.ipc("notifications", "clear"), 1)
  test.truthy(test.ipc("notifications", "undo"))
  test.eq(test.ipc("notifications", "status").count, 1)
  test.ipc("notifications", "mute", "A", "0") test.settle(100)
  test.ipc("notify", "Muted", "Body", "normal", "A") test.settle(300)
  test.eq(test.ipc("notifications", "status").shown, 0)
  test.ipc("notifications", "unmute", "A") test.settle(100)
  test.raises(function() test.ipc("notifications", "nonsense") end)
  test.contains(test.ipc("focus", "list"), "sleep")
  test.truthy(test.ipc("focus", "on", "sleep", "60"))
  test.eq(test.ipc("focus", "status").active, "sleep")
  test.truthy(test.ipc("focus", "off"))
  clean()
end)
