-- eva-logs' page in the Tools window: the journal, live, by priority, boot, unit
-- and words. journalctl follows it only while the page is on show.
local model = require("apps.logs.model")

local M = {}

local started, visible, unit = false, false, nil
local function ready()
  if started then return end
  started = true
  model.start(unit)
  if not visible then model.stop() end
end

--- The page, `w` by `h`.
function M.build(w, h)
  ready()
  return require("apps.logs.view").build(function() return w end, function() return h end)
end

--- `eva-logs UNIT`: the journal narrowed to that unit.
function M.open(args)
  if not args[1] or args[1] == "" then return end
  if started then model.set_unit(args[1]) else unit = args[1] end
end

function M.shown(on)
  if on == visible then return end
  visible = on
  if not started then return end
  if on then model.load() else model.stop() end
end

--- Follow and hold, in the window's head.
function M.actions() return require("apps.logs.view").actions() end

-- `morf ipc call tool logs VERB`.
M.verbs = {
  state = function()
    local rows = {}
    for index = 1, math.min(model.rows:len(), 40) do
      local row = model.rows:get(index)
      rows[index] = { key = row.key, name = row.name, priority = row.priority, text = row.text, unit = row.unit }
    end
    return { rows = rows, shown = model.shown:get(), kept = model.kept:get(), running = model.running:get(),
      query = model.query:get(), unit = model.unit:get(), priority = model.priority:get(), boot = model.boot:get(),
      selected = model.selected:get(), message = model.message:get(), argv = model.argv(model.follow:get()) }
  end,
  search = function(...) model.query:set(table.concat({ ... }, " ")) return true end,
  grep = function(...) model.search(table.concat({ ... }, " ")) return true end,
  priority = function(index) model.set_priority(tonumber(index)) return true end,
  boot = function(index) model.set_boot(tonumber(index)) return true end,
  unit = function(name) model.set_unit(name) return true end,
  follow = function(how) model.set_follow(how ~= "off") return true end,
  select = function(index) model.select_row(tonumber(index)) return true end,
  close = function() model.select("") return true end,
  copy = function() return model.copy() end,
}

return M
