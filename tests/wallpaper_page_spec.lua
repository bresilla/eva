-- The wallpaper picker in the real shell: Lule's folder as a grid, a choice going
-- where the target says, the options, in both themes on a desk and a phone.
--
--     morf test --no-dbus tests/wallpaper_page_spec.lua
local test = morf.test
local ROOT = morf.fs.join(morf.env("PWD") or ".", "tests/fixtures/wallpapers")
local function picture(name) return ROOT .. "/" .. name .. ".png" end

local SOURCE = [[
  require("init")
  local config = require("config")
  local studio = require("lule_studio")
  local wallpaper = require("wallpaper")
  local model = require("wallpaper_model")
  morf.ipc.p_get = function(key) return config.get(key) end
  morf.ipc.p_files = function() return #studio.files:get() end
  morf.ipc.p_selected = function() return studio.selected:get() end
  morf.ipc.p_select = function(path) return studio.select(path) end
  morf.ipc.p_current = function() return wallpaper.current:get() end
  morf.ipc.p_picture = function() return wallpaper.picture() end
  morf.ipc.p_preview = function() return studio.preview:get() ~= "" end
  morf.ipc.p_target = function(value) model.target:set(value) end
  morf.ipc.p_favourite = function(path) return model.favourite(path) end
  morf.ipc.p_form = function() return require("responsive").form() end
]]

local serial = 0
local function load(spec)
  spec = spec or {}
  serial = serial + 1
  local cache = morf.env("XDG_CACHE_HOME")
  local env = { EVA_DRY_RUN = "1", EVA_STYLE = spec.style or "material", EVA_WALLPAPER = "",
    EVA_SETTINGS = cache .. "/page-settings-" .. serial .. ".json",
    EVA_APPEARANCE = cache .. "/page-appearance-" .. serial .. ".json",
    LULE_A = "/nonexistent/lule", HOME = cache,
    EVA_INPUT_DEVICES = spec.touch and (morf.env("PWD") .. "/tests/fixtures/input-devices-touch") or nil }
  morf.fs.write(env.EVA_SETTINGS, morf.json.encode { lule = { folder = ROOT },
    wallpaper = { draw = true, path = picture("dune"), transition = { kind = spec.kind or "circle" } } })
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { source = SOURCE, size = spec.size or { 1600, 1000 }, env = env })
  test.settle(1200)
  test.ipc("settings", "theme/wallpaper")
  test.settle(2500)
end

for _, style in ipairs { "material", "tsugumori" } do
  for _, size in ipairs { { name = "desk", size = { 1600, 1000 } }, { name = "phone", size = { 412, 915 }, touch = true } } do
    test.describe(style .. " on a " .. size.name, function()
      test.it("lists Lule's folder as a grid and says who paints", function()
        load { style = style, size = size.size, touch = size.touch }
        test.eq(test.ipc("p_files"), 6)
        test.truthy(test.find { id = "wallpaper-grid", visible = true }, "no grid")
        test.truthy(test.find { id = "wallpaper-apply", visible = true }, "no way to apply")
        test.click("wallpaper-tab-options") test.settle(400)
        test.truthy(test.find { id = "wallpaper-draw-subtitle", visible = true })
        test.truthy(test.get({ id = "wallpaper-draw-subtitle" }).text:find("Eva paints", 1, true), "it does not say who paints")
        test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
      end)
    end)
  end

  test.describe(style .. " choosing", function()
    test.it("previews without changing the desktop, then sets it", function()
      load { style = style }
      test.ipc("p_select", picture("forest"))
      test.wait(function() test.advance(16) return test.ipc("p_preview") end, 3000, "no preview")
      test.settle(900)
      test.eq(test.ipc("p_current"), picture("dune"), "browsing changed the desktop")
      test.click("wallpaper-apply") test.settle(200)
      test.eq(test.ipc("p_current"), picture("forest"))
    end)

    test.it("sets a screen's own picture from its target", function()
      load { style = style }
      test.click("wallpaper-target-output-HEADLESS-1") test.settle(100)
      test.ipc("p_select", picture("snow"))
      test.advance(32)
      test.click("wallpaper-apply") test.settle(200)
      test.eq(test.ipc("p_picture"), picture("snow"))
      test.eq(test.ipc("p_current"), picture("dune"))
    end)

    test.it("marks a favourite", function()
      load { style = style }
      test.ipc("p_select", picture("dusk")) test.advance(32)
      test.click("wallpaper-favourite") test.advance(32)
      test.truthy(test.ipc("p_favourite", picture("dusk")))
      test.click("wallpaper-favourite") test.advance(32)
      test.falsy(test.ipc("p_favourite", picture("dusk")))
    end)

    test.it("keeps its options in the settings", function()
      load { style = style }
      test.click("wallpaper-tab-options") test.settle(400)
      test.click("wallpaper-transition-wipe") test.settle(100)
      test.eq(test.ipc("p_get", "wallpaper.transition.kind"), "wipe")
      test.click("wallpaper-parallax-0.12") test.settle(100)
      test.eq(test.ipc("p_get", "wallpaper.parallax"), 0.12)
      test.click("wallpaper-draw-switch") test.settle(100)
      test.eq(test.ipc("p_get", "wallpaper.draw"), false)
      test.truthy(test.get({ id = "wallpaper-draw-subtitle" }).text:find("Your wallpaper tool", 1, true), "it still says Eva paints")
    end)
  end)
end
