-- eva-record's window, or with `indicator` the pill shown while one runs.
local morf = require("morf")
local ui = require("morf.ui")
local model = require("model")
local view = require("view")
local frame = require("common.frame")

model.check()

morf.ipc.state = function()
  return { target = model.target:get(), audio = model.audio:get(), recording = model.recording:get(),
    elapsed = model.elapsed:get(), message = model.message:get() }
end

if morf.operands[1] == "indicator" then
  ui.Item { width = 1, height = 1 }
  morf.surface.layer = "background"
  morf.surface.width, morf.surface.height = 1, 1
  morf.surface.keyboard_focus = "none"
  frame.follow_scheme()
  view.indicator(function() morf.quit() end)
  return
end

frame.open {
  id = "record", title = "Record", width = 560, height = 460,
  build = function(w, h) return view.build(w, h) end,
}
