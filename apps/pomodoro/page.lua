-- eva-pomodoro's page in the Tools window: a focus timer of work and breaks.
-- The session is a file and a timer in eva-clock's store, which the shell's
-- own alarms ring, so it goes on with the page shut.
local model = require("apps.pomodoro.model")

local M = {}

local started = false
local function ready()
  if started then return end
  started = true
  model.start_up(false, true)
end

--- The page, `w` by `h`.
function M.build(w, h)
  ready()
  return require("apps.pomodoro.view").build(function() return w end, function() return h end)
end

-- `morf ipc call tool pomodoro VERB`.
M.verbs = {
  state = function()
    ready()
    local session = model.session:get()
    return { phase = session.phase, running = session.running, left = model.left(), seconds = session.seconds,
      round = session.round, today = session.today, total = session.total, plan = session.plan,
      alarm = session.alarm, message = model.message:get() }
  end,
  start = function() ready() return model.start() end,
  pause = function() ready() return model.pause() end,
  skip = function() ready() return model.skip() end,
  reset = function() ready() return model.reset() end,
  plan = function(index) ready() return model.set_plan(tonumber(index)) end,
}

return M
