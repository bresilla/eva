-- eva-draw: draw on the screen, as ZoomIt does. Strokes and words over
-- everything, until Escape or a second launch.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

frame.quiet(true)
view.overlay(function() morf.quit() end)
frame.on_second(function() morf.quit() return true end)

morf.ipc.state = function()
  return { marks = model.marks:len(), drawing = model.drawing:get(), pen = model.pen:get(), width = model.width:get(),
    writing = model.writing:get(), board = model.board:get(), typing = model.typing:get() ~= nil }
end
morf.ipc.stroke = function(line)
  local started = false
  for x, y in line:gmatch("(%d+)%s+(%d+)") do
    if started then model.move(tonumber(x), tonumber(y)) else model.begin(tonumber(x), tonumber(y)) end
    started = true
  end
  model.finish()
  return true
end
morf.ipc.pen = function(name) return model.choose(name) end
morf.ipc.width = function(index) model.width:set(tonumber(index)) return true end
morf.ipc.undo = function() model.undo() return true end
morf.ipc.clear = function() model.clear() return true end
morf.ipc.write = function(x, y, ...)
  model.place(tonumber(x), tonumber(y))
  model.type(table.concat({ ... }, " "))
  model.commit()
  return true
end
morf.ipc.board = function() model.board:set(not model.board:get()) return true end
