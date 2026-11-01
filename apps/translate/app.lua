-- eva-translate: free translation, offline where this machine can. With words
-- it is a job that answers and ends; the window sends nothing until pressed.
local morf = require("morf")
local frame = require("common.frame")
local job = require("lib.shell.tool_job")
local model = require("model")

model.load()

if morf.args[1] then
  frame.quiet()
  model.job(morf.args, job.input(), job.finish)
  return
end

local view = require("view")

frame.open {
  id = "translate", title = "Translate", width = 640, height = 760, minimum_width = 380, minimum_height = 640,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  local engine = model.current()
  local found = {}
  for index, item in ipairs(model.found:get()) do found[index] = item.id end
  return { input = model.input:get(), output = model.output:get(), source = model.source:get(), target = model.target:get(),
    engine = engine and engine.id or "", offline = engine ~= nil and engine.offline, found = found,
    privacy = model.privacy(), busy = model.busy:get(), detected = model.detected:get(), message = model.message:get() }
end
morf.ipc.input = function(...) model.input:set(table.concat({ ... }, " ")) return true end
morf.ipc.source = function(code) model.set_source(code) return true end
morf.ipc.target = function(code) model.set_target(code) return true end
morf.ipc.engine = function(id) model.set_engine(id) return true end
morf.ipc.go = function() return model.translate() end
morf.ipc.swap = function() model.swap() return true end
morf.ipc.paste = function(how) model.paste(how == "selection") return true end
morf.ipc.copy = function() return model.copy() end
