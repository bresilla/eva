-- eva-zoom: a magnifier. With a word (in, out, reset, a number) it steps
-- Hyprland's cursor zoom and ends; asked for the lens it is a lens alone; else the
-- small window with its slider.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

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

local asked = morf.env("EVA_ZOOM_LENS")
if asked and asked ~= "" then
  local function done()
    model.close()
    morf.quit()
  end
  frame.quiet(true)
  view.overlay(done)
  frame.on_second(function() done() return true end)
  morf.ipc.lens = function(step) return model.lens_word(step, done) end
  if asked == "lens" then model.open() else model.lens_word(asked, done) end
  return
end

local function shut() model.close() end
morf.ipc.lens = function(step) return model.lens_word(step, shut) end
view.overlay(shut)
if model.native() then model.read() end

frame.open {
  id = "zoom", title = "Zoom", width = 460, height = 360, minimum_height = 320,
  on_close = shut,
  build = function(w, h) return view.build(w, h, model.open) end,
}
