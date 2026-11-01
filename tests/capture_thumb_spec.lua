-- The floating thumbnail after a shot: a surface of its own while it shows, a
-- press opens the editor, left alone it fades, and a switch turns it off.
--
--     morf test --no-dbus tests/capture_thumb_spec.lua
local test = morf.test

local TOOL = "../apps/screenshot/app.lua"

local SOURCE = [[
  local backend = require("lib.shell.capture")
  local scratch = morf.env("XDG_CACHE_HOME") .. "/capture-thumb"
  morf.fs.mkdir(scratch)
  local picture = scratch .. "/rendered.png"
  morf.fs.copy(morf.fs.join(morf.env("PWD"), "tests/fixtures/wallpaper.png"), picture)
  local quits = 0
  backend.windows = function(cb) cb({}) end
  backend.session = function()
    return { snapshot = function(_, cb) cb(true, { source = picture, width = 1200, height = 800 }) end,
      render = function(_, _, cb) morf.time.timer(5, function() cb(true, picture) end, false) end,
      close = function() end, remove = function() end }
  end
  backend.copy = function(_, cb) cb(true) end
  backend.save = function(path, target, cb) morf.fs.copy(path, target) cb(true, target) end
  morf.process.detach = function() end
  morf.quit = function() quits = quits + 1 end
  require("config").set("capture.folder", scratch .. "/shots")
  require("config").set("capture.thumbnail", true)
  require("config").set("capture.thumbnail_seconds", 5)
  require("app")
  local env = morf.env
  morf.env = function(key) if key == "EVA_DRY_RUN" then return "0" end return env(key) end
  local capture = require("capture")
  morf.shared("eva.capture.owner", ""):set("")
  morf.ipc.flow = function()
    local thumb = package.loaded.thumb
    return { editing = capture.editor.active:get(), held = capture.held:get(), quits = quits,
      thumb = thumb and thumb.showing:get() or "", loaded = thumb ~= nil, phase = capture.phase:get() }
  end
  morf.ipc.option = function(key, value) require("config").set("capture." .. key, value == "true") end
  morf.ipc.seconds = function(n) require("config").set("capture.thumbnail_seconds", tonumber(n)) end
]]

local function tool(style, options)
  options = options or {}
  test.load(TOOL, { source = SOURCE, size = options.size or { 1200, 800 }, args = options.args,
    env = { EVA_STYLE = style or "material", EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "" } })
  test.advance(300)
end

local function surface()
  for _, one in ipairs(test.surfaces()) do
    if one.name == "eva-capture-thumb" or tostring(one.label):find("eva-capture-thumb", 1, true) then return one end
  end
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": a saved shot floats in the corner, and fades left alone", function()
    tool(style, { size = { 1920, 1080 } })
    test.falsy(test.ipc("flow").loaded, "the thumbnail was loaded at rest")
    test.ipc("screenshot", "screen", "how=save") test.advance(900)
    local state = test.ipc("flow")
    test.contains(state.thumb, "/shots/capture_")
    test.eq(state.held, 1)
    local shown = surface()
    test.truthy(shown, "no surface of its own")
    test.truthy(shown.visible)
    test.truthy(shown.width <= 216 and shown.height <= 216, "not small")
    test.truthy(shown.x + shown.width < 1920 and shown.y + shown.height < 1080, "it left the screen")
    test.truthy(shown.x > 1920 / 2 and shown.y > 1080 / 2, "not in the corner")
    test.truthy(test.find { id = "capture-thumb-image" })
    test.advance(4000)
    test.truthy(surface(), "gone early")
    test.advance(1800)
    test.settle(300)
    state = test.ipc("flow")
    test.eq(state.thumb, "") test.eq(state.held, 0)
    test.falsy(surface(), "its surface stayed")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": a press opens it in the editor", function()
    tool(style)
    test.ipc("screenshot", "screen", "how=save") test.advance(900)
    local shot = test.ipc("flow").thumb
    test.truthy(shot ~= "")
    test.click("capture-thumb-press") test.advance(400)
    local state = test.ipc("flow")
    test.truthy(state.editing, "the editor did not open")
    test.eq(state.thumb, "") test.eq(state.held, 0)
    test.falsy(surface())
    test.truthy(morf.fs.exists(shot), "the saved shot went with it")
    test.key("Escape") test.advance(300)
    test.falsy(test.ipc("flow").editing)
    test.truthy(morf.fs.exists(shot))
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("a shot only copied floats from a private file, gone with it", function()
  tool()
  test.ipc("screenshot", "screen", "how=copy") test.advance(900)
  local shot = test.ipc("flow").thumb
  test.contains(shot, "capture-thumb-")
  test.truthy(morf.fs.exists(shot))
  test.ipc("seconds", 2)
  test.advance(6000) test.settle(300)
  test.falsy(morf.fs.exists(shot), "the private copy stayed")
end)

test.it("a private file opened in the editor goes when the editor ends", function()
  tool()
  test.ipc("screenshot", "screen", "how=copy") test.advance(900)
  local shot = test.ipc("flow").thumb
  test.click("capture-thumb-press") test.advance(400)
  test.truthy(test.ipc("flow").editing)
  test.truthy(morf.fs.exists(shot), "it went from under the editor")
  test.key("Escape") test.advance(300)
  test.falsy(morf.fs.exists(shot), "the private copy stayed")
end)

test.it("the switch turns it off", function()
  tool()
  test.ipc("option", "thumbnail", "false")
  test.ipc("screenshot", "screen", "how=save") test.advance(900)
  test.eq(test.ipc("flow").thumb, "")
  test.falsy(surface())
  test.ipc("option", "thumbnail", "true")
end)

test.it("a thumbnail is never in the next picture", function()
  tool()
  test.ipc("screenshot", "screen", "how=save") test.advance(900)
  test.truthy(test.ipc("flow").thumb ~= "")
  test.ipc("screenshot", "region") test.advance(10)
  test.eq(test.ipc("flow").thumb, "", "it stayed for the next shot")
  test.falsy(surface())
end)

test.it("a tool with nothing else to do stays for it, then ends", function()
  tool("material", { args = { "screenshot", "screen", "how=save" } })
  test.advance(1200)
  local state = test.ipc("flow")
  test.truthy(state.thumb ~= "") test.eq(state.quits, 0)
  test.advance(6000) test.settle(400)
  test.eq(test.ipc("flow").quits, 1, "it did not end after the thumbnail")
end)

test.it("fits a phone", function()
  tool("tsugumori", { size = { 412, 915 } })
  test.ipc("screenshot", "screen", "how=save") test.advance(900)
  local shown = surface()
  test.truthy(shown)
  test.truthy(shown.x >= 0 and shown.x + shown.width <= 412, "it left a phone's width")
end)
