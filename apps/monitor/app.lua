-- eva-monitor: the processes, the machine's resources and its sensors, all from
-- the samples lib.services.sysinfo takes for the shell's dashboard.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

model.start()

frame.open {
  id = "monitor", title = "Monitor", width = 1040, height = 760,
  actions = function() return view.actions() end,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  local rows = {}
  for index = 1, math.min(model.rows:len(), 40) do
    local row = model.rows:get(index)
    rows[index] = { pid = row.pid, name = row.name, cpu = row.cpu, memory = row.memory, command = row.command, user = row.user }
  end
  return { tab = model.TABS[model.tab:get()], sort = model.sort:get(), query = model.query:get(), rows = rows,
    shown = model.shown:get(), count = model.count:get(), selected = model.selected:get(), detail = model.detail:get(),
    sent = model.sent:get(), message = model.message:get(), live = model.live(), speed = model.speed:get() }
end
morf.ipc.tab = function(name) return model.select_tab(name) end
morf.ipc.sort = function(name) return model.select_sort(name) end
morf.ipc.search = function(...) model.query:set(table.concat({ ... }, " ")) return true end
morf.ipc.select = function(pid) model.select(pid) return true end
morf.ipc.term = function(pid) return model.term(pid) end
morf.ipc.kill = function(pid) return model.force(pid) end
morf.ipc.pause = function(how) model.paused:set(how ~= "off") return true end
morf.ipc.away = function(how) model.away:set(how ~= "off") return true end
morf.ipc.speed = function(ms) model.set_speed(ms) return true end
morf.ipc.sampling = function()
  local running = {}
  for name, source in pairs(require("lib.services.sysinfo").sources) do
    if source:running() then running[#running + 1] = name end
  end
  table.sort(running)
  return running
end
