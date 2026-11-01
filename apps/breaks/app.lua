-- eva-breaks: break reminders. `--watch` is the session's process, with no
-- window; plain, the window that configures it and shows the day; `status` and
-- `pause MINUTES`, jobs that end.
local morf = require("morf")

local first = morf.args[1]
if first and first ~= "--watch" then
  local job = require("lib.util.job")
  job.quiet()
  require("model").job(morf.args, job.finish)
  return
end

local frame = require("common.frame")
local model = require("model")

if first == "--watch" then
  local view = require("view")
  frame.quiet(true)
  view.overlay()
  if not model.watch() then
    morf.log("info", "eva-breaks: already watching")
    morf.quit()
    return
  end
  morf.ipc.state = function()
    return { status = model.status:get(), current = model.current:get(), settings = model.settings:get() }
  end
  morf.ipc.skip = function() model.skip() return true end
  morf.ipc.postpone = function() model.postpone() return true end
  morf.ipc.begin = function(kind) model.begin(kind) return true end
  frame.on_second(function() return true end)
  return
end

local view = require("view")

model.follow()

frame.open {
  id = "breaks", title = "Breaks", width = 560, height = 760,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  return { status = model.status:get(), settings = model.settings:get(), watching = model.watching(model.status:get()) }
end
morf.ipc.set = function(kind, field, value)
  if field == "on" then value = value == "true" else value = tonumber(value) end
  model.change(function(settings) settings[kind][field] = value end)
  return true
end
morf.ipc.pause = function(minutes) model.pause(tonumber(minutes)) return true end
