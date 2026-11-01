-- A phone's and a tablet's home: pages of apps and widgets on the desktop's own
-- board, the dock's row on a phone, a hold to arrange, and a desk left as it was.
-- Every finger here goes through morf's touch path.
--
--     morf test --no-dbus tests/home_spec.lua
local test = morf.test
local host = assert(load(morf.fs.read(morf.env("PWD") .. "/tests/fixtures/launcher_host.lua")))()

local PHONE, TABLET, DESK = { 620, 1380 }, { 1280, 800 }, { 1440, 900 }
local TOUCH = morf.env("PWD") .. "/tests/fixtures/input-devices-touch"
local COVER = morf.env("PWD") .. "/tests/fixtures/input-devices-cover"
local WALL = morf.fs.join(morf.env("PWD") or ".", "tests/fixtures/wallpapers/dusk.png")
local SURFACE = { surface = "eva-wallpaper" }

local SOURCE = [==[
  morf.ipc.layout = function() return require("desktop_model").layout() end
  morf.ipc.pages = function() return require("desktop_model").page_count() end
  morf.ipc.form = function() return require("responsive").form() end
  morf.ipc.dock_mode = function() return require("dock_model").mode() end
  morf.ipc.dock_shown = function() return require("dock").shown() end
  morf.ipc.dock_rows = function()
    local out = {}
    for i = 1, require("dock_model").rows:len() do out[i] = require("dock_model").rows:get(i).key end
    return out
  end
  morf.ipc.editing = function() return require("desktop_model").editing() end
  morf.ipc.home_on = function(on) require("config").set("desktop.home.enabled", on) return true end
]==]

local function load(size, devices, settings, style)
  settings = settings or {}
  settings.wallpaper = { draw = true, path = WALL }
  host.load { size = size, style = style, settings = settings, source_extra = SOURCE,
    env = { EVA_INPUT_DEVICES = devices, EVA_WALLPAPER = WALL } }
  test.ipc("close") test.settle(500)
end

local function page_of(id) return test.ipc("layout")[id].page end

local function swipe(from_x, to_x, y)
  test.swipe({ from_x, y }, { to_x, y }, { duration = 200, surface = SURFACE.surface })
  test.settle(700)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " a phone's home", function()
    test.it("stands apps among the widgets, on the page's own board", function()
      load(PHONE, TOUCH, { desktop = { widgets = { phone = { "clock", "app:fixture-editor", "app:fixture-browser" } } } }, style)
      test.eq(test.ipc("form"), "phone")
      local layout = test.ipc("layout")
      test.truthy(layout["app:fixture-editor"].y > layout.clock.y, "an icon stands on a widget")
      test.eq(layout["app:fixture-editor"].y, layout["app:fixture-browser"].y, "two icons did not share a row")
      test.truthy(layout["app:fixture-browser"].x > layout["app:fixture-editor"].x)
      test.truthy(test.find { id = "desktop-icon-name-app:fixture-editor", visible = true }, "the icon is not drawn")
      test.eq(test.logs("error"), {})
    end)

    test.it("opens an app with a press", function()
      load(PHONE, TOUCH, { desktop = { widgets = { phone = { "app:fixture-editor" } } } }, style)
      local icon = test.get { id = "desktop-icon-app:fixture-editor" }
      test.touch("down", 0, icon.x + icon.width / 2, icon.y + icon.height / 2, SURFACE) test.advance(50)
      test.touch("up", 0, icon.x + icon.width / 2, icon.y + icon.height / 2, SURFACE) test.settle(300)
      test.truthy(host.logged("launch fixture-editor"), "a press did not start it")
    end)

    test.it("offers an app's actions from a hold, and a hold on bare wallpaper arranges", function()
      load(PHONE, TOUCH, { desktop = { widgets = { phone = { "app:fixture-browser" } } } }, style)
      local icon = test.get { id = "desktop-icon-app:fixture-browser" }
      local x, y = icon.x + icon.width / 2, icon.y + icon.height / 2
      test.touch("down", 0, x, y, SURFACE) test.advance(700)
      test.touch("up", 0, x, y, SURFACE) test.settle(300)
      test.truthy(test.find { id = "desktop-icon-menu", visible = true }, "a hold offered nothing")
      test.truthy(test.find { text = "New Window", visible = true }, "its own actions are missing")
      test.truthy(test.find { text = "Take off the home screen", visible = true })
      test.key("Escape") test.settle(300)
      test.touch("down", 0, 300, 1000, SURFACE) test.advance(700)
      test.touch("up", 0, 300, 1000, SURFACE) test.settle(300)
      test.truthy(test.ipc("editing"), "a hold did not arrange")
      test.truthy(test.find { id = "desktop-done", visible = true })
      test.touch("down", 0, 300, 1000, SURFACE) test.advance(30)
      test.touch("up", 0, 300, 1000, SURFACE) test.settle(300)
      test.falsy(test.ipc("editing"), "a tap on the bare page left it arranging")
    end)

    test.it("a locked layout keeps a hold from arranging", function()
      load(PHONE, TOUCH, { desktop = { home = { locked = true } } }, style)
      test.touch("down", 0, 300, 1000, SURFACE) test.advance(700)
      test.touch("up", 0, 300, 1000, SURFACE) test.settle(300)
      test.falsy(test.ipc("editing"), "a locked layout was arranged")
      test.truthy(test.find { id = "desktop-menu", visible = true }, "the menu still offers it")
    end)

    test.it("slides between pages under a finger, and the dots follow", function()
      load(PHONE, TOUCH, { desktop = { widgets = { phone = { "clock" } },
        pages = { phone = { { "app:fixture-editor" }, { "date" } } } } }, style)
      test.eq(test.ipc("pages"), 3)
      test.eq(page_of("app:fixture-editor"), 2)
      test.truthy(test.find { id = "desktop-dots", visible = true }, "no dots")
      local track = test.get("desktop-track")
      test.near(track.x, 0, 2)
      swipe(520, 100, 1000)
      test.eq(test.ipc("desktop", "state").page, 2, "a swipe did not turn the page")
      test.near(test.get("desktop-track").x, -PHONE[1], 2, "the track did not come to rest on the page")
      swipe(520, 100, 1000)
      test.eq(test.ipc("desktop", "state").page, 3)
      swipe(100, 520, 1000)
      test.eq(test.ipc("desktop", "state").page, 2)
      test.touch("down", 0, 300, 1000, SURFACE) test.advance(16)
      test.touch("move", 0, 400, 1000, SURFACE) test.advance(16)
      test.touch("move", 0, 500, 1000, SURFACE) test.advance(16)
      test.touch("cancel", 0, 500, 1000, SURFACE) test.settle(500)
      test.eq(test.ipc("desktop", "state").page, 2, "a cancelled drag moved the page")
    end)

    test.it("swiping starts no hold, and a slight move does not turn a page", function()
      load(PHONE, TOUCH, { desktop = { pages = { phone = { { "date" } } } } }, style)
      swipe(520, 100, 1000)
      test.falsy(test.ipc("editing"), "a swipe arranged the home")
      test.eq(test.ipc("desktop", "state").page, 2)
    end)

    test.it("carries an icon to the next page by holding it at the side", function()
      load(PHONE, TOUCH, { desktop = { widgets = { phone = { "app:fixture-editor", "app:fixture-browser" } } } }, style)
      test.ipc("desktop", "edit") test.settle(400)
      local tile = test.get("desktop-tile-app:fixture-editor")
      local x, y = tile.x + tile.width / 2, tile.y + tile.height / 2
      test.touch("down", 0, x, y, SURFACE) test.advance(300)
      for i = 1, 16 do test.touch("move", 0, x + (PHONE[1] - 8 - x) * i / 16, y, SURFACE) test.advance(16) end
      test.advance(700)
      test.touch("up", 0, PHONE[1] - 8, y, SURFACE) test.settle(600)
      test.eq(test.ipc("pages"), 2, "no new page was made")
      test.eq(page_of("app:fixture-editor"), 2, "it stayed on its page")
      test.eq(page_of("app:fixture-browser"), 1)
      test.eq(test.ipc("desktop", "state").page, 2, "the view stayed behind")
    end)

    test.it("reorders by carrying, and drops an empty page when done", function()
      load(PHONE, TOUCH, { desktop = { widgets = { phone = { "app:fixture-editor", "app:fixture-browser" } } } }, style)
      test.ipc("desktop", "new-page") test.settle(200)
      test.eq(test.ipc("pages"), 2)
      test.ipc("desktop", "edit") test.settle(400)
      local a, b = test.get("desktop-tile-app:fixture-editor"), test.get("desktop-tile-app:fixture-browser")
      local x, y = a.x + a.width / 2, a.y + a.height / 2
      test.touch("down", 0, x, y, SURFACE) test.advance(300)
      for i = 1, 12 do test.touch("move", 0, x + (b.x - a.x) * i / 12, y, SURFACE) test.advance(16) end
      test.touch("up", 0, x + b.x - a.x, y, SURFACE) test.settle(500)
      test.eq(test.ipc("desktop", "state").shown, { "app:fixture-browser", "app:fixture-editor" }, "the carry changed nothing")
      local done = test.get("desktop-done")
      test.click(done.x + done.width / 2, done.y + done.height / 2, SURFACE) test.settle(300)
      test.falsy(test.ipc("editing"))
      test.eq(test.ipc("pages"), 1, "an empty page stayed")
    end)

    test.it("adds from the launcher: its grid while arranging, its hold's place otherwise", function()
      load(PHONE, TOUCH, nil, style)
      test.ipc("desktop", "edit") test.settle(300)
      test.ipc("launcher", "open") test.settle(700)
      local tile = test.get { text = "Fixture Browser", visible = true }
      test.click(tile.x + tile.width / 2, tile.y - 12) test.settle(500)
      test.truthy(test.ipc("layout")["app:fixture-browser"], "a press while arranging did not place it")
      test.falsy(host.logged("launch fixture-browser"), "it started the app instead")
      test.ipc("desktop", "done") test.settle(300)
      test.ipc("launcher", "open") test.settle(700)
      tile = test.get { text = "Fixture Editor", visible = true }
      local x, y = tile.x + tile.width / 2, tile.y - 12
      test.touch("down", 0, x, y) test.advance(700)
      local place = test.get("launcher-home-target")
      local to_x, to_y = place.x + place.width / 2, place.y + place.height / 2
      for i = 1, 12 do test.touch("move", 0, x + (to_x - x) * i / 12, y + (to_y - y) * i / 12) test.advance(16) end
      test.touch("up", 0, to_x, to_y) test.settle(400)
      test.truthy(test.ipc("layout")["app:fixture-editor"], "the place over the grid did not put it home")
    end)

    test.it("takes a page's overflow onto a new page", function()
      local many = { "clock", "weather", "media", "system", "calendar", "quote", "photo" }
      load(PHONE, TOUCH, { desktop = { widgets = { phone = many } } }, style)
      test.ipc("desktop", "app", "fixture-browser") test.settle(300)
      local spot = test.ipc("layout")["app:fixture-browser"]
      test.truthy(spot.y + 104 <= PHONE[2] - 40, "it was put past the page's foot")
    end)

    test.it("an app gone from the machine goes from the page", function()
      load(PHONE, TOUCH, { desktop = { widgets = { phone = { "app:nothing-installed", "app:fixture-editor" } } } }, style)
      test.falsy(test.ipc("layout")["app:nothing-installed"], "a ghost stands on the page")
      test.truthy(test.ipc("layout")["app:fixture-editor"])
    end)

    test.it("opens a folder on the home in the launcher's grid", function()
      load(PHONE, TOUCH, { launcher = { folders = { { name = "Work", apps = { "fixture-editor" } } } },
        desktop = { widgets = { phone = { "folder:Work" } } } }, style)
      local icon = test.get { id = "desktop-icon-folder:Work" }
      test.touch("down", 0, icon.x + 20, icon.y + 20, SURFACE) test.advance(50)
      test.touch("up", 0, icon.x + 20, icon.y + 20, SURFACE) test.settle(700)
      test.eq(test.ipc("state").folder, "Work")
      test.truthy(test.ipc("state").open)
    end)

    test.it("keeps the pinned apps in a row on the home, gone under a window", function()
      load(PHONE, TOUCH, { dock = { pins = { "fixture-browser" } } }, style)
      test.eq(test.ipc("dock_mode"), "hotseat")
      test.truthy(test.ipc("dock_shown"), "no row on an empty home")
      test.eq(test.ipc("dock_rows"), { "eva:launcher", "fixture-browser" }, "running apps have no place on it")
      local button = test.get("dock-icon-area-1")
      test.touch("down", 0, button.x + 10, button.y + 10) test.advance(40)
      test.touch("up", 0, button.x + 10, button.y + 10) test.settle(700)
      test.truthy(test.ipc("state").open, "its first button did not open the grid")
      test.falsy(test.ipc("dock_shown"), "it stands over the open launcher")
    end)

    test.it("a phone's row goes with its setting", function()
      load(PHONE, TOUCH, { desktop = { home = { dock = false } } }, style)
      test.eq(test.ipc("dock_mode"), "off")
    end)
  end)

  test.describe(style .. " a tablet's home", function()
    test.it("has pages and keeps its taskbar", function()
      load(TABLET, TOUCH, { desktop = { widgets = { tablet = { "clock", "app:fixture-editor" } },
        pages = { tablet = { { "app:fixture-browser" } } } } }, style)
      test.eq(test.ipc("form"), "tablet")
      test.eq(test.ipc("dock_mode"), "taskbar")
      test.eq(test.ipc("pages"), 2)
      swipe(1100, 300, 700)
      test.eq(test.ipc("desktop", "state").page, 2)
    end)

    test.it("still places by hand, icons too", function()
      load(TABLET, TOUCH, { desktop = { widgets = { tablet = { "clock", "app:fixture-editor" } } } }, style)
      local first = test.ipc("layout")["app:fixture-editor"]
      test.ipc("desktop", "edit") test.settle(400)
      local tile = test.get("desktop-tile-app:fixture-editor")
      local x, y = tile.x + tile.width / 2, tile.y + tile.height / 2
      test.touch("down", 0, x, y, SURFACE) test.advance(300)
      for i = 1, 10 do test.touch("move", 0, x + 20 * i, y + 16 * i, SURFACE) test.advance(16) end
      test.touch("up", 0, x + 200, y + 160, SURFACE) test.settle(500)
      local now = test.ipc("layout")["app:fixture-editor"]
      test.truthy(now.x > first.x + 100, "it did not move")
      test.truthy(#test.ipc("setting", "desktop.place.tablet") >= 1, "the place was not kept")
    end)
  end)

  test.describe(style .. " a desk", function()
    test.it("stays as it was, with a touchscreen and a keyboard on it", function()
      load(DESK, COVER, { desktop = { widgets = { desk = { "clock" } } } }, style)
      test.eq(test.ipc("form"), "desk")
      test.eq(test.ipc("pages"), 1)
      test.eq(test.ipc("dock_mode"), "off")
      test.falsy(test.find { id = "desktop-dots", visible = true })
      swipe(1200, 300, 500)
      test.eq(test.ipc("desktop", "state").page, 1, "a desk turned a page")
      test.touch("down", 0, 300, 800, SURFACE) test.advance(700)
      test.touch("up", 0, 300, 800, SURFACE) test.settle(300)
      test.falsy(test.ipc("editing"), "a desk's hold still opens its menu")
      test.truthy(test.find { id = "desktop-menu", visible = true })
      test.ipc("launcher", "open") test.settle(600)
      test.eq(test.ipc("state").mode, "apps", "the launcher left its list")
      test.eq(test.logs("error"), {})
    end)

    test.it("offers no home in an app's actions", function()
      load(DESK, COVER, nil, style)
      test.ipc("launcher", "open") test.settle(600)
      host.search("fixture editor")
      test.falsy((function()
        for _, name in ipairs(test.ipc("act_names")) do if name:find("home screen", 1, true) then return true end end
      end)(), "a desk offered a home")
    end)
  end)
end

test.it("a home turned off leaves one page of widgets, and keeps the rest for later", function()
  load(TABLET, TOUCH, { desktop = { pages = { tablet = { { "app:fixture-editor" } } } } })
  test.eq(test.ipc("pages"), 2)
  test.ipc("home_on", false) test.settle(300)
  test.eq(test.ipc("pages"), 1, "a page outlived its home")
  test.falsy(test.ipc("layout")["app:fixture-editor"], "an icon outlived its home")
  test.ipc("home_on", true) test.settle(300)
  test.eq(test.ipc("pages"), 2, "its pages were lost")
end)
