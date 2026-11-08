-- The quick settings' catalogue past the first tiles, on the one board, and the
-- rules for what folds when a status bar runs out of room.
--
--     morf test --no-dbus tests/quick_catalogue_spec.lua
local test = morf.test

local HOST = [==[
  require("init")
  local utilities = require("utilities")
  local status = require("status_model")
  morf.ipc.tile_ids = function()
    local out = {}
    for _, tile in ipairs(utilities.TOGGLES) do out[#out + 1] = tile.id end
    return out
  end
  morf.ipc.tile_on = function(id) return utilities.CONTROLS[id].on() == true end
  morf.ipc.press_tile = function(id)
    local t = utilities.CONTROLS[id]
    t.set(not t.on())
    return true
  end
  morf.ipc.present = function(id)
    local t = utilities.CONTROLS[id]
    return t.present == nil or t.present() == true
  end
  morf.ipc.spare = function()
    local out = {}
    for _, item in ipairs(utilities.tiles.spare()) do out[item.id] = true end
    return out
  end
  morf.ipc.setting = function(key) return require("config").get(key) end
  morf.ipc.rule = function(id, rule) status.set_rule(id, rule) return status.rule(id) end
  morf.ipc.arrange = function(room)
    local active = {}
    for _, source in ipairs(status.read()) do active[#active + 1] = { key = source.key, tier = source.tier } end
    local plan = status.arrange(active, tonumber(room), { icon = 24, dot = 8, fixed = 100 })
    local keys = {}
    for _, item in ipairs(active) do keys[#keys + 1] = item.key end
    return { keys = keys, hidden = plan.hidden, dot = plan.dot }
  end
  morf.ipc.tier = function(id, tier) return status.tier_of(id, tier) end
  morf.ipc.session_open = function() return require("session").drawer.open:get() end
  morf.ipc.launcher_query = function() return require("launcher").query:get() end
  morf.ipc.launcher_open = function() return require("launcher").drawer.open:get() end
]==]

local serial = 0
local TOUCH = morf.env("PWD") .. "/tests/fixtures/input-devices-touch"

local function load(style, size, settings, env)
  serial = serial + 1
  local path = morf.env("XDG_CACHE_HOME") .. "/quick-catalogue-" .. serial .. ".json"
  morf.fs.write(path, morf.json.encode(settings or {}))
  env = env or {}
  env.EVA_STYLE, env.EVA_DRY_RUN, env.EVA_SETTINGS, env.EVA_WALLPAPER = style, "1", path, ""
  env.EVA_INPUT_DEVICES = env.EVA_INPUT_DEVICES or TOUCH
  env.HOME = morf.env("XDG_CACHE_HOME")
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { source = HOST, size = size or { 412, 915 }, env = env })
  test.settle(900)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " the catalogue", function()
    test.it("offers what the shell can do, on the same board", function()
      load(style)
      local ids = {}
      for _, id in ipairs(test.ipc("tile_ids")) do ids[id] = true end
      for _, id in ipairs { "timer", "clipboard", "qr", "translate", "magnifier", "colorpick", "pomodoro", "breaks", "clock",
        "highcontrast", "largetext", "lockscreen", "power", "alwayson", "getapps" } do
        test.truthy(ids[id], "no tile " .. id)
      end
      test.eq(#test.logs("error"), 0)
    end)

    test.it("offers a tool only where this install has it", function()
      load(style)
      test.truthy(test.ipc("present", "qr"), "apps/qr is here")
      test.ipc("quick", "edit") test.settle(900)
      test.truthy(test.ipc("spare").qr, "it does not wait to be added")
      test.truthy(test.find { id = "utilities-add-qr", visible = true }, "no way to add it")
      test.ipc("close") test.settle(300)
      test.ipc("press_tile", "qr") test.settle(900)
      test.eq(test.ipc("tools", "state"), { open = true, page = "qr" }, "a press opened nothing")
    end)

    test.it("leaves a tool out where this install lacks it", function()
      load(style, nil, nil, { EVA_FAKE_SYSTEM = "1" })
      test.falsy(test.ipc("present", "qr"), "offered a tool this install lacks")
    end)

    test.it("flips what it stands for", function()
      load(style)
      test.falsy(test.ipc("tile_on", "highcontrast"))
      test.ipc("press_tile", "highcontrast") test.settle(100)
      test.truthy(test.ipc("setting", "appearance.high_contrast"), "the setting did not move")
      test.falsy(test.ipc("tile_on", "largetext"))
      test.ipc("press_tile", "largetext") test.settle(1200)
      test.eq(test.ipc("setting", "appearance.text_scale"), 1.25)
      test.truthy(test.ipc("tile_on", "largetext"), "the tile does not light")
    end)

    test.it("opens what it stands for", function()
      load(style)
      test.ipc("press_tile", "power") test.settle(400)
      test.truthy(test.ipc("session_open"), "no power menu")
      test.ipc("close") test.settle(300)
      test.ipc("press_tile", "timer") test.settle(400)
      test.truthy(test.ipc("launcher_open"), "no launcher")
      test.eq(test.ipc("launcher_query"), "> timer ")
      test.ipc("close") test.settle(300)
      test.ipc("press_tile", "clipboard") test.settle(400)
      test.eq(test.ipc("launcher_query"), ";")
    end)
  end)

  test.describe(style .. " what folds", function()
    local FULL = "alarm,night,awake,hotspot,ring,headphones,bluetooth,vpn,dnd,mic"

    test.it("keeps to the shipped order with no rules", function()
      load(style, nil, nil, { EVA_FAKE_STATUS = FULL })
      local plan = test.ipc("arrange", 160)
      test.truthy(plan.hidden.alarm, "the rarest stayed")
      test.falsy(plan.hidden.mic, "a microphone in use folded")
      test.truthy(plan.dot)
    end)

    test.it("keeps what a person keeps, and folds first what they say", function()
      load(style, nil, { bar = { fold = { { id = "alarm", rule = "keep" }, { id = "vpn", rule = "early" } } } }, { EVA_FAKE_STATUS = FULL })
      local plan = test.ipc("arrange", 160)
      test.falsy(plan.hidden.alarm, "a kept icon folded")
      test.truthy(plan.hidden.vpn, "what folds first stayed")
    end)

    test.it("never shows what a person hid, and never hides what is watching", function()
      load(style, nil, { bar = { fold = { { id = "alarm", rule = "hide" }, { id = "mic", rule = "hide" },
        { id = "camera", rule = "early" } } } }, { EVA_FAKE_STATUS = FULL .. ",camera" })
      local keys = {}
      for _, key in ipairs(test.ipc("arrange", 900).keys) do keys[key] = true end
      test.falsy(keys.alarm, "a hidden icon showed")
      test.truthy(keys.mic, "a rule hid the microphone in use")
      test.truthy(keys.camera)
      test.eq(test.ipc("tier", "camera", 0), 0, "a rule could fold the camera")
    end)

    test.it("rules on the bar's own modules, and leaves what never folds", function()
      load(style)
      test.eq(test.ipc("tier", "notifications", 3), 3)
      test.ipc("rule", "notifications", "early")
      test.eq(test.ipc("tier", "notifications", 3), 1)
      test.ipc("rule", "notifications", "keep")
      test.eq(test.ipc("tier", "notifications", 3), 0)
      test.eq(test.ipc("rule", "notifications", "auto"), "auto")
      test.eq(test.ipc("setting", "bar.fold"), {})
      test.ipc("rule", "clock", "early")
      test.eq(test.ipc("tier", "clock", 0), 0, "a rule folded what never folds")
    end)

    test.it("has a page, reached from the Bar's, in the phone's width", function()
      load(style)
      test.ipc("settings", "bar") test.settle(900)
      test.truthy(test.find { id = "bar-fold-open" }, "the Bar page does not lead there")
      test.ipc("settings", "bar/fold") test.settle(900)
      test.truthy(test.find { id = "bar-fold-indicators", visible = true })
      test.falsy(test.find { id = "bar-fold-mic" }, "a rule offered on a microphone in use")
      local box = test.get("bar-fold-scroll")
      test.truthy(box.x >= 0 and box.x + box.width <= 412, "wider than the phone")
      test.click("bar-fold-alarm-hide") test.settle(200)
      test.eq(test.ipc("setting", "bar.fold"), { { id = "alarm", rule = "hide" } })
      test.eq(#test.logs("error"), 0)
    end)

    test.it("is found by search", function()
      load(style)
      local words = {}
      for _, hit in ipairs(test.ipc("settings-search", "folds first")) do words[#words + 1] = hit.name end
      test.truthy(table.concat(words, " "):find("What folds first", 1, true), "Settings search does not find it")
    end)
  end)
end
