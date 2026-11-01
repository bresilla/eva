-- eva-standby: a clock for a phone or a tablet on its charger. It holds the screen
-- awake while it shows, and a second launch, Escape or a press of Close ends it.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

model.start(morf.args)

frame.quiet(true)
local layer = frame.overlay { id = "standby", root = view.root() }
frame.on_second(function() return model.quit() end)

-- Off the screen as soon as it is leaving.
morf.effect("standby.leaving", function()
  if model.leaving:get() then layer.visible = false end
end)

morf.ipc.state = function()
  local upcoming = model.alarm.next()
  return { view = model.VIEWS[model.view:get()], night = model.night:get(), held = model.held:get(),
    leaving = model.leaving:get(), power = model.power:get(), message = model.message:get(),
    cities = #model.world:get(), upcoming = upcoming and upcoming.label or nil, seconds = model.seconds:get() }
end
morf.ipc.show = function(name) return model.select(name) end
morf.ipc.step = function(step) model.step(tonumber(step) or 1) return true end
morf.ipc.night = function(how) model.set_night(how ~= "off") return true end
morf.ipc.quit = function() return model.quit() end
