-- eva-startup: what starts with the session, and the scheduled jobs. With ARGS
-- it is a job with no window: `list`, `enable NAME`, `disable NAME`.
-- EVA_FAKE_STARTUP=1 puts a stand-in where systemd's timers would be.
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

model.refresh()
model.load_timers()

frame.open {
  id = "startup", title = "Startup", width = 640, height = 720,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  return { rows = model.rows:get(), timers = model.timers:get(), scheduled = model.scheduled:get(),
    message = model.message:get() }
end
morf.ipc.tab = function(name) return model.select(name) end
morf.ipc.enable = function(name)
  local row = model.find(name)
  if row then model.enable(row) end
  return row ~= nil
end
morf.ipc.disable = function(name)
  local row = model.find(name)
  if row then model.disable(row) end
  return row ~= nil
end
morf.ipc.command = function(name, command) return model.add_command(name, command) end
morf.ipc.search = function(query) model.query:set(query or "") return #model.matches() end
