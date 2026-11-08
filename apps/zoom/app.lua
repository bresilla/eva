-- eva-zoom: a magnifier. With a word (in, out, reset, a number) it steps
-- Hyprland's cursor zoom and ends; asked for the lens (EVA_ZOOM_LENS) it is a
-- lens alone over the frozen screen. The slider is a page of the Tools window
-- (page.lua).
local morf = require("morf")
local frame = require("common.frame")
local model = require("apps.zoom.model")
local view = require("apps.zoom.view")

model.load()

morf.ipc.state = function()
  local at = model.at:get()
  return { factor = model.factor:get(), cursor = model.cursor:get(), radius = model.radius:get(), x = at.x, y = at.y,
    open = model.picture:get() ~= nil, native = model.native(), message = model.message:get() }
end
morf.ipc.point = function(x, y) model.point(tonumber(x), tonumber(y)) return true end
morf.ipc.set = function(value) model.set(tonumber(value)) return true end

local word = morf.operands[1]
if word then
  frame.quiet(false)
  model.command(word, function() morf.quit() end)
  return
end

local function done()
  model.close()
  morf.quit()
end
local asked = morf.env("EVA_ZOOM_LENS")
if not asked or asked == "" then asked = "lens" end
frame.quiet(true)
view.overlay(done)
frame.on_second(function() done() return true end)
morf.ipc.lens = function(step) return model.lens_word(step, done) end
if asked == "lens" then model.open() else model.lens_word(asked, done) end
