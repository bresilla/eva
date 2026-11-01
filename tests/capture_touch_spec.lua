-- The tool under a finger, on a phone: the selection, the panel's history, and
-- a thumbnail pressed.
--
--     morf test --no-dbus tests/capture_touch_spec.lua
local test = morf.test

local SOURCE = [[
  local backend = require("lib.shell.capture")
  local scratch = morf.env("XDG_CACHE_HOME") .. "/capture-touch"
  morf.fs.mkdir(scratch .. "/shots")
  local picture = scratch .. "/rendered.png"
  morf.fs.copy(morf.fs.join(morf.env("PWD"), "tests/fixtures/wallpaper.png"), picture)
  backend.windows = function(cb) cb({ { x = 40, y = 200, w = 300, h = 200 } }) end
  backend.session = function()
    return { snapshot = function(_, cb) cb(true, { source = picture, width = 412, height = 915 }) end,
      render = function(_, _, cb) morf.time.timer(5, function() cb(true, picture) end, false) end,
      close = function() end, remove = function() end }
  end
  backend.copy = function(_, cb) cb(true) end
  backend.save = function(path, target, cb) morf.fs.copy(path, target) cb(true, target) end
  morf.process.detach = function() end
  require("config").set("capture.folder", scratch .. "/shots")
  require("config").set("capture.thumbnail", true)
  require("app")
  local env = morf.env
  morf.env = function(key) if key == "EVA_DRY_RUN" then return "0" end return env(key) end
  local capture = require("capture")
  morf.shared("eva.capture.owner", ""):set("")
  local moves, move = 0, capture.editor.move
  capture.editor.move = function(...) moves = moves + 1 return move(...) end
  morf.ipc.flow = function()
    local doc = capture.editor.document
    local thumb = package.loaded.thumb
    return { stage = capture.editor.phase:get(), active = capture.editor.active:get(), moves = moves,
      crop = doc and doc.crop or false, thumb = thumb and thumb.showing:get() or "" }
  end
]]

local function phone(style)
  test.load("../apps/screenshot/app.lua", { source = SOURCE, size = { 412, 915 },
    env = { EVA_STYLE = style, EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "" } })
  test.advance(300)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": a finger drags out a region", function()
    phone(style)
    test.ipc("screenshot", "region") test.advance(600)
    test.eq(test.ipc("flow").stage, "selecting")
    test.touch("down", 1, 50, 120) test.advance(16)
    test.touch("move", 1, 200, 300) test.advance(16)
    test.touch("move", 1, 300, 500) test.advance(16)
    test.touch("up", 1, 300, 500) test.advance(300)
    local state = test.ipc("flow")
    test.eq(state.stage, "editing", "the selection did not take")
    test.near(state.crop.x, 50, 2) test.near(state.crop.y, 120, 2)
    test.near(state.crop.w, 250, 2) test.near(state.crop.h, 380, 2)
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": a finger drags a crop handle and draws in the editor", function()
    phone(style)
    test.ipc("screenshot", "region") test.advance(600)
    test.touch("down", 1, 50, 120) test.advance(16)
    test.touch("move", 1, 300, 500) test.advance(16)
    test.touch("up", 1, 300, 500) test.advance(300)
    test.eq(test.ipc("flow").stage, "editing")
    local before = test.ipc("flow").crop
    local handle = test.get("capture-handle-se")
    local x, y = handle.x + handle.width / 2, handle.y + handle.height / 2
    test.swipe({ x, y }, { x - 60, y - 80 }, { id = 2, steps = 6, duration = 96 }) test.advance(200)
    local after = test.ipc("flow").crop
    test.truthy(after.w < before.w - 20 and after.h < before.h - 20, "the handle stayed where it was")
    test.click("capture-editor-draw") test.advance(220)
    test.click("capture-tool-pen") test.advance(220)
    test.touch("down", 3, 80, 160) test.touch("up", 3, 80, 160) test.advance(220)
    local moved = test.ipc("flow").moves
    test.swipe({ 80, 160 }, { 150, 220 }, { id = 4, steps = 6, duration = 96 }) test.advance(200)
    test.truthy(test.ipc("flow").moves - moved >= 3, "the pen missed the finger's way")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": a tap takes a window", function()
    phone(style)
    test.ipc("screenshot", "window") test.advance(600)
    test.touch("down", 1, 100, 300) test.advance(16)
    test.touch("up", 1, 100, 300) test.advance(300)
    local state = test.ipc("flow")
    test.eq(state.stage, "editing")
    test.near(state.crop.w, 300, 2)
  end)

  test.it(style .. ": a tap on the thumbnail opens the editor", function()
    phone(style)
    test.ipc("screenshot", "screen", "how=save") test.advance(900)
    test.truthy(test.ipc("flow").thumb ~= "")
    local name
    for _, one in ipairs(test.surfaces()) do
      if tostring(one.label):find("eva-capture-thumb", 1, true) then name = one.label end
    end
    test.touch("down", 1, 60, 50, { surface = name }) test.advance(16)
    test.touch("up", 1, 60, 50, { surface = name }) test.advance(400)
    test.truthy(test.ipc("flow").active, "a tap did not open it")
  end)

  test.it(style .. ": the panel's history opens under a finger", function()
    phone(style)
    test.ipc("capture", "open") test.settle(1000)
    local box = test.get("capture-history-open")
    test.touch("down", 1, box.x + box.width / 2, box.y + box.height / 2) test.advance(16)
    test.touch("up", 1, box.x + box.width / 2, box.y + box.height / 2) test.advance(800)
    test.truthy(test.find { id = "capture-history", visible = true }, "a tap did not open it")
  end)
end
