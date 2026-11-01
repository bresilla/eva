-- eva-find: where the pointer is. A spotlight, crosshairs through it, or rings on
-- a press, over the whole screen; a second launch shuts it.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

frame.quiet(true)
model.choose(morf.env("EVA_FIND_MODE") or morf.operands[1])
model.start()
view.overlay()
frame.on_second(function() model.finish() return true end)

morf.ipc.state = function()
  local at = model.at:get()
  return { mode = model.mode:get(), x = at.x, y = at.y, known = model.known:get(), up = model.up:get(),
    leaving = model.leaving:get(), rings = model.rings:len() }
end
morf.ipc.point = function(x, y) model.point(tonumber(x), tonumber(y)) return true end
morf.ipc.ripple = function(x, y) model.ripple(tonumber(x), tonumber(y)) return true end
morf.ipc.finish = function() model.finish() return true end
