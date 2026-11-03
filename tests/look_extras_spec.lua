-- What sits around the main features: parallax, the second picture and the glow,
-- the island, what the desktop says, and how quick and how fluid things are.
--
--     morf test --no-dbus tests/look_extras_spec.lua
local test = morf.test
local ROOT = morf.fs.join(morf.env("PWD") or ".", "tests/fixtures/wallpapers")
local function picture(name) return ROOT .. "/" .. name .. ".png" end

local SOURCE = [[
  local reloads = 0
  local reload = morf.reload
  morf.reload = function() reloads = reloads + 1 end
  morf.ipc.x_reloads = function() return reloads end
  local ui = require("morf.ui")
  local nodes = {}
  for _, name in ipairs { "Item", "Rect" } do
    local make = ui[name]
    ui[name] = function(props)
      local node = make(props)
      if props.id then nodes[props.id] = node end
      return node
    end
  end
  morf.ipc.x_prop = function(id, property) return nodes[id] and nodes[id][property] end
  require("init")
  local config = require("config")
  local theme = require("theme")
  local appearance = require("appearance_model")
  morf.ipc.x_set = function(key, value) return config.set(key, value) end
  morf.ipc.x_get = function(key) return config.get(key) end
  morf.ipc.x_stretch = function() return theme.stretch and theme.stretch.drawer and theme.stretch.drawer.scale end
  morf.ipc.x_stiffness = function(name) return theme.bounce[name].duration end
  morf.ipc.x_pointer = function(x, y) require("wallpaper").pointer(x, y) end
  morf.ipc.x_mode = function() return appearance.mode() end
]]

-- Stands in for the desktop's settings portal, which no spec has.
local function desktop_says(scheme, accent, reduced)
  return ([[
    morf.prefers = { color_scheme = %q, accent_color = %s, reduced_motion = %s }
  ]]):format(scheme, accent and ("%q"):format(accent) or "nil", tostring(reduced == true)) .. SOURCE
end

local serial = 0
local function load(spec)
  spec = spec or {}
  serial = serial + 1
  local cache = morf.env("XDG_CACHE_HOME")
  local config_home = cache .. "/extras-config-" .. serial
  local env = { EVA_DRY_RUN = "1", EVA_STYLE = spec.style or "material", EVA_WALLPAPER = "",
    EVA_SETTINGS = cache .. "/extras-settings-" .. serial .. ".json",
    EVA_APPEARANCE = cache .. "/extras-appearance-" .. serial .. ".json",
    LULE_A = "/nonexistent/lule", HOME = cache, XDG_CONFIG_HOME = spec.config_home or config_home }
  morf.fs.write(env.EVA_SETTINGS, morf.json.encode(spec.settings or {}))
  test.stub_run("task", { code = 0, stdout = "[]" })
  if spec.appearance then morf.fs.write(env.EVA_APPEARANCE, morf.json.encode(spec.appearance)) end
  test.load("../shell/init.lua", { source = spec.source or SOURCE, size = spec.size or { 1600, 1000 }, env = env })
  test.settle(1200)
  return env
end

test.describe("the picture", function()
  test.it("slides across the workspaces by the parallax, on a spring", function()
    load { settings = { wallpaper = { draw = true, path = picture("dune"), parallax = 0.2 } } }
    test.near(test.get({ id = "wallpaper-plate" }).width, 1920, 1)
    test.near(test.ipc("x_prop", "wallpaper-plate", "translate_x"), 0, 0.5)
    test.ipc("workspace", 3) test.advance(48)
    local moving = test.ipc("x_prop", "wallpaper-plate", "translate_x")
    test.truthy(moving < 0 and moving > -160, "it jumped, or stayed: " .. tostring(moving))
    test.settle(1500)
    test.near(test.ipc("x_prop", "wallpaper-plate", "translate_x"), -160, 1)
  end)

  test.it("stands still without a parallax", function()
    load { settings = { wallpaper = { draw = true, path = picture("dune") } } }
    test.ipc("workspace", 3) test.settle(800)
    test.near(test.get({ id = "wallpaper-plate" }).width, 1600, 1)
    test.near(test.ipc("x_prop", "wallpaper-plate", "translate_x"), 0, 0.1)
  end)

  test.it("shows a second picture round the pointer", function()
    load { settings = { wallpaper = { draw = true, path = picture("dune"), xray = picture("snow") } } }
    test.truthy(test.find { id = "wallpaper-xray", visible = true }, "no second picture")
    test.ipc("x_pointer", 500, 300) test.advance(16)
    local hole = test.get { id = "wallpaper-xray-hole" }
    test.near(hole.x, 360, 0.5)
    test.near(hole.y, 160, 0.5)
    test.move(700, 400, { surface = "eva-wallpaper" }) test.advance(16)
    hole = test.get { id = "wallpaper-xray-hole" }
    test.near(hole.x, 560, 0.5, "the hole does not follow the real pointer")
    test.near(hole.y, 260, 0.5)
    test.ipc("x_set", "wallpaper.xray", "") test.advance(16)
    test.falsy(test.find { id = "wallpaper-xray", visible = true })
  end)

  test.it("carries a glow that is there only when asked", function()
    load { settings = { wallpaper = { draw = true, path = picture("dune"), glow = true } } }
    test.truthy(test.ipc("x_prop", "wallpaper-glow", "visible"))
    test.ipc("x_set", "wallpaper.glow", false) test.advance(16)
    test.falsy(test.ipc("x_prop", "wallpaper-glow", "visible"))
    test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
  end)
end)

test.describe("the island", function()
  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. " grows out of the frame when asked, and opens on a press", function()
      load { style = style, settings = { island = { enabled = true } } }
      test.truthy(test.find { id = "island", visible = true }, "no island")
      local rest = test.get({ id = "island" }).width
      test.eq(test.ipc("island", "state").showing, "clock")
      test.truthy(test.get({ id = "island-words" }).text:find(":", 1, true), "no time on it")
      test.ipc("island", "toggle") test.settle(800)
      test.truthy(test.get({ id = "island" }).width > rest, "it did not grow")
      test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
    end)
  end

  test.it("stays out of the frame unless asked, and rebuilds when it is", function()
    load {}
    test.falsy(test.find { id = "island", visible = true })
    test.ipc("island", "on") test.advance(300)
    test.eq(test.ipc("x_reloads"), 1, "turning it on did not rebuild")
  end)

  test.it("opens on a press and walks its faces on a right press", function()
    load { settings = { island = { enabled = true } } }
    local island = test.get { id = "island" }
    local x, y = island.x + island.width / 2, island.y + island.height / 2
    test.click(x, y, { button = "right" })
    test.eq(test.ipc("island", "state").face, "media", "a right press did not walk the faces")
    test.falsy(test.ipc("island", "state").open)
    test.click(x, y)
    test.truthy(test.ipc("island", "state").open, "a press did not open it")
  end)

  test.it("walks its faces", function()
    load { settings = { island = { enabled = true } } }
    test.eq(test.ipc("island", "next").face, "media")
    test.eq(test.ipc("island", "next").face, "clock")
    test.eq(test.ipc("island", "next").face, "weather")
    test.eq(test.ipc("island", "next").face, "auto")
  end)
end)

test.describe("what the desktop says", function()
  test.it("sets the mode while following it, and stands by the tool when it has no opinion", function()
    load { source = desktop_says("light"), appearance = { mode = "system" } }
    test.eq(test.ipc("x_mode"), "light")
    load { source = desktop_says("dark"), appearance = { mode = "system" } }
    test.eq(test.ipc("x_mode"), "dark")
    load { source = desktop_says("none"), appearance = { mode = "system" } }
    test.eq(test.ipc("x_mode"), "dark", "no opinion should leave the tool's mode")
  end)

  test.it("lands everything when the desktop asks for less motion", function()
    load { source = desktop_says("dark", nil, true) .. [[
      morf.ipc.x_reduced = function() return require("themes.motion_style").reduced() end
    ]] }
    test.truthy(test.ipc("x_reduced"))
  end)
end)

test.describe("how things move", function()
  test.it("quickens with the speed", function()
    load { settings = { appearance = { speed = 1 } } }
    local usual = test.ipc("x_stiffness", "spatial")
    load { settings = { appearance = { speed = 1.5 } } }
    test.truthy(test.ipc("x_stiffness", "spatial") < usual, "it is no quicker")
  end)

  test.it("deforms by the setting, down to rigid", function()
    load { settings = { appearance = { deform = 2 } } }
    local liquid = test.ipc("x_stretch")
    load { settings = { appearance = { deform = 0 } } }
    test.eq(test.ipc("x_stretch"), 0)
    test.truthy(liquid > 0)
  end)
end)
