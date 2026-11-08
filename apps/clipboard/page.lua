-- eva-clipboard's page in the Tools window: the history `eva-clipboard --watch`
-- keeps, searched, copied back by a press, pinned and cleared. The page reads
-- the store and follows its file; it records nothing itself.
local model = require("apps.clipboard.model")

local M = {}

local ready = false
local function load()
  if ready then return end
  ready = true
  model.load()
  model.follow()
end

--- The page, `w` by `h`.
function M.build(w, h)
  load()
  return require("apps.clipboard.view").build(function() return w end, function() return h end)
end

-- `morf ipc call tool clipboard VERB`.
M.verbs = {
  state = function()
    load()
    return { items = model.items:get(), found = #model.found(), message = model.message:get() }
  end,
  text = function(text) load() model.text(text) return true end,
  pin = function(id) load() model.toggle_pin(id) return true end,
  clear = function() load() model.clear() return true end,
}

return M
