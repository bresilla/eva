-- eva-large: Large Type. Words huge across the screen, from the arguments, the
-- cli's stdin or the clipboard, until a press or Escape.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

frame.quiet(true)
view.overlay()
model.load()
frame.on_second(function() model.finish() return true end)

morf.ipc.state = function()
  return { text = model.text:get(), from = model.from:get(), qr = model.qr:get(), leaving = model.leaving:get() }
end
morf.ipc.show = function(...) model.show(table.concat({ ... }, " "), "arguments") return true end
morf.ipc.finish = function() model.finish() return true end
