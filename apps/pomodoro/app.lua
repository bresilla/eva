-- eva-pomodoro: a focus timer. With a word it is a job on the session and ends;
-- the session itself is a file and a timer in eva-clock's store, so it goes on
-- with no window.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")

local how = morf.operands[1]
if how then
  frame.quiet()
  model.start_up(false, false)
  model.job(how, require("lib.shell.tool_job").finish)
  return
end

local view = require("view")

model.start_up(true, true)

frame.open {
  id = "pomodoro", title = "Pomodoro", width = 440, height = 680, minimum_height = 560,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  local session = model.session:get()
  return { phase = session.phase, running = session.running, left = model.left(), seconds = session.seconds,
    round = session.round, today = session.today, total = session.total, plan = session.plan,
    alarm = session.alarm, message = model.message:get() }
end
morf.ipc.start = function() return model.start() end
morf.ipc.pause = function() return model.pause() end
morf.ipc.skip = function() return model.skip() end
morf.ipc.reset = function() return model.reset() end
morf.ipc.plan = function(index) return model.set_plan(tonumber(index)) end
