-- The Settings window: over everything in the middle of a desk, seven tenths of
-- the screen, the rest dimmed; the whole of a phone; shut by Escape, a press
-- on the dimmed screen and its close control; coming and going in each theme's
-- motion, landing at once under Reduce motion, still at rest, and open again
-- where it was after the shell is built again in place.
--
--     morf test --no-dbus tests/settings_window_spec.lua
local test = morf.test
local FRAME = 16

local SOURCE = [[
  require("init")
  morf.ipc.window_state = function()
    local settings = require("utilities")
    return { open = settings.opened:get(), page = settings.detail:get(),
      sidebar = require("sidebar").drawer.open:get(), keyboard = morf.surface.keyboard_focus }
  end
  morf.ipc.q_hold = function() require("themes.session").hold() return true end
]]

local serial = 0
local function load(style, size, values, extra)
  serial = serial + 1
  local appearance = morf.env("XDG_CACHE_HOME") .. "/window-appearance-" .. serial .. ".json"
  morf.fs.write(appearance, morf.json.encode(values or {}))
  -- (Stubs last the file, and the verb that sets them does not last a reload.)
  if serial == 1 then test.stub_run("task", { code = 0, stdout = "[]" }) end
  local env = { EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_APPEARANCE = appearance, EVA_WALLPAPER = "",
    EVA_FONT_FILE = "", LULE_A = "/nonexistent/lule", HOME = morf.env("XDG_CACHE_HOME"),
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/window-" .. serial .. ".json" }
  for key, value in pairs(extra or {}) do env[key] = value end
  test.load("../shell/init.lua", { size = size or { 1600, 1000 }, source = SOURCE, env = env })
  test.settle(1200)
  return env
end
local function state() return test.ipc("window_state") end
local function window() return test.get("settings-window") end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " the Settings window", function()
    test.it("stands in the middle of a desk, seven tenths of it, over the panels and the dimmed screen", function()
      load(style)
      test.ipc("bar", "show", "on") test.settle(900)
      test.ipc("utilities", "open") test.settle(900)
      test.click("utilities-more-wifi") test.settle(1200)
      test.truthy(state().open)
      test.falsy(state().sidebar, "the panel stayed open under it")
      local box = window()
      test.eq({ box.x, box.y, box.width, box.height }, { 240, 150, 1120, 700 })
      local scrim = test.get("settings-scrim")
      test.eq({ scrim.x, scrim.y, scrim.width, scrim.height }, { 0, 0, 1600, 1000 }, "the dim does not cover the screen")
      local bar = test.get("bar")
      test.truthy(scrim.depth > bar.depth, "the bar stands over the dim")
      test.truthy(test.find { id = "network-page", visible = true })
      test.eq(state().keyboard, "exclusive")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("fills a phone", function()
      load(style, { 412, 915 })
      test.ipc("settings", "network") test.settle(1200)
      local box = window()
      test.eq({ box.x, box.y, box.width, box.height }, { 0, 0, 412, 915 })
      test.eq(#test.logs("error"), 0)
    end)

    test.it("shuts on Escape, on a press around it and from its close control", function()
      load(style)
      for _, how in ipairs { "escape", "outside", "close" } do
        test.ipc("settings", "bluetooth") test.settle(1200)
        test.truthy(state().open, how)
        if how == "escape" then test.key("Escape")
        elseif how == "outside" then test.click(60, 500)
        else test.click("settings-close") end
        test.settle(1200)
        test.falsy(state().open, how .. " left it open")
        test.falsy(test.find { id = "settings-window", visible = true }, how .. " left it drawn")
      end
      test.eq(#test.logs("error"), 0)
    end)

    test.it("a press inside it is no press outside", function()
      load(style)
      test.ipc("settings", "bluetooth") test.settle(1200)
      local box = window()
      test.click(box.x + box.width - 40, box.y + box.height - 20) test.settle(600)
      test.truthy(state().open, "a press on its empty corner shut it")
    end)

    test.it("gives way to a password prompt and comes back, and shuts for another panel", function()
      load(style)
      test.ipc("settings", "bluetooth") test.settle(1200)
      test.truthy(test.ipc("polkit", "demo")) test.settle(1200)
      test.truthy(state().open)
      test.falsy(test.find { id = "settings-window", visible = true }, "it stood over the prompt")
      test.ipc("polkit", "cancel") test.settle(1200)
      test.truthy(test.find { id = "settings-window", visible = true }, "it did not come back")
      test.ipc("launcher", "apps") test.settle(1200)
      test.falsy(state().open, "it stayed open over the launcher")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("is drawn while it leaves, and then not at all", function()
      load(style)
      test.ipc("settings", "bluetooth") test.settle(1500)
      test.near(window().opacity, 1, 0.001)
      test.ipc("settings", "close")
      test.advance(FRAME)
      test.truthy(window().visible, "it vanished at once")
      local leaving = window().opacity
      test.truthy(leaving > 0 and leaving < 1, "it did not fade on the way out")
      test.advance(1000)
      test.falsy(window().visible, "it stayed on screen after leaving")
    end)

    test.it("lands at once under Reduce motion", function()
      load(style, nil, { reduce_motion = true })
      test.ipc("settings", "bluetooth")
      test.advance(2 * FRAME)
      test.near(window().opacity, 1, 0.001, "it travelled")
      test.ipc("settings", "close")
      test.advance(2 * FRAME)
      test.falsy(window().visible, "it lingered")
    end)

    test.it("holds still once it has arrived", function()
      load(style)
      -- (A theme's finite pulses play out in the first seconds a page shows.)
      for _, page in ipairs { "home", "bluetooth", "bar/tray" } do
        test.ipc("settings", page)
        test.advance(10000)
        test.truthy(test.settle(2000) <= 2 * FRAME, "something still moves at rest on " .. page)
      end
    end)

    test.it("is open again, on its page, after the shell is built again in place", function()
      local env = load(style)
      test.ipc("settings", "bar/tray") test.settle(1200)
      local kept = ("local env = morf.env local kept = %s morf.env = function(name) "
        .. "if kept[name] ~= nil then return kept[name] end return env(name) end\n"):format(
        "{ EVA_SETTINGS = " .. ("%q"):format(env.EVA_SETTINGS) .. ", EVA_STYLE = " .. ("%q"):format(style)
          .. ", EVA_DRY_RUN = \"1\", EVA_APPEARANCE = " .. ("%q"):format(env.EVA_APPEARANCE) .. " }")
      test.ipc("q_hold")
      test.truthy(test.reload { source = kept .. SOURCE }, "the reload failed")
      test.settle(1400)
      test.truthy(state().open, "it shut in the rebuild")
      test.eq(state().page, "bar/tray", "it lost its place")
      test.truthy(test.find { id = "settings-detail-bar/tray", visible = true })
      test.eq(#test.logs("error"), 0)
    end)
  end)
end
