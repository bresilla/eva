-- eva-clock: alarms, timers, a stopwatch and world clocks. The alarms and timers
-- are lib/services/alarm.lua's, which the shell's bar reads too.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

model.start()

frame.open {
  id = "clock", title = "Clock", width = 620, height = 720,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  return { items = model.alarm.items:get(), ongoing = model.alarm.ongoing:get(), rang = model.alarm.rang:get(),
    world = model.world:get(), laps = model.laps:get(), running = model.running:get(),
    elapsed = model.elapsed(), message = model.alarm.message:get() }
end
morf.ipc.add = function(...) return model.add(table.concat({ ... }, " ")) ~= nil end
morf.ipc.tab = function(name) return model.select(name) end
morf.ipc.watch = function(how) model.stopwatch(how) return true end
morf.ipc.city = function(name) return model.add_city(name) end
