-- eva-webapp: a site as an app with its own desktop entry and icon. With ARGS it
-- is a job with no window: `add NAME URL [--icon FILE]`, `list`, `remove NAME`.
-- EVA_FAKE_WEBAPP=1 puts a stand-in where the web would be.
local morf = require("morf")

if morf.env("EVA_FAKE_WEBAPP") == "1" then require("fake").install() end

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

frame.open {
  id = "webapp", title = "Web apps", width = 640, height = 620,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  return { rows = model.rows:get(), message = model.message:get(), busy = model.busy:get() }
end
morf.ipc.add = function(name, url)
  model.name:set(name or "")
  model.url:set(url or "")
  model.submit()
  return true
end
morf.ipc.remove = function(name)
  local row = model.find(name)
  if row then model.remove(row) end
  return row ~= nil
end
