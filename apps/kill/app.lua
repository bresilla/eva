-- eva-kill: press a window to end it. `--active` ends the focused window with no
-- overlay, for a keybinding.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")

morf.ipc.state = function()
  local hover = model.hover:get()
  return { windows = #model.windows:get(), hover = hover and hover.title or "", armed = model.armed:get(),
    ended = model.ended:get(), leaving = model.leaving:get() }
end
morf.ipc.point = function(x, y) model.point(tonumber(x), tonumber(y)) return true end
morf.ipc.kill = function() return model.kill() end
morf.ipc.cancel = function() model.cancel() return true end

if morf.options.active then
  frame.quiet(false)
  model.active()
  return
end

local view = require("view")
frame.quiet(true)
view.overlay()
model.load()
frame.on_second(function() model.cancel() return true end)
