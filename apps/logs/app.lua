-- eva-logs: the journal, live. `eva-logs UNIT` opens narrowed to that unit.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

model.start(morf.operands[1])

frame.open {
  id = "logs", title = "Logs", width = 1040, height = 760,
  actions = function() return view.actions() end,
  on_close = function() model.stop() end,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  local rows = {}
  for index = 1, math.min(model.rows:len(), 40) do
    local row = model.rows:get(index)
    rows[index] = { key = row.key, name = row.name, priority = row.priority, text = row.text, unit = row.unit }
  end
  return { rows = rows, shown = model.shown:get(), kept = model.kept:get(), running = model.running:get(),
    query = model.query:get(), unit = model.unit:get(), priority = model.priority:get(), boot = model.boot:get(),
    selected = model.selected:get(), message = model.message:get(), argv = model.argv(model.follow:get()) }
end
morf.ipc.search = function(...) model.query:set(table.concat({ ... }, " ")) return true end
morf.ipc.grep = function(...) model.search(table.concat({ ... }, " ")) return true end
morf.ipc.priority = function(index) model.set_priority(tonumber(index)) return true end
morf.ipc.boot = function(index) model.set_boot(tonumber(index)) return true end
morf.ipc.unit = function(name) model.set_unit(name) return true end
morf.ipc.follow = function(how) model.set_follow(how ~= "off") return true end
morf.ipc.select = function(index) model.select_row(tonumber(index)) return true end
morf.ipc.close = function() model.select("") return true end
morf.ipc.copy = function() return model.copy() end
