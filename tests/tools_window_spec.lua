-- The Tools window: the same window as Settings on a book of its own, every
-- tool a page. Over everything in the middle of a desk, the whole of a phone;
-- shut by Escape, a press on the dim and its close control; one of the two
-- windows open at a time; landing at once under Reduce motion; open again where
-- it was after the shell is built again in place; and nothing of a tool loaded
-- before its page opens.
--
--     morf test --no-dbus tests/tools_window_spec.lua
local test = morf.test
local FRAME = 16

local SOURCE = [[
  require("init")
  morf.ipc.window_state = function()
    local tools, settings = require("tools_model"), require("utilities")
    return { open = tools.opened:get(), page = tools.detail:get(), settings = settings.opened:get(),
      keyboard = morf.surface.keyboard_focus }
  end
  morf.ipc.q_loaded = function(name) return package.loaded[name] ~= nil end
  morf.ipc.q_hold = function() require("themes.session").hold() return true end
]]

local serial = 0
local function load(style, size, values, extra)
  serial = serial + 1
  local appearance = morf.env("XDG_CACHE_HOME") .. "/tools-appearance-" .. serial .. ".json"
  morf.fs.write(appearance, morf.json.encode(values or {}))
  if serial == 1 then test.stub_run("task", { code = 0, stdout = "[]" }) end
  local env = { EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_APPEARANCE = appearance, EVA_WALLPAPER = "",
    EVA_FONT_FILE = "", LULE_A = "/nonexistent/lule", HOME = morf.env("XDG_CACHE_HOME"),
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/tools-" .. serial .. ".json" }
  for key, value in pairs(extra or {}) do env[key] = value end
  test.load("../shell/init.lua", { size = size or { 1600, 1000 }, source = SOURCE, env = env })
  test.settle(1200)
  return env
end
local function state() return test.ipc("window_state") end
local function window() return test.get("tools-window") end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " the Tools window", function()
    test.it("is not built until it opens", function()
      load(style)
      test.falsy(state().open)
      test.falsy(test.find { id = "tools-window-content" }, "its content was made at start")
      test.ipc("tools", "home") test.settle(1200)
      test.truthy(test.find { id = "tools-window-content", visible = true })
      test.eq(#test.logs("error"), 0)
    end)

    test.it("stands in the middle of a desk, seven tenths of it, over the dimmed screen", function()
      load(style)
      test.ipc("tools", "home") test.settle(1200)
      test.truthy(state().open)
      local box = window()
      test.eq({ box.x, box.y, box.width, box.height }, { 240, 150, 1120, 700 })
      local scrim = test.get("tools-scrim")
      test.eq({ scrim.x, scrim.y, scrim.width, scrim.height }, { 0, 0, 1600, 1000 })
      test.eq(state().keyboard, "exclusive")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("fills a phone", function()
      load(style, { 412, 915 })
      test.ipc("tools", "home") test.settle(1200)
      local box = window()
      test.eq({ box.x, box.y, box.width, box.height }, { 0, 0, 412, 915 })
      test.eq(#test.logs("error"), 0)
    end)

    test.it("shuts on Escape, on a press around it and from its close control", function()
      load(style)
      for _, how in ipairs { "escape", "outside", "close" } do
        test.ipc("tools", "home") test.settle(1200)
        test.truthy(state().open, how)
        if how == "escape" then test.key("Escape")
        elseif how == "outside" then test.click(60, 500)
        else test.click("tools-close") end
        test.settle(1200)
        test.falsy(state().open, how .. " left it open")
        test.falsy(test.find { id = "tools-window", visible = true }, how .. " left it drawn")
      end
      test.eq(#test.logs("error"), 0)
    end)

    test.it("is one of the two windows open at a time", function()
      load(style)
      test.ipc("settings", "bluetooth") test.settle(1200)
      test.truthy(state().settings)
      test.ipc("tools", "home") test.settle(1200)
      test.truthy(state().open)
      test.falsy(state().settings, "Settings stayed open under Tools")
      test.falsy(test.find { id = "settings-window", visible = true })
      test.ipc("settings", "network") test.settle(1200)
      test.truthy(state().settings)
      test.falsy(state().open, "Tools stayed open under Settings")
      test.ipc("tools", "close") test.settle(600)
      test.truthy(state().settings, "shutting Tools shut Settings")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("a category's page, and Back to the home", function()
      load(style)
      test.ipc("tools", "home/screen") test.settle(1200)
      test.eq(state().page, "home/screen")
      test.ipc("tools", "home") test.settle(900)
      test.eq(state().page, "home")
      test.key("Escape") test.settle(900)
      test.falsy(state().open)
    end)

    test.it("finds a tool from its search, and goes back from it", function()
      load(style)
      test.ipc("tools", "home") test.settle(1500)
      test.type("stopwatch") test.settle(400)
      test.truthy(test.find { id = "tools-hit-1", visible = true }, "the search found nothing")
      test.key("Return") test.settle(1200)
      test.eq(state().page, "clock")
      test.key("Left", "alt") test.settle(900)
      test.eq(state().page, "home", "Alt+Left did not go back")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("goes back a page at a time on a phone", function()
      load(style, { 412, 915 })
      test.ipc("tools", "home/time") test.settle(1200)
      test.click("tools-open-clock") test.settle(1200)
      test.eq(state().page, "clock")
      test.click("tools-back") test.settle(1200)
      test.eq(state().page, "home/time")
      test.click("tools-back") test.settle(1200)
      test.eq(state().page, "home")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("lands at once under Reduce motion, and leaves the same way", function()
      load(style, nil, { reduce_motion = true })
      test.ipc("tools", "home")
      test.advance(2 * FRAME)
      test.near(window().opacity, 1, 0.001, "it travelled")
      test.ipc("tools", "close")
      test.advance(2 * FRAME)
      test.falsy(window().visible, "it lingered")
    end)

    test.it("holds still once it has arrived", function()
      load(style)
      test.ipc("tools", "home")
      test.advance(10000)
      test.truthy(test.settle(2000) <= 2 * FRAME, "something still moves at rest")
    end)

    test.it("is open again, on its page, after the shell is built again in place", function()
      local env = load(style)
      test.ipc("tools", "home/system") test.settle(1200)
      local kept = ("local env = morf.env local kept = %s morf.env = function(name) "
        .. "if kept[name] ~= nil then return kept[name] end return env(name) end\n"):format(
        "{ EVA_SETTINGS = " .. ("%q"):format(env.EVA_SETTINGS) .. ", EVA_STYLE = " .. ("%q"):format(style)
          .. ", EVA_DRY_RUN = \"1\", EVA_APPEARANCE = " .. ("%q"):format(env.EVA_APPEARANCE) .. " }")
      test.ipc("q_hold")
      test.truthy(test.reload { source = kept .. SOURCE }, "the reload failed")
      test.settle(1400)
      test.truthy(state().open, "it shut in the rebuild")
      test.eq(state().page, "home/system", "it lost its place")
      test.eq(#test.logs("error"), 0)
    end)
  end)
end
