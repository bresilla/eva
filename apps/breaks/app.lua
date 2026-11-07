-- eva-breaks: break reminders. `--watch` is the session's process, with no
-- window; `status` and `pause MINUTES`, jobs that end. What configures it and
-- shows the day is Settings' Breaks page (page.lua).
local morf = require("morf")

local first = morf.args[1]
if first ~= "--watch" then
  local job = require("lib.util.job")
  job.quiet()
  require("apps.breaks.model").job(morf.args, job.finish)
  return
end

local frame = require("common.frame")
local model = require("apps.breaks.model")
local view = require("apps.breaks.view")

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
