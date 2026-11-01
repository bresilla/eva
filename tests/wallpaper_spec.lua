-- The wallpaper: which picture, who paints it, and how one becomes the next.
--
--     morf test --no-dbus tests/wallpaper_spec.lua
local test = morf.test
local ROOT = morf.fs.join(morf.env("PWD") or ".", "tests/fixtures/wallpapers")
local function picture(name) return ROOT .. "/" .. name .. ".png" end

local SOURCE = [[
  local ui = require("morf.ui")
  local images = {}
  local make = ui.Image
  ui.Image = function(props)
    local node = make(props)
    if props.id then images[props.id] = node end
    return node
  end
  local layers, closed = 0, 0
  local open = morf.window.layer
  morf.window.layer = function(props)
    local handle = open(props)
    if props.namespace ~= "eva-wallpaper" then return handle end
    layers = layers + 1
    local destroy = handle.destroy
    return setmetatable({ destroy = function() closed = closed + 1 destroy(handle) end }, { __index = handle })
  end
  require("init")
  local config = require("config")
  local wallpaper = require("wallpaper")
  local model = require("wallpaper_model")
  morf.ipc.w_set = function(key, value) return config.set(key, value) end
  morf.ipc.w_get = function(key) return config.get(key) end
  morf.ipc.w_layers = function() return { open = layers, closed = closed, painter = wallpaper.painter() } end
  morf.ipc.w_current = function() return wallpaper.current:get() end
  morf.ipc.w_picture = function() return wallpaper.picture() end
  morf.ipc.w_masked = function()
    local out = {}
    for slot = 1, 2 do
      local image = images["wallpaper-picture-" .. slot]
      if image and image.visible then out[#out + 1] = { source = image.source, opacity = image.opacity } end
    end
    return out
  end
  morf.ipc.w_output = function(path) wallpaper.set_output(wallpaper.output(), path) end
  morf.ipc.w_workspace = function(n, path) wallpaper.set_workspace(n, path) end
  morf.ipc.w_neighbour = function(delta) return model.neighbour(delta) end
  morf.ipc.w_step = function(delta) return model.step(delta) end
  morf.ipc.w_held = function() return model.held() end
  morf.ipc.w_target = function(value) model.target:set(value) end
  morf.ipc.w_choose = function(path) return model.choose(path, { x = 40, y = 30 }) end
  morf.ipc.w_note = function() return model.painter_note() end
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
  for key, value in pairs(spec.env or {}) do env[key] = value end
  if spec.settings then morf.fs.write(env.EVA_SETTINGS, morf.json.encode(spec.settings)) end
  test.load("../shell/init.lua", { source = SOURCE, size = spec.size or { 1280, 800 }, env = env })
  test.settle(1500)
end

local function drawn(settings)
  settings = settings or {}
  settings.draw = settings.draw == nil and true or settings.draw
  settings.path = settings.path or picture("dune")
  return { wallpaper = settings }
end

local function wait_picture(path)
  test.wait(function()
    local masked = test.ipc("w_masked")
    return #masked == 1 and masked[1].source ~= "" and test.ipc("w_picture") == path
  end, 3000, "the picture did not arrive")
end

test.describe("which picture", function()
  test.it("keeps a picture set by hand over Lule's until Lule makes another", function()
    local dir = morf.env("XDG_CACHE_HOME") .. "/lule-" .. serial
    morf.fs.mkdir(dir, { parents = true })
    local colors = { wallpaper = picture("dune"), theme = "dark", colors = { "#111111", "#ffaa66" } }
    morf.fs.write(dir .. "/colors.json", morf.json.encode(colors))
    load { lule = dir }
    test.eq(test.ipc("w_current"), picture("dune"))
    test.ipc("w_set_wallpaper", picture("snow"))
    test.eq(test.ipc("w_current"), picture("snow"), "a picture set by hand gave way to Lule's")
    colors.wallpaper = picture("lagoon")
    morf.fs.write(dir .. "/colors.json", morf.json.encode(colors))
    test.wait(function() test.advance(16) return test.ipc("w_current") == picture("lagoon") end, 3000,
      "Lule's new picture did not take over")
  end)

  test.it("gives an output and a workspace their own picture", function()
    load { settings = drawn() }
    test.eq(test.ipc("w_picture"), picture("dune"))
    test.ipc("w_output", picture("snow"))
    test.eq(test.ipc("w_picture"), picture("snow"))
    test.eq(test.ipc("w_current"), picture("dune"), "the scheme's picture moved with the output's")
    test.ipc("w_workspace", 3, picture("forest"))
    test.eq(test.ipc("w_picture"), picture("snow"))
    test.ipc("workspace", 3) test.advance(16)
    test.eq(test.ipc("w_picture"), picture("forest"))
    test.ipc("workspace", 1) test.advance(16)
    test.eq(test.ipc("w_picture"), picture("snow"))
    test.ipc("w_output", "")
    test.eq(test.ipc("w_picture"), picture("dune"))
  end)

  test.it("takes the day and night pictures by the colour mode", function()
    local settings = drawn { day = picture("paper"), night = picture("dusk") }
    load { settings = settings }
    test.eq(test.ipc("w_current"), picture("dusk"), "dark did not take the night picture")
  end)
end)

test.describe("who paints", function()
  test.it("opens and shuts the layer with wallpaper.draw, and says who paints", function()
    load { settings = { wallpaper = { path = picture("dune") } } }
    test.eq(test.ipc("w_layers"), { open = 0, closed = 0, painter = "tool" })
    test.truthy(test.ipc("w_note"):find("Your wallpaper tool", 1, true))
    test.ipc("w_set", "wallpaper.draw", true) test.advance(16)
    test.eq(test.ipc("w_layers"), { open = 1, closed = 0, painter = "eva" })
    test.truthy(test.ipc("w_note"):find("Eva paints", 1, true))
    test.ipc("w_set", "wallpaper.draw", false) test.advance(16)
    test.eq(test.ipc("w_layers"), { open = 1, closed = 1, painter = "tool" })
    test.ipc("w_set", "wallpaper.draw", true) test.advance(16)
    test.eq(test.ipc("w_layers"), { open = 2, closed = 1, painter = "eva" })
    test.eq(#test.logs("error"), 0)
  end)

  test.it("paints a colour alone, and leaves the desk alone with nothing to show", function()
    load { settings = { wallpaper = { draw = true } } }
    test.eq(test.ipc("w_layers").painter, "none")
    test.ipc("w_set", "wallpaper.color", "#123456") test.advance(16)
    test.eq(test.ipc("w_layers"), { open = 1, closed = 0, painter = "eva" })
  end)
end)

test.describe("transitions", function()
  for _, kind in ipairs { "fade", "wipe", "circle", "grow", "dissolve", "stripes", "diamond", "star", "melt" } do
    test.it(kind .. " carries one picture into the next, and lets the first go", function()
      load { settings = drawn { transition = { kind = kind, duration = 400 } } }
      wait_picture(picture("dune"))
      test.ipc("w_set_wallpaper", picture("lagoon"))
      test.wait(function() test.advance(16) return #test.ipc("w_masked") == 2 end, 3000, "both pictures never showed")
      test.advance(600)
      test.settle(800)
      local after = test.ipc("w_masked")
      test.eq(#after, 1, "the outgoing picture is still drawn")
      test.eq(after[1].opacity, 1)
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it("lands at once under Reduce motion", function()
    load { settings = { wallpaper = { draw = true, path = picture("dune") }, appearance = { reduce_motion = true } } }
    wait_picture(picture("dune"))
    test.ipc("w_set_wallpaper", picture("lagoon"))
    test.wait(function() test.advance(16) return test.ipc("w_masked")[1].source ~= "" end, 3000)
    test.advance(32)
    test.eq(#test.ipc("w_masked"), 1, "Reduce motion still ran a transition")
  end)
end)

test.describe("the slideshow", function()
  test.it("shuffles without a repeat until every picture has shown", function()
    load { settings = { lule = { folder = ROOT }, wallpaper = { slideshow = { order = "shuffle" } } } }
    local seen = {}
    for _ = 1, 6 do
      local path = test.ipc("w_neighbour", 1)
      test.falsy(seen[path], "a picture came round twice: " .. tostring(path))
      seen[path] = true
    end
  end)

  test.it("walks the folder by name, both ways", function()
    load { settings = { lule = { folder = ROOT }, wallpaper = { path = picture("dune"), slideshow = { order = "name" } } } }
    test.eq(test.ipc("w_neighbour", 1), picture("dusk"))
    test.eq(test.ipc("w_neighbour", -1), picture("snow"))
  end)

  test.it("turns on its interval and stops when told", function()
    load { settings = { lule = { folder = ROOT },
      wallpaper = { path = picture("dune"), slideshow = { on = true, interval = 60, order = "name", colors = false } } } }
    test.advance(61000)
    test.eq(test.ipc("w_current"), picture("dusk"))
    test.ipc("w_set", "wallpaper.slideshow.on", false)
    test.advance(121000)
    test.eq(test.ipc("w_current"), picture("dusk"))
  end)

  test.it("holds while the session is locked", function()
    load { env = { EVA_FAKE_LOCKED = "1" }, settings = { lule = { folder = ROOT },
      wallpaper = { path = picture("dune"), slideshow = { on = true, interval = 60, order = "name", colors = false } } } }
    test.truthy(test.ipc("w_held"))
    test.advance(121000)
    test.eq(test.ipc("w_current"), picture("dune"), "a locked session moved on")
  end)
end)

test.describe("a choice", function()
  test.it("goes where the target says", function()
    load { settings = drawn() }
    test.ipc("w_target", "output:HEADLESS-1")
    test.ipc("w_choose", picture("snow"))
    test.eq(test.ipc("w_picture"), picture("snow"))
    test.eq(test.ipc("w_current"), picture("dune"), "a screen's picture changed the desk's")
    test.ipc("w_target", "all")
    test.ipc("w_choose", picture("forest"))
    test.eq(test.ipc("w_current"), picture("forest"))
  end)

  test.it("answers the wallpaper verb", function()
    load { settings = drawn() }
    test.eq(test.ipc("wallpaper", "state").painter, "eva")
    test.ipc("wallpaper", "set", picture("forest"))
    test.eq(test.ipc("wallpaper"), picture("forest"))
    test.ipc("wallpaper", "transition", "melt")
    test.eq(test.ipc("w_get", "wallpaper.transition.kind"), "melt")
    test.ipc("wallpaper", "draw", "off")
    test.eq(test.ipc("wallpaper", "state").painter, "tool")
  end)
end)
