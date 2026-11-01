-- eva-keys: a searchable cheat sheet of the live bindings.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

model.load()

frame.open {
  id = "keys", title = "Keys", width = 820, height = 640,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  return { rows = #model.rows:get(), found = #model.found(), query = model.query:get(), message = model.message:get() }
end
morf.ipc.search = function(query) model.query:set(query or "") return #model.found() end
