-- StandBy: on charge and sideways, a phone or tablet is a bedside screen.
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
      for _, view in ipairs { "photos", "widgets", "clock" } do
        test.ipc("standby", view) test.settle(500)
        test.truthy(test.find { id = "standby-" .. view, visible = true }, "no " .. view)
      end
      test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
    end)
  end)
end

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
