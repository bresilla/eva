-- eva-keys: a searchable list of the live bindings, each of which can be given
-- a new chord.
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
  return { rows = #model.rows:get(), found = #model.found(), query = model.query:get(), message = model.message:get(),
    recording = model.recording:get(), pending = model.clash_text() }
end
morf.ipc.search = function(query) model.query:set(query or "") return #model.found() end
-- `row CHORD`: the row a chord is on.
morf.ipc.row = function(chord)
  local normal = require("key_rows").normal(chord)
  for _, row in ipairs(model.rows:get()) do
    if require("key_rows").normal(row.keys) == normal then return row end
  end
end
morf.ipc.reload = function() model.load() return true end
morf.ipc.record = function(id) return model.record(id) end
morf.ipc.stop = function() model.stop() return true end
morf.ipc.confirm = function() return model.confirm() end
morf.ipc.reset = function(id) model.reset(id) return true end
