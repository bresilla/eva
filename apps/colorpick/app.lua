-- eva-colorpick: the window, or with `--pick` the frozen screen alone: one
-- click copies a colour and ends, for a keybinding.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

model.load()

morf.ipc.state = function()
  local hover = model.hover:get()
  return { frozen = model.picture:get() ~= nil, hover = hover and hover.hex or "", picked = model.picked:get(),
    format = model.format:get(), recent = model.recent:get(), message = model.message:get() }
end
morf.ipc.freeze = function() model.freeze() return true end
morf.ipc.point = function(x, y) model.point(tonumber(x), tonumber(y), 1) return true end
morf.ipc.pick = function() return model.pick() end
morf.ipc.format = function(name) model.format:set(name) return true end
morf.ipc.lule = function(hex) model.send_to_lule(hex) return true end

if morf.operands[1] == "--pick" then
  frame.quiet(true)
  view.overlay(function() morf.quit() end)
  model.freeze()
  return
end

view.overlay(function() end)

frame.open {
  id = "colorpick", title = "Colour picker", width = 520, height = 460,
  on_close = function() model.thaw() end,
  build = function(w, h) return view.build(w, h) end,
}
