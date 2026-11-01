-- eva-awake: keep the session awake for a chosen time, through the shell's own
-- keep awake. With ARGS it is a job with no window: `30m`, `off`, `status`,
-- `--pid N`.
local morf = require("morf")

if morf.args[1] then
  local job = require("lib.util.job")
  job.quiet()
  require("model").job(morf.args, job.finish)
  return
end

local frame = require("common.frame")
local model = require("model")
local view = require("view")

model.start()

frame.open {
  id = "awake", title = "Keep awake", width = 520, height = 660,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  return { on = model.on:get(), ["until"] = model.stop:get(), left = model.left(), fraction = model.fraction(),
    up = model.up:get(), message = model.message:get() }
end
morf.ipc.keep = function(minutes) model.keep(tonumber(minutes)) return true end
morf.ipc.say = function(...) return model.say(table.concat({ ... }, " ")) end
morf.ipc.forever = function() model.forever() return true end
morf.ipc.off = function() model.off() return true end
morf.ipc.ask = function() model.ask() return true end
