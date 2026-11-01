-- A pinned shot: a surface above the windows, moved by a drag and closed by a
-- press, from the editor, the thumbnail, the history and the command line.
--
--     morf test --no-dbus tests/capture_pin_spec.lua
local test = morf.test

local TOOL = "../apps/screenshot/app.lua"

local SOURCE = [[
  local backend = require("lib.shell.capture")
  local scratch = morf.env("XDG_CACHE_HOME") .. "/capture-pin"
  morf.fs.remove(scratch, { recursive = true })
  morf.fs.mkdir(scratch .. "/shots")
  local picture = scratch .. "/rendered.png"
  morf.fs.copy(morf.fs.join(morf.env("PWD"), "tests/fixtures/wallpaper.png"), picture)
  morf.fs.copy(picture, scratch .. "/shots/capture_1.png")
  local quits = 0
  backend.windows = function(cb) cb({}) end
  backend.session = function()
    return { snapshot = function(_, cb) cb(true, { source = picture, width = 1200, height = 800 }) end,
      render = function(_, _, cb) morf.time.timer(5, function() cb(true, picture) end, false) end,
      close = function() end, remove = function() end }
  end
  backend.save = function(path, target, cb) morf.fs.copy(path, target) cb(true, target) end
  backend.copy = function(_, cb) cb(true) end
  morf.process.detach = function() end
  morf.quit = function() quits = quits + 1 end
  require("config").set("capture.folder", scratch .. "/shots")
  require("config").set("capture.thumbnail", true)
  require("app")
  local env = morf.env
  morf.env = function(key) if key == "EVA_DRY_RUN" then return "0" end return env(key) end
  local capture = require("capture")
  morf.shared("eva.capture.owner", ""):set("")
  morf.ipc.flow = function()
    local pin = package.loaded.pin
    local first = pin and pin.list[1]
    return { pins = pin and #pin.list or 0, loaded = pin ~= nil, held = capture.held:get(), quits = quits,
      editing = capture.editor.active:get(), own = first and first.own or false, path = first and first.path or "",
      x = first and first.x or 0, y = first and first.y or 0, width = first and first.width or 0,
      height = first and first.height or 0, index = first and first.index or 0,
      left = first and first.surface and first.surface.margin_left or 0 }
  end
  morf.ipc.picture = function() return picture end
  morf.ipc.fit = function(w, h, sw, sh) return { require("pin").fit(tonumber(w), tonumber(h), { width = tonumber(sw), height = tonumber(sh) }) } end
]]

local function tool(style, size, args)
  test.load(TOOL, { source = SOURCE, size = size or { 1920, 1080 }, args = args,
    env = { EVA_STYLE = style or "material", EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "" } })
  test.advance(300)
end

local function surfaces()
  local found = {}
  for _, one in ipairs(test.surfaces()) do
    if tostring(one.name):find("eva-capture-pin", 1, true) or tostring(one.label):find("eva-capture-pin", 1, true) then
      found[#found + 1] = one
    end
  end
  return found
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": the editor pins what is selected, marks and all, and a press closes it", function()
    tool(style)
    test.falsy(test.ipc("flow").loaded, "the pin was loaded at rest")
    test.ipc("screenshot", "screen") test.advance(600)
    test.click("capture-editor-more") test.advance(220)
    test.click("capture-editor-pin") test.advance(400)
    local state = test.ipc("flow")
    test.eq(state.pins, 1) test.falsy(state.editing) test.truthy(state.own) test.eq(state.held, 1)
    test.truthy(morf.fs.exists(state.path))
    local shown = surfaces()[1]
    test.truthy(shown, "no surface of its own")
    test.truthy(shown.visible)
    test.truthy(shown.width <= 1920 * 0.4 + 1)
    test.click("capture-pin-press-" .. state.index) test.advance(100) test.settle(100)
    state = test.ipc("flow")
    test.eq(state.pins, 0) test.eq(state.held, 0)
    test.eq(#surfaces(), 0, "its surface stayed")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("floats on the top layer, under the tool's own overlay", function()
  tool()
  test.ipc("capture-pin", "add", test.ipc("picture")) test.advance(100)
  local one = surfaces()[1]
  test.truthy(one)
  local index = test.ipc("flow").index
  test.falsy(test.ipc("flow").own, "a file of the person's would go with the pin")
  test.click("capture-pin-press-" .. index) test.settle(100)
  test.truthy(morf.fs.exists(test.ipc("picture")), "closing a pin took the person's file")
end)

test.it("a private copy goes with its pin", function()
  tool()
  test.ipc("screenshot", "screen", "how=pin") test.advance(900)
  local state = test.ipc("flow")
  test.eq(state.pins, 1) test.truthy(state.own)
  test.truthy(morf.fs.exists(state.path))
  test.ipc("capture-pin", "clear") test.settle(100)
  test.falsy(morf.fs.exists(state.path), "the private copy stayed")
end)

test.it("a drag moves it and does not close it, a finger as well", function()
  tool()
  test.ipc("capture-pin", "add", test.ipc("picture")) test.advance(100)
  local before = test.ipc("flow")
  local name = surfaces()[1].label
  test.press(40, 40, { surface = name }) test.advance(16)
  test.move(10, 60, { surface = name }) test.advance(16)
  test.release(10, 60, { surface = name }) test.advance(100)
  local after = test.ipc("flow")
  test.eq(after.pins, 1, "a drag closed it")
  test.truthy(after.x ~= before.x or after.y ~= before.y, "it did not move")
  test.eq(after.left, math.floor(after.x), "the surface stayed where it was")
  local id = "capture-pin-press-" .. after.index
  test.touch("down", 1, 40, 40, { surface = name }) test.advance(16)
  test.touch("move", 1, 90, 90, { surface = name }) test.advance(16)
  test.touch("up", 1, 90, 90, { surface = name }) test.advance(100)
  local dragged = test.ipc("flow")
  test.eq(dragged.pins, 1, "a finger's drag closed it")
  test.truthy(dragged.x ~= after.x or dragged.y ~= after.y, "a finger did not move it")
  test.touch("down", 1, 40, 40, { surface = name }) test.advance(16)
  test.touch("up", 1, 40, 40, { surface = name }) test.advance(100) test.settle(100)
  test.eq(test.ipc("flow").pins, 0, "a tap did not close it")
  test.falsy(test.find { id = id })
end)

test.it("stays on the screen however far it is dragged", function()
  tool(nil, { 412, 915 })
  test.ipc("capture-pin", "add", test.ipc("picture")) test.advance(100)
  local name = surfaces()[1].label
  test.press(20, 20, { surface = name }) test.advance(16)
  test.move(2000, 2000, { surface = name }) test.advance(16)
  test.release(2000, 2000, { surface = name }) test.advance(100)
  local state = test.ipc("flow")
  test.truthy(state.x + state.width <= 412, "it left the phone")
  test.truthy(state.y + state.height <= 915)
end)

test.it("the thumbnail's pin takes it from the corner", function()
  tool()
  test.ipc("screenshot", "screen", "how=save") test.advance(900)
  test.eq(test.ipc("flow").held, 1, "no thumbnail")
  test.click("capture-thumb-pin") test.advance(300)
  local state = test.ipc("flow")
  test.eq(state.pins, 1) test.eq(state.held, 1)
  test.contains(state.path, "/shots/capture_")
  test.falsy(state.own)
end)

test.it("the history pins a shot from its file", function()
  tool()
  test.ipc("capture", "open") test.settle(1000)
  test.click("capture-history-open") test.settle(800)
  test.click("capture-history-row-1") test.advance(100)
  test.click("capture-history-pin") test.advance(400)
  local state = test.ipc("flow")
  test.eq(state.pins, 1) test.falsy(state.own)
end)

test.it("a tool with nothing else to do stays while one is up", function()
  tool("material", { 1920, 1080 }, { "capture-pin", "add", morf.fs.join(morf.env("PWD"), "tests/fixtures/wallpaper.png") })
  test.advance(600)
  test.eq(test.ipc("flow").pins, 1)
  test.advance(600)
  test.eq(test.ipc("flow").quits, 0, "it ended under a pin")
  test.ipc("capture-pin", "clear") test.settle(400)
  test.advance(400)
  test.eq(test.ipc("flow").quits, 1, "it did not end with the last pin")
end)

test.it("fits a large picture to the screen, and keeps a small one its size", function()
  tool()
  test.eq(test.ipc("fit", 3840, 2160, 1920, 1080), { 768, 432 })
  test.eq(test.ipc("fit", 300, 200, 1920, 1080), { 300, 200 })
end)

test.it("comes back after a reload", function()
  tool()
  test.ipc("capture-pin", "add", test.ipc("picture")) test.advance(100)
  test.eq(test.ipc("flow").pins, 1)
  test.reload { source = SOURCE }
  test.advance(300)
  test.eq(test.ipc("flow").pins, 1, "a reload took the pin")
  test.eq(#surfaces(), 1)
  test.ipc("capture-pin", "clear") test.settle(100)
end)
