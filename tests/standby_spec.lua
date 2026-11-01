-- StandBy: on charge and sideways, a phone is a bedside screen.
--
--     morf test --no-dbus tests/standby_spec.lua
local test = morf.test
local ROOT = morf.fs.join(morf.env("PWD") or ".", "tests/fixtures/wallpapers")

local SOURCE = [[
  require("init")
  local config = require("config")
  morf.ipc.s_set = function(key, value) return config.set(key, value) end
  morf.ipc.s_form = function() return require("responsive").form() end
]]

local serial = 0
local function load(spec)
  spec = spec or {}
  serial = serial + 1
  local cache = morf.env("XDG_CACHE_HOME")
  local env = { EVA_DRY_RUN = "1", EVA_STYLE = spec.style or "material", EVA_WALLPAPER = "",
    EVA_SETTINGS = cache .. "/standby-settings-" .. serial .. ".json",
    EVA_APPEARANCE = cache .. "/standby-appearance-" .. serial .. ".json",
    LULE_A = "/nonexistent/lule", HOME = cache, EVA_FAKE_BATTERY = spec.battery or "64,charging",
    EVA_FAKE_CLOCK = spec.clock or "12:00",
    EVA_INPUT_DEVICES = morf.env("PWD") .. "/tests/fixtures/input-devices" .. (spec.desk and "" or "-touch") }
  morf.fs.write(env.EVA_SETTINGS, morf.json.encode(spec.settings or { lule = { folder = ROOT } }))
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { source = SOURCE, size = spec.size or { 1080, 500 }, env = env })
  test.settle(1200)
end

local function shown() return test.ipc("standby", "state").showing end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " StandBy", function()
    test.it("comes on charge sideways, and builds every view", function()
      load { style = style }
      test.truthy(shown(), "it did not come")
      test.truthy(test.find { id = "standby-clock", visible = true })
      for _, view in ipairs { "photos", "widgets", "world", "alarm", "clock" } do
        test.ipc("standby", view) test.settle(500)
        test.truthy(test.find { id = "standby-" .. view, visible = true }, "no " .. view)
      end
      test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
    end)
  end)
end

test.describe("eva-standby's way in", function()
  test.it("opens on any form, closes on a second call, and holds the screen awake", function()
    load { battery = "64", desk = true, size = { 1920, 1080 } }
    test.falsy(shown())
    test.ipc("standby", "toggle") test.settle(600)
    test.truthy(shown(), "the verb did not open it")
    test.truthy(test.ipc("awake", "state").on, "the screen may sleep under it")
    test.ipc("standby", "toggle") test.settle(600)
    test.falsy(shown())
    test.falsy(test.ipc("awake", "state").on, "the screen stayed held")
  end)

  test.it("ends with the power when asked to, and is red when asked to", function()
    load { battery = "64,charging", desk = true, size = { 1920, 1080 } }
    test.ipc("standby", "on", "when-charging", "night") test.settle(600)
    test.truthy(shown())
    test.truthy(test.ipc("standby", "state").night)
    test.ipc("fake-battery", "64") test.settle(600)
    test.falsy(shown(), "it outlived the power")
    test.falsy(test.ipc("standby", "state").night)
  end)

  test.it("shows eva-clock's cities and the next thing to ring", function()
    local state = morf.env("XDG_STATE_HOME") .. "/eva/clock"
    morf.fs.write(state .. "/world.json", morf.json.encode { { name = "Tirana", zone = "Europe/Tirane" } }, { parents = true })
    load {}
    test.ipc("standby", "world") test.settle(500)
    test.truthy(test.find { id = "standby-city-name-1", text = "Tirana", visible = true })
    morf.fs.remove(state .. "/world.json")
    test.ipc("standby", "alarm") test.settle(500)
    test.truthy(test.find { id = "standby-alarm-empty", visible = true })
  end)
end)

test.describe("when it shows", function()
  test.it("stays away off charge, upright, on a desk, or switched off", function()
    load { battery = "64" }
    test.falsy(shown(), "no charger")
    load { size = { 500, 1080 } }
    test.falsy(shown(), "upright")
    load { size = { 1920, 1080 }, desk = true }
    test.falsy(test.ipc("standby", "state").called, "a desk")
    load { settings = { desktop = { standby = false } } }
    test.falsy(shown(), "switched off")
  end)

  test.it("goes when sent away, and comes when asked", function()
    load {}
    test.truthy(shown())
    test.ipc("standby", "off") test.settle(200)
    test.falsy(shown())
    test.falsy(test.find { id = "standby", visible = true })
    test.ipc("standby", "on") test.settle(200)
    test.truthy(test.find { id = "standby", visible = true })
  end)

  test.it("follows a finger across the views and turns on the lift", function()
    load {}
    local on = { surface = "eva-standby" }
    local before = test.ipc("standby", "state").view
    test.touch("down", 0, 800, 250, on) test.advance(16)
    for i = 1, 10 do test.touch("move", 0, 800 - 30 * i, 250, on) test.advance(16) end
    test.eq(test.ipc("standby", "state").view, before, "the view waits for the lift")
    test.touch("up", 0, 500, 250, on) test.settle(300)
    test.eq(test.ipc("standby", "state").view, "photos")
    test.falsy(test.find { id = "standby-close", visible = true }, "a swipe is no touch for the way out")
    test.eq(test.logs("error"), {})
  end)

  test.it("turns the view on a swipe and offers the way out on a touch", function()
    load {}
    test.drag({ 800, 250 }, { 500, 250 }, { steps = 6, surface = "eva-standby" })
    test.settle(200)
    test.eq(test.ipc("standby", "state").view, "photos")
    test.click(540, 250, { surface = "eva-standby" })
    test.settle(200)
    test.truthy(test.find { id = "standby-close", visible = true }, "no way out")
    test.click("standby-close") test.settle(200)
    test.falsy(shown())
  end)

  test.it("turns dim and red at night", function()
    load { clock = "23:30" }
    test.truthy(test.ipc("standby", "state").night)
    load { clock = "12:00" }
    test.falsy(test.ipc("standby", "state").night)
  end)
end)
