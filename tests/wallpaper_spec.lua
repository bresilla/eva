-- The wallpaper: which picture, and whether the shell paints it.
--
--     morf test --no-dbus tests/wallpaper_spec.lua
local test = morf.test
local ROOT = morf.fs.join(morf.env("PWD") or ".", "tests/fixtures/wallpapers")
local function picture(name) return ROOT .. "/" .. name .. ".png" end

local SOURCE = [[
  local layers = 0
  local open = morf.window.layer
  morf.window.layer = function(props)
    if props.namespace == "eva-wallpaper" then layers = layers + 1 end
    return open(props)
  end
  require("init")
  local config = require("config")
  local wallpaper = require("wallpaper")
  morf.ipc.w_get = function(key) return config.get(key) end
  morf.ipc.w_layers = function() return layers end
  morf.ipc.w_current = function() return wallpaper.current:get() end
  morf.ipc.w_set_wallpaper = function(path) wallpaper.set(path) end
]]

local serial = 0
local function load(spec)
  spec = spec or {}
  serial = serial + 1
  local cache = morf.env("XDG_CACHE_HOME")
  local env = { EVA_DRY_RUN = "1", EVA_STYLE = spec.style or "material", EVA_WALLPAPER = spec.wallpaper or "",
    EVA_SETTINGS = cache .. "/wallpaper-settings-" .. serial .. ".json",
    EVA_APPEARANCE = cache .. "/wallpaper-appearance-" .. serial .. ".json",
    LULE_A = spec.lule or "/nonexistent/lule", HOME = cache }
  if spec.settings then morf.fs.write(env.EVA_SETTINGS, morf.json.encode(spec.settings)) end
  test.load("../shell/init.lua", { source = SOURCE, size = spec.size or { 1280, 800 }, env = env })
  test.settle(1500)
end

-- A Lule folder whose colours were made from `name`.
local function lule_made(name)
  local dir = morf.env("XDG_CACHE_HOME") .. "/lule-" .. serial .. "-" .. name
  morf.fs.mkdir(dir, { parents = true })
  morf.fs.write(dir .. "/colors.json", morf.json.encode {
    wallpaper = picture(name), theme = "dark", colors = { "#111111", "#ffaa66" } })
  return dir
end

test.describe("which picture", function()
  test.it("takes Lule's over the setting, and Lule's next one with it", function()
    local dir = lule_made("dune")
    load { lule = dir, settings = { wallpaper = { path = picture("snow") } } }
    test.eq(test.ipc("w_current"), picture("dune"))
    morf.fs.write(dir .. "/colors.json", morf.json.encode {
      wallpaper = picture("lagoon"), theme = "dark", colors = { "#111111", "#ffaa66" } })
    test.wait(function() test.advance(16) return test.ipc("w_current") == picture("lagoon") end, 3000,
      "Lule's new picture did not take over")
  end)

  test.it("takes the setting without Lule, and a picture set by hand", function()
    load { settings = { wallpaper = { path = picture("snow") } } }
    test.eq(test.ipc("w_current"), picture("snow"))
    test.ipc("w_set_wallpaper", picture("forest"))
    test.eq(test.ipc("w_current"), picture("forest"))
    test.eq(test.ipc("w_get", "wallpaper.path"), picture("forest"))
  end)

  test.it("takes EVA_WALLPAPER over Lule's", function()
    load { lule = lule_made("dune"), wallpaper = picture("paper") }
    test.eq(test.ipc("w_current"), picture("paper"))
  end)
end)

test.describe("who paints", function()
  test.it("opens the layer only with wallpaper.draw", function()
    load { settings = { wallpaper = { path = picture("dune") } } }
    test.eq(test.ipc("w_layers"), 0)
    load { settings = { wallpaper = { draw = true, path = picture("dune") } } }
    test.eq(test.ipc("w_layers"), 1)
    test.eq(#test.logs("error"), 0)
  end)

  test.it("leaves the desk alone with nothing to show", function()
    load { settings = { wallpaper = { draw = true } } }
    test.eq(test.ipc("w_layers"), 0)
  end)
end)
