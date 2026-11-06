-- eva-monitor's page in the Tools window: the processes, the machine's resources
-- and its sensors, from the samples lib.services.sysinfo takes for the shell's
-- dashboard. Nothing is sampled for it while the page is not on show.
local model = require("apps.monitor.model")

local M = {}

local started, visible = false, false
local function ready()
  if started then return end
  started = true
  model.away:set(not visible)
  -- The dashboard's graphs read the same samples while it is open.
  model.shared = function()
    local dashboard = package.loaded.dashboard
    return dashboard ~= nil and dashboard.drawer.open:get()
  end
  model.start()
end

--- The page, `w` by `h`.
function M.build(w, h)
  ready()
  return require("apps.monitor.view").build(function() return w end, function() return h end)
end

function M.shown(on)
  visible = on
  if started then model.away:set(not on) end
end

--- Pause and play, in the window's head.
function M.actions() return require("apps.monitor.view").actions() end

-- `morf ipc call tool monitor VERB`.
M.verbs = {
  state = function()
    ready()
    local rows = {}
    for index = 1, math.min(model.rows:len(), 40) do
      local row = model.rows:get(index)
      rows[index] = { pid = row.pid, name = row.name, cpu = row.cpu, memory = row.memory, command = row.command,
        user = row.user }
    end
    return { tab = model.TABS[model.tab:get()], sort = model.sort:get(), query = model.query:get(), rows = rows,
      shown = model.shown:get(), count = model.count:get(), selected = model.selected:get(), detail = model.detail:get(),
      sent = model.sent:get(), message = model.message:get(), live = model.live(), speed = model.speed:get() }
  end,
  tab = function(name) return model.select_tab(name) end,
  sort = function(name) return model.select_sort(name) end,
  search = function(...) model.query:set(table.concat({ ... }, " ")) return true end,
  select = function(pid) model.select(pid) return true end,
  term = function(pid) return model.term(pid) end,
  kill = function(pid) return model.force(pid) end,
  pause = function(how) model.paused:set(how ~= "off") return true end,
  away = function(how) model.away:set(how ~= "off") return true end,
  speed = function(ms) model.set_speed(ms) return true end,
  sampling = function()
    local running = {}
    for name, source in pairs(require("lib.services.sysinfo").sources) do
      if source:running() then running[#running + 1] = name end
    end
    table.sort(running)
    return running
  end,
}

return M
