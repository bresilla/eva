-- eva-keys as Settings' Keyboard shortcuts page, under Keyboard: the live
-- bindings of the compositor and the shell's own as one searchable list, and a
-- new chord for any row.
local model = require("apps.keys.model")

local M = {}

local loaded = false

--- The page, `w` by `h`.
function M.build(w, h)
  if not loaded then
    loaded = true
    model.load()
  end
  return require("apps.keys.view").build(function() return w end, function() return h end)
end

-- What the specs and scenarios ask of it, as the tool's window answered.
M.verbs = {
  state = function()
    return { rows = #model.rows:get(), found = #model.found(), query = model.query:get(),
      message = model.message:get(), recording = model.recording:get(), pending = model.clash_text() }
  end,
  search = function(query) model.query:set(query or "") return #model.found() end,
  -- `row CHORD`: the row a chord is on.
  row = function(chord)
    local rows = require("key_rows")
    local normal = rows.normal(chord)
    for _, row in ipairs(model.rows:get()) do
      if rows.normal(row.keys) == normal then return row end
    end
  end,
  reload = function() model.load() return true end,
  record = function(id) return model.record(id) end,
  stop = function() model.stop() return true end,
  confirm = function() return model.confirm() end,
  reset = function(id) model.reset(id) return true end,
}

return M
