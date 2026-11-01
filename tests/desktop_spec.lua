-- The widgets on the desktop: the board they share with the quick settings, how
-- a person arranges them, where they live, and what a picture does to them.
--
--     morf test --no-dbus tests/desktop_spec.lua
local test = morf.test
local ROOT = morf.fs.join(morf.env("PWD") or ".", "tests/fixtures/wallpapers")

local SOURCE = [[
  require("init")
  local config = require("config")
  local model = require("desktop_model")
  local quiet = require("wallpaper_quiet")
  morf.ipc.d_form = function() return require("responsive").form() end
  morf.ipc.d_layout = function() return model.layout() end
  morf.ipc.d_get = function(key) return config.get(key) end
  morf.ipc.d_set = function(key, value) return config.set(key, value) end
  morf.ipc.d_shown = function()
    local out = {}
    for i, item in ipairs(model.board.shown()) do out[i] = item.id end
    return out
  end
  morf.ipc.d_spare = function()
    local out = {}
    for i, item in ipairs(model.board.spare()) do out[i] = item.id end
    return out
  end
  morf.ipc.d_small = function(id) return model.board.small(id) end
  morf.ipc.d_days = function(date, now) return model.days_until(date, now) end
  morf.ipc.d_quote = function(day) return model.quote(day) end
  morf.ipc.d_move = function(id, x, y) return model.move_to(id, x, y) end
  morf.ipc.d_reading = function() return quiet.reading:get() ~= false end
  morf.ipc.d_quiet = function(cols, rows, values)
    local reading = quiet.read_cells(values, cols, rows)
    local x, y = quiet.quietest(reading, 0.25, 0.25, 0)
    return { x = x, y = y }
  end
  morf.ipc.d_feed = function(cols, rows, values) quiet.reading:set(quiet.read_cells(values, cols, rows)) end
  morf.ipc.d_output = function() return model.command_output:get() end
]]

local serial = 0
local function load(spec)
  spec = spec or {}
  serial = serial + 1
  local cache = morf.env("XDG_CACHE_HOME")
  local env = { EVA_DRY_RUN = spec.live and "0" or "1", EVA_STYLE = spec.style or "material", EVA_WALLPAPER = "",
    EVA_SETTINGS = cache .. "/desktop-settings-" .. serial .. ".json",
    EVA_APPEARANCE = cache .. "/desktop-appearance-" .. serial .. ".json",
    LULE_A = "/nonexistent/lule", HOME = cache, EVA_FAKE_HARDWARE = "1",
    EVA_INPUT_DEVICES = spec.touch and (morf.env("PWD") .. "/tests/fixtures/input-devices-touch") or nil }
  morf.fs.write(env.EVA_SETTINGS, morf.json.encode(spec.settings or {}))
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { source = SOURCE, size = spec.size or { 1600, 1000 }, env = env })
  test.settle(1500)
end

local function painted(desktop)
  return { wallpaper = { draw = true, path = ROOT .. "/dusk.png" }, desktop = desktop or {} }
end

local ALL = { "clock", "date", "weather", "system", "media", "visualiser", "calendar", "quote", "command", "note",
  "countdown", "photo", "orb" }

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " desktop", function()
    test.it("builds every widget large and small without an error", function()
      load { style = style, settings = painted { widgets = { desk = ALL } } }
      test.settle(600)
      for _, id in ipairs(ALL) do
        test.truthy(test.find { id = "desktop-widget-" .. id, visible = true }, "no " .. id .. " on the desktop")
      end
      test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
      for _, id in ipairs(ALL) do test.ipc("desktop", "size", id) end
      test.settle(600)
      for _, id in ipairs(ALL) do
        test.truthy(test.find { id = "desktop-widget-" .. id, visible = true }, id .. " went at its small size")
      end
      test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
    end)

    test.it("hides and adds through the board and keeps the form's own list", function()
      load { style = style, settings = painted { widgets = { desk = { "clock", "date" } } } }
      test.eq(test.ipc("d_shown"), { "clock", "date" })
      test.ipc("desktop", "edit") test.settle(400)
      test.truthy(test.find { id = "desktop-done", visible = true }, "no way out of arranging")
      test.click("desktop-hide-date") test.settle(400)
      test.eq(test.ipc("d_shown"), { "clock" })
      test.falsy(test.find { id = "desktop-widget-date", visible = true }, "a hidden widget stayed")
      test.click("desktop-add-weather") test.settle(400)
      test.eq(test.ipc("d_shown"), { "clock", "weather" })
      test.eq(test.ipc("d_get", "desktop.widgets.phone"), {}, "the phone's list moved with the desk's")
      test.click("desktop-size-clock") test.settle(400)
      test.truthy(test.ipc("d_small", "clock"))
      test.click("desktop-done") test.settle(200)
      test.falsy(test.find { id = "desktop-done", visible = true }, "arranging did not end")
    end)

    test.it("moves a widget by dragging it, snapped to the grid, and remembers", function()
      load { style = style, settings = painted { widgets = { desk = { "clock" } } } }
      test.ipc("desktop", "edit") test.settle(400)
      local before = test.ipc("d_layout").clock
      test.drag({ before.x + 180, before.y + 88 }, { before.x - 420, before.y + 288 },
        { steps = 10, surface = "eva-wallpaper" })
      test.settle(500)
      local after = test.ipc("d_layout").clock
      test.near(after.x, before.x - 600, 8)
      test.near(after.y, before.y + 200, 8)
      test.eq(after.x % 8, 0, "not on the grid")
      test.eq(after.y % 8, 0, "not on the grid")
      local saved = test.ipc("d_get", "desktop.place.desk")
      test.eq(#saved, 1)
      test.eq(saved[1].id, "clock")
    end)

    test.it("offers every widget on the Desktop page", function()
      load { style = style, settings = painted() }
      test.ipc("settings", "theme/desktop") test.settle(2500)
      test.click("desktop-switch-clock") test.settle(300)
      test.eq(test.ipc("d_shown"), { "clock" })
      test.truthy(test.find { id = "desktop-widget-clock", visible = true })
      test.click("desktop-chrome-solid") test.settle(100)
      test.eq(test.ipc("d_get", "desktop.chrome"), "solid")
      test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
    end)
  end)
end

test.describe("where they live", function()
  test.it("rides the wallpaper's layer where Eva paints, and has its own otherwise", function()
    load { settings = painted { widgets = { desk = { "clock" } } } }
    test.eq(test.ipc("desktop", "state").host, "wallpaper")
    test.truthy(test.find { id = "desktop-widget-clock", visible = true })
    test.ipc("d_set", "wallpaper.draw", false) test.settle(300)
    test.eq(test.ipc("desktop", "state").host, "own")
    test.truthy(test.find { id = "desktop-widget-clock", visible = true }, "the widgets went with the layer")
    test.ipc("d_set", "wallpaper.draw", true) test.settle(300)
    test.eq(test.ipc("desktop", "state").host, "wallpaper")
    test.truthy(test.find { id = "desktop-widget-clock", visible = true })
    test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
  end)

  test.it("opens nothing with no widgets and no picture of its own", function()
    load { settings = { wallpaper = { path = ROOT .. "/dusk.png" } } }
    test.falsy(test.find { id = "desktop", visible = true })
  end)
end)

test.describe("on a phone and a tablet", function()
  test.it("flows down a phone, two small to a row, in the board's order", function()
    load { size = { 412, 915 }, touch = true,
      settings = painted { widgets = { phone = { "clock", "date", "weather", "media" } }, small = { phone = { "date", "weather" } } } }
    test.eq(test.ipc("d_form"), "phone")
    local layout = test.ipc("d_layout")
    test.truthy(layout.clock.width > layout.date.width, "the large one is no wider")
    test.eq(layout.date.y, layout.weather.y, "two small did not share a row")
    test.truthy(layout.weather.x > layout.date.x)
    test.truthy(layout.media.y > layout.weather.y)
  end)

  test.it("keeps a tablet's own board, placed by hand", function()
    load { size = { 1280, 800 }, touch = true, settings = painted { widgets = { tablet = { "clock" }, desk = { "date" } } } }
    test.eq(test.ipc("d_form"), "tablet")
    test.eq(test.ipc("d_shown"), { "clock" })
    test.ipc("d_move", "clock", 200, 200)
    test.settle(100)
    test.eq(#test.ipc("d_get", "desktop.place.tablet"), 1)
    test.eq(#test.ipc("d_get", "desktop.place.desk"), 0)
  end)
end)

test.describe("the picture", function()
  test.it("finds the quietest part of a reading", function()
    load {}
    local cols, rows, values = 8, 8, {}
    for y = 0, rows - 1 do
      for x = 0, cols - 1 do
        -- A checkerboard everywhere but the lower right.
        values[#values + 1] = (x >= 4 and y >= 4) and 0.5 or ((x + y) % 2 == 0 and 1 or 0)
      end
    end
    local at = test.ipc("d_quiet", cols, rows, values)
    test.truthy(at.x >= 0.5 and at.y >= 0.5, ("quiet at %.2f, %.2f"):format(at.x, at.y))
  end)

  test.it("moves the clock to the quiet part, and leaves it alone while arranging", function()
    load { settings = painted { quiet_clock = true, widgets = { desk = { "clock" } } } }
    local cols, rows, values = 8, 8, {}
    for y = 0, rows - 1 do
      for x = 0, cols - 1 do values[#values + 1] = (x >= 4 and y >= 4) and 0.5 or ((x + y) % 2 == 0 and 1 or 0) end
    end
    test.ipc("d_feed", cols, rows, values)
    test.settle(900)
    local tile = test.get { id = "desktop-tile-clock" }
    test.truthy(tile.x > 800, "the clock stayed at " .. tostring(tile.x))
    test.truthy(tile.y > 400, "the clock stayed at " .. tostring(tile.y))
  end)

  test.it("reads a real picture", function()
    load { settings = painted { widgets = { desk = { "clock" } } } }
    test.wait(function() test.advance(16) return test.ipc("d_reading") end, 3000, "the picture was never read")
  end)
end)

test.describe("what widgets say", function()
  test.it("counts the days to a date", function()
    load {}
    test.eq(test.ipc("d_days", "2026-11-11", "2026-11-01"), 10)
    test.eq(test.ipc("d_days", "2026-10-31", "2026-11-01"), -1)
    test.eq(test.ipc("d_days", "2027-01-01", "2026-11-01"), 61)
    test.eq(test.ipc("d_days", "soon", "2026-11-01"), nil)
  end)

  test.it("takes its quotes from a file, and keeps its own without one", function()
    local file = morf.env("XDG_CACHE_HOME") .. "/quotes.txt"
    morf.fs.write(file, "one\ntwo\n")
    load { settings = { desktop = { quotes = file } } }
    test.eq(test.ipc("d_quote", 0), "one")
    test.eq(test.ipc("d_quote", 1), "two")
    test.ipc("d_set", "desktop.quotes", "")
    test.truthy(#test.ipc("d_quote", 0) > 8)
  end)

  test.it("runs the custom command while it is shown, and stops", function()
    test.stub_run("sh", { code = 0, stdout = "up 3 days\n" })
    load { live = true, settings = { appearance = { sync = false },
      desktop = { widgets = { desk = { "command" } }, command = { run = "uptime -p", interval = 30 } } } }
    test.wait(function() test.advance(16) return test.ipc("d_output") == "up 3 days" end, 3000, "the command never answered")
    test.ipc("desktop", "hide", "command") test.advance(32)
    test.eq(test.ipc("d_output"), "")
  end)
end)
