-- Screen time: what the focus says each app has had, the limit that warns and can
-- be overridden, downtime, bedtime, and that nothing leaves the machine.
-- The focus moves through the compositor's own event, from the stand-in windows.
--
--     morf test --no-dbus tests/screen_time_spec.lua
local test = morf.test
local host = assert(load(morf.fs.read(morf.env("PWD") .. "/tests/fixtures/launcher_host.lua")))()

local PHONE = { 620, 1380 }
local TOUCH = morf.env("PWD") .. "/tests/fixtures/input-devices-touch"
local NOW = 1793520000

local SOURCE = [==[
  local time = require("screen_time_model")
  local clock = tonumber(morf.env("TEST_NOW"))
  time.now = function() return clock end
  require("focus_model").now = time.now
  -- The host's own desktop entries stay out of what a class is counted under.
  local entry_of = time.app_of
  time.app_of = function(class) return class end
  morf.ipc.st_app = function(class) return entry_of(class) end
  morf.ipc.st_forget = function() time.forget() return true end
  morf.ipc.st_pass = function(seconds) clock = clock + seconds time.sample() return time.report(1) end
  morf.ipc.st_at = function(text)
    local y, m, d = morf.time.format("%Y-%m-%d", clock):match("(%d+)-(%d+)-(%d+)")
    local hour, minute = text:match("(%d+):(%d+)")
    clock = morf.time.time { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = tonumber(hour), minute = tonumber(minute) }
    time.sample()
    return true
  end
  morf.ipc.st_focus = function(class)
    local h = require("lib.compositor.hyprland")
    for i = 1, h.state.clients:len() do
      local c = h.state.clients:get(i)
      if c.class == class then require("windows_model").focus(c.address) return true end
    end
    return false
  end
  morf.ipc.st_notice = function() return time.notice:get() end
  morf.ipc.st_held = function(id) return time.holds({ id = id, name = id }, function() morf.log("info", "went ahead " .. id) end) end
  morf.ipc.st_override = function() time.override() return true end
  morf.ipc.st_extend = function() time.extend() return true end
  morf.ipc.st_limit = function(id, minutes) time.set_limit(id, minutes) return true end
  morf.ipc.st_spent = function(id) return time.spent(id) end
  morf.ipc.st_file = function() return morf.env("EVA_SCREEN_TIME") end
  morf.ipc.st_mode = function() return require("focus_model").active_id() end
  morf.ipc.st_bedtime = function() return time.bedtime() end
  morf.ipc.st_settle = function() return time.verb("bedtime") end
  morf.ipc.st_downtime = function() return time.downtime() end
  morf.ipc.st_grey = function() return require("config").get("filters.grayscale") end
  morf.ipc.st_set = function(key, value) require("config").set(key, value) return true end
]==]

local serial = 0
local function load(style, settings, env, kept)
  serial = serial + 1
  env = env or {}
  env.EVA_INPUT_DEVICES, env.EVA_FAKE_WINDOWS = TOUCH, "1"
  env.TEST_NOW = tostring(NOW)
  env.EVA_SCREEN_TIME = morf.env("XDG_CACHE_HOME") .. "/screen-time-" .. serial .. ".json"
  if kept then morf.fs.write(env.EVA_SCREEN_TIME, morf.json.encode(kept)) end
  host.load { style = style, size = PHONE, settings = settings, env = env, prelude = SOURCE }
  test.ipc("close") test.settle(300)
end

local function usage(rows, key)
  for _, row in ipairs(rows) do if row.key == key then return row.seconds end end
  return 0
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " counting", function()
    test.it("adds up the focused app, and moves on as the focus does", function()
      load(style)
      test.ipc("st_focus", "kitty") test.advance(50)
      local rows = test.ipc("st_pass", 20)
      test.eq(usage(rows, "kitty"), 20)
      test.ipc("st_focus", "firefox") test.advance(50)
      rows = test.ipc("st_pass", 10)
      test.eq(usage(rows, "kitty"), 20, "time went to the app that lost the focus")
      test.eq(usage(rows, "firefox"), 10)
    end)

    test.it("counts an app by its desktop entry where it has one", function()
      load(style)
      test.eq(test.ipc("st_app", "fixture-browser"), "fixture-browser")
      test.eq(test.ipc("st_app", "no-such-class-at-all"), "no-such-class-at-all")
    end)

    test.it("counts no more than two ticks for a gap, as across a sleep", function()
      load(style)
      test.ipc("st_focus", "kitty") test.advance(50)
      local rows = test.ipc("st_pass", 8 * 3600)
      test.eq(usage(rows, "kitty"), 60)
    end)

    test.it("counts nothing while locked", function()
      load(style, nil, { EVA_FAKE_LOCKED = "1" })
      test.ipc("st_focus", "kitty") test.advance(50)
      test.eq(usage(test.ipc("st_pass", 20), "kitty"), 0)
    end)

    test.it("counts nothing when turned off", function()
      load(style, { wellbeing = { enabled = false } })
      test.ipc("st_focus", "kitty") test.advance(50)
      test.eq(usage(test.ipc("st_pass", 20), "kitty"), 0)
      test.falsy(test.ipc("st_notice"))
    end)

    test.it("keeps its file on this machine, and asks nothing of the network", function()
      load(style)
      test.ipc("st_focus", "kitty") test.advance(50)
      test.ipc("st_pass", 20)
      local text = morf.fs.read(test.ipc("st_file"))
      test.truthy(text:find("kitty", 1, true), "the count was not kept")
      for _, argv in ipairs(test.runs()) do
        test.falsy(argv[1] == "curl" or argv[1] == "wget", "something went out")
      end
    end)
  end)

  test.describe(style .. " limits", function()
    local LIMIT = { wellbeing = { limits = { { app = "kitty", minutes = 1 } } } }

    test.it("warns once a limit is used up, and says it cannot stop the app", function()
      load(style, LIMIT)
      test.ipc("st_focus", "kitty") test.advance(50)
      test.ipc("st_pass", 30)
      test.falsy(test.ipc("st_notice"), "it warned early")
      test.ipc("st_pass", 30) test.advance(200)
      local notice = test.ipc("st_notice")
      test.truthy(notice, "no warning")
      test.eq(notice.kind, "limit")
      test.truthy(test.find { id = "screen-time-notice", visible = true })
      test.matches(test.get("screen-time-why").text, "cannot stop an app")
      test.truthy(test.ipc("st_spent", "kitty"))
    end)

    test.it("can be overridden, and says nothing more that day", function()
      load(style, LIMIT)
      test.ipc("st_focus", "kitty") test.advance(50)
      test.ipc("st_pass", 30) test.ipc("st_pass", 30) test.advance(200)
      test.click("screen-time-override") test.advance(200)
      test.falsy(test.ipc("st_notice"), "it did not go")
      test.ipc("st_pass", 30) test.advance(200)
      test.falsy(test.ipc("st_notice"), "it came back after being overridden")
    end)

    test.it("gives more minutes, and warns again when they run out", function()
      load(style, LIMIT)
      test.ipc("st_focus", "kitty") test.advance(50)
      test.ipc("st_pass", 30) test.ipc("st_pass", 30) test.advance(200)
      test.click("screen-time-more") test.advance(200)
      test.falsy(test.ipc("st_notice"))
      test.falsy(test.ipc("st_spent", "kitty"), "the extra minutes did not count")
      for _ = 1, 30 do test.ipc("st_pass", 30) end
      test.advance(200)
      test.truthy(test.ipc("st_notice"), "no second warning")
    end)

    test.it("asks before opening an app that has run out, and opens it if told", function()
      load(style, { wellbeing = { limits = { { app = "fixture-editor", minutes = 1 } } } }, nil,
        { days = { [morf.time.format("%Y-%m-%d", NOW)] = { ["fixture-editor"] = 120 } } })
      test.truthy(test.ipc("st_spent", "fixture-editor"), "the file was not read")
      test.ipc("launcher", "open") test.settle(600)
      local tile = test.get { text = "Fixture Editor", visible = true }
      test.click(tile.x + tile.width / 2, tile.y - 12) test.settle(400)
      test.falsy(host.logged("launch fixture-editor"), "it opened with no word")
      test.truthy(test.ipc("st_notice"), "no word")
      test.click("screen-time-override") test.settle(200)
      test.truthy(host.logged("launch fixture-editor"), "going on did not open it")
    end)

    test.it("leaves an app with time left alone", function()
      load(style, LIMIT)
      test.falsy(test.ipc("st_held", "kitty"), "it held an app with time left")
      test.falsy(test.ipc("st_held", "firefox"), "it held an app with no limit")
    end)
  end)

  test.describe(style .. " downtime and bedtime", function()
    test.it("warns of an app in downtime, and lets through what is allowed", function()
      load(style, { wellbeing = { downtime = { on = true, from = "22:00", to = "07:00", allowed = { "kitty" } } } })
      test.ipc("st_at", "23:00")
      test.truthy(test.ipc("st_downtime"))
      test.falsy(test.ipc("st_held", "kitty"), "an allowed app was held")
      test.truthy(test.ipc("st_held", "firefox"), "downtime let it by")
      test.eq(test.ipc("st_notice").kind, "downtime")
      test.ipc("st_override")
      test.falsy(test.ipc("st_held", "firefox"), "it warned twice in a night")
    end)

    test.it("is off outside its hours", function()
      load(style, { wellbeing = { downtime = { on = true, from = "22:00", to = "07:00", allowed = {} } } })
      test.ipc("st_at", "12:00")
      test.falsy(test.ipc("st_downtime"))
    end)

    test.it("greys the screen and quiets it at bedtime, and puts both back", function()
      load(style, { wellbeing = { bedtime = { on = true, from = "22:30", to = "07:00", grayscale = true, quiet = true } } })
      test.ipc("st_at", "12:00") test.ipc("st_set", "wellbeing.bedtime.from", "22:30") test.advance(50)
      test.falsy(test.ipc("st_bedtime"))
      test.ipc("st_at", "23:00") test.ipc("st_set", "wellbeing.bedtime.to", "07:01") test.advance(50)
      test.truthy(test.ipc("st_bedtime"), "bedtime did not start")
      test.truthy(test.ipc("st_grey"), "the screen stayed in colour")
      test.eq(test.ipc("st_mode"), "sleep")
      test.ipc("st_at", "12:00") test.ipc("st_set", "wellbeing.bedtime.to", "07:00") test.advance(50)
      test.falsy(test.ipc("st_bedtime"), "bedtime did not end")
      test.falsy(test.ipc("st_grey"), "the colour did not come back")
      test.eq(test.ipc("st_mode"), "")
    end)

    test.it("leaves a filter or a focus the person set themselves", function()
      load(style, { filters = { grayscale = true },
        wellbeing = { bedtime = { on = false, from = "22:30", to = "07:00", grayscale = true, quiet = true } } })
      test.ipc("focus", "on", "work") test.advance(50)
      test.ipc("screen-time", "bedtime", "on") test.advance(50)
      test.eq(test.ipc("st_mode"), "work", "bedtime took over a focus")
      test.ipc("screen-time", "bedtime", "off") test.advance(50)
      test.truthy(test.ipc("st_grey"), "bedtime took off a filter it did not put on")
      test.eq(test.ipc("st_mode"), "work")
    end)
  end)

  test.describe(style .. " the page", function()
    test.it("lists the apps, says limits cannot enforce, and sets one", function()
      load(style)
      test.ipc("st_focus", "kitty") test.advance(50)
      test.ipc("st_pass", 30) test.ipc("st_pass", 30)
      test.ipc("settings", "screen_time") test.settle(900)
      test.truthy(test.find { id = "screen-time-honest", visible = true })
      test.matches(test.get("screen-time-honest-subtitle").text, "cannot stop an app")
      test.matches(test.get("screen-time-local-subtitle").text, "Nothing leaves it")
      test.matches(test.get("screen-time-downtime-from-label").text, "Starts")
      test.matches(test.get("screen-time-app-1-title").text, "kitty")
      test.click("screen-time-app-1-press") test.settle(900)
      test.truthy(test.find { id = "screen-time-limit", visible = true }, "no limit page")
      test.click("screen-time-limit-30") test.settle(200)
      test.eq(test.ipc("setting", "wellbeing.limits"), { { app = "kitty", minutes = 30 } })
      test.eq(#test.logs("error"), 0)
    end)

    test.it("forgets what it counted, and its settings stay", function()
      load(style, { wellbeing = { limits = { { app = "kitty", minutes = 30 } } } })
      test.ipc("st_focus", "kitty") test.advance(50)
      test.ipc("st_pass", 30)
      test.ipc("settings", "screen_time") test.settle(900)
      test.truthy(test.find { id = "screen-time-forget-button" }, "no way to forget it")
      test.ipc("st_forget") test.settle(300)
      test.eq(usage(test.ipc("st_pass", 0), "kitty"), 0, "the count stayed")
      test.eq(#test.ipc("setting", "wellbeing.limits"), 1)
    end)

    test.it("has tiles on the board, and is found by search", function()
      load(style)
      local hits = {}
      for _, hit in ipairs(test.ipc("settings-search", "downtime")) do hits[#hits + 1] = hit.key end
      test.truthy(table.concat(hits, " "):find("screen_time", 1, true), "search does not find it")
      test.ipc("quick", "edit") test.settle(900)
      test.truthy(test.find { id = "utilities-add-bedtime", visible = true }, "no Bedtime tile")
      test.truthy(test.find { id = "utilities-add-screentime", visible = true }, "no Screen time tile")
    end)
  end)
end
