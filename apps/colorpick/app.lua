-- eva-colorpick --pick: the frozen screen with its magnifier; one click copies a
-- colour and ends. The formats and the recent colours are a page of the Tools
-- window (page.lua).
local morf = require("morf")
local frame = require("common.frame")
local model = require("apps.colorpick.model")
local view = require("apps.colorpick.view")

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

frame.quiet(true)
view.overlay(function() morf.quit() end)
model.freeze()
