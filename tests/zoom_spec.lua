-- eva-zoom: Hyprland's cursor zoom through a stubbed hyprctl, read back, the Lua
-- configuration's way, the words of the command line; the lens over a frozen
-- picture, its factor, its field, a finger, and how it ends; the small window.
-- A real freeze on a real sway is tools/see/zoom.steps'. Hyprland itself never
-- runs here: `hyprctl` is a stub in every test.
--
--     morf test --no-dbus tests/zoom_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local PICTURE = ROOT .. "tests/fixtures/wallpaper.png"
local SURFACE = "layer:eva-zoom"

local function env(extra)
  local full = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule" }
  for key, value in pairs(extra or {}) do full[key] = value end
  return full
end

local function option(value) return { code = 0, stdout = ('{"option":"cursor:zoom_factor","float":%s,"set":true}'):format(value) } end

-- A host beside the real model: a hyprctl whose factor follows the keyword.
local function hyprland(word, accepts)
  test.clear_stubs()
  test.stub_run("hyprctl", option(accepts or 2))
  test.load("../apps/zoom/app.lua", { env = env { HYPRLAND_INSTANCE_SIGNATURE = "stub" }, args = { word } })
  test.advance(100)
end

local function calls(name)
  local found = {}
  for _, argv in ipairs(test.runs()) do
    if argv[1] == name then found[#found + 1] = table.concat(argv, " ") end
  end
  return found
end

test.it("takes a word of the command line to a factor", function()
  test.clear_stubs()
  test.load("../apps/zoom/app.lua", { source = [[
    local model = require("model")
    morf.ipc.word = function(word, now) return model.word(word, tonumber(now)) end
  ]] .. morf.fs.read(ROOT .. "apps/zoom/app.lua"), env = env() })
  test.eq(test.ipc("word", "in", "2"), 2.5)
  test.eq(test.ipc("word", "out", "2"), 1.5)
  test.eq(test.ipc("word", "out", "1"), 1)
  test.eq(test.ipc("word", "in", "10"), 10)
  test.eq(test.ipc("word", "reset", "4"), 1)
  test.eq(test.ipc("word", "3.25", "1"), 3.25)
  test.eq(test.ipc("word", "99", "1"), 10)
  test.falsy(test.ipc("word", "sideways", "1"))
end)

test.it("steps the keyword from what it reads, and reads it back", function()
  hyprland("in", 2.5)
  test.contains(calls("hyprctl"), "hyprctl keyword cursor:zoom_factor 3")
  hyprland("2.5", 2.5)
  local list = calls("hyprctl")
  test.eq(list[1], "hyprctl -j getoption cursor:zoom_factor")
  test.eq(list[2], "hyprctl eval hl.config({ cursor = { zoom_factor = 2.5 } })")
  test.eq(list[3], "hyprctl keyword cursor:zoom_factor 2.5")
  test.eq(list[4], "hyprctl -j getoption cursor:zoom_factor")
  test.eq(#list, 4, "a classic Hyprland hears the keyword once")
end)

test.it("sets a factor, and reset goes back to one", function()
  hyprland("4", 4)
  test.contains(calls("hyprctl"), "hyprctl keyword cursor:zoom_factor 4")
  hyprland("reset", 1)
  test.contains(calls("hyprctl"), "hyprctl keyword cursor:zoom_factor 1")
end)

test.it("a Lua-configured Hyprland takes it and never hears the keyword", function()
  test.clear_stubs()
  test.stub_run("hyprctl", "ok\n")
  test.load("../apps/zoom/app.lua", { env = env { HYPRLAND_INSTANCE_SIGNATURE = "stub" }, args = { "2.5" } })
  test.advance(100)
  local list = calls("hyprctl")
  test.contains(list, "hyprctl eval hl.config({ cursor = { zoom_factor = 2.5 } })")
  for _, line in ipairs(list) do test.falsy(line:find("keyword", 1, true), line) end
end)

test.it("holds the keyword back when dry", function()
  test.clear_stubs()
  test.stub_run("hyprctl", option(2))
  test.load("../apps/zoom/app.lua", { env = env { HYPRLAND_INSTANCE_SIGNATURE = "stub", EVA_DRY_RUN = "1" }, args = { "in" } })
  test.advance(100)
  for _, line in ipairs(calls("hyprctl")) do test.falsy(line:find("keyword", 1, true), line) end
end)

local function lens(extra, size)
  test.clear_stubs()
  test.stub_run("grim", { code = 1 })
  local full = env { EVA_ZOOM_LENS = "lens", XDG_STATE_HOME = morf.env("XDG_STATE_HOME") .. "/zoom-" .. morf.time.now_ms() }
  for key, value in pairs(extra or {}) do full[key] = value end
  test.load("../apps/zoom/app.lua", { env = full, size = size or { 1280, 800 }, source = ([[
    require("model").picture:set { path = %q, width = 1280, height = 800 }
  ]]):format(PICTURE) .. morf.fs.read(ROOT .. "apps/zoom/app.lua") })
  test.settle(1500)
end

local function state() return test.ipc("state") end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("stands a lens on the pointer, a field round it, in " .. style, function()
    lens { EVA_FAKE_POINTER = "300,200", EVA_STYLE = style }
    test.eq({ state().x, state().y }, { 300, 200 })
    local glass = test.get("zoom-glass")
    test.near(glass.x + glass.width / 2, 300, 1)
    test.near(glass.y + glass.height / 2, 200, 1)
    test.eq(test.get("zoom-rim").element, "Sdf")
    test.eq(test.get("zoom-tab-shape").parent, test.get("zoom-rim").handle)
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("shows the picture magnified about the pointer", function()
  lens { EVA_FAKE_POINTER = "300,200" }
  test.eq(test.get("zoom-factor").text, "2.0×")
  test.ipc("point", "640", "400")
  test.settle(1500)
  local image, pane = test.get("zoom-image"), test.get("zoom-pane")
  test.near(image.width, 1280 * 2, 2, "the picture is not at twice its size")
  test.near(image.x, pane.x - 640 * 2, 2, "the pointer's pixel is not at the middle")
end)

test.it("the wheel sets the factor on a spring, with a modifier the size", function()
  lens()
  test.wheel(0, -40, { x = 300, y = 300, surface = SURFACE })
  test.eq(state().factor, 2.5)
  test.wheel(0, 40, { x = 300, y = 300, surface = SURFACE, modifiers = "ctrl" })
  test.eq(state().radius, 96)
  test.wheel(0, 40, { x = 300, y = 300, surface = SURFACE })
  test.wheel(0, 40, { x = 300, y = 300, surface = SURFACE })
  test.eq(state().factor, 1.5)
end)

test.it("takes keys", function()
  lens()
  test.click(5, 5, { surface = SURFACE, button = "right" })
  test.key("+")
  test.eq(state().factor, 2.5)
  test.key("]")
  test.eq(state().radius, 200)
  test.key("0")
  test.eq(state().factor, 1)
end)

test.it("keeps the factor for next time", function()
  local folder = morf.env("XDG_STATE_HOME") .. "/zoom-kept-" .. morf.time.now_ms()
  lens { XDG_STATE_HOME = folder }
  test.wheel(0, -40, { x = 300, y = 300, surface = SURFACE })
  lens { XDG_STATE_HOME = folder }
  test.eq(state().factor, 2.5)
end)

test.it("a finger drives it, the lens above the finger", function()
  lens(nil, { 412, 915 })
  test.touch("down", 1, 200, 500, { surface = SURFACE })
  test.touch("move", 1, 220, 520, { surface = SURFACE })
  test.settle(1000)
  test.eq({ state().x, state().y }, { 220, 520 })
  local glass = test.get("zoom-glass")
  test.truthy(glass.y + glass.height < 520, "the lens sits under the finger")
  test.touch("up", 1, 220, 520, { surface = SURFACE })
end)

test.it("has buttons for a finger", function()
  lens(nil, { 412, 915 })
  test.click { id = "zoom-in" }
  test.eq(state().factor, 2.5)
  test.click { id = "zoom-out" }
  test.eq(state().factor, 2)
  local bar = test.get("zoom-controls")
  test.truthy(bar.x >= 0 and bar.x + bar.width <= 412)
end)

test.it("the window's slider sets the lens elsewhere", function()
  test.clear_stubs()
  test.load("../apps/zoom/app.lua", { env = env { XDG_STATE_HOME = morf.env("XDG_STATE_HOME") .. "/zoom-w" }, size = { 460, 360 } })
  test.settle(1000)
  test.truthy(test.find { id = "zoom-slider" })
  test.click { id = "zoom-window-in" }
  test.eq(state().factor, 2.5)
  test.click { id = "zoom-window-reset" }
  test.eq(state().factor, 1)
  test.ipc("set", "4")
  test.eq(state().factor, 4)
  test.eq(#test.logs("error"), 0)
end)

test.it("the window's slider sets the keyword on Hyprland", function()
  test.clear_stubs()
  test.stub_run("hyprctl", option(3))
  test.load("../apps/zoom/app.lua", { env = env { HYPRLAND_INSTANCE_SIGNATURE = "stub" }, size = { 460, 360 } })
  test.advance(100)
  test.eq(state().cursor, 3)
  test.ipc("set", "3")
  test.advance(100)
  test.contains(calls("hyprctl"), "hyprctl keyword cursor:zoom_factor 3")
end)
