-- eva-clock's page in the Tools window: a line that takes what you say, over
-- alarms, timers, the stopwatch and world clocks. The stopwatch is followed on
-- screen only while the page is on show.
local model = require("apps.clock.model")

local M = {}

local started = false
local function ready()
  if started then return end
  started = true
  model.start()
end

--- The page, `w` by `h`.
function M.build(w, h)
  ready()
  return require("apps.clock.view").build(function() return w end, function() return h end)
end

function M.shown(on)
  if on and started then model.tick() else model.rest() end
end

-- `morf ipc call tool clock VERB`.
M.verbs = {
  state = function()
    ready()
    return { items = model.alarm.items:get(), ongoing = model.alarm.ongoing:get(), rang = model.alarm.rang:get(),
      world = model.world:get(), laps = model.laps:get(), running = model.running:get(),
      elapsed = model.elapsed(), message = model.alarm.message:get() }
  end,
  add = function(...) ready() return model.add(table.concat({ ... }, " ")) ~= nil end,
  tab = function(name) return model.select(name) end,
  watch = function(how) ready() model.stopwatch(how) return true end,
  city = function(name) ready() return model.add_city(name) end,
}

return M
