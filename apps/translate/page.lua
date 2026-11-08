-- eva-translate's page in the Tools window: free translation, offline with Argos
-- where it is set up. Text leaves the machine only on a press, and the page
-- says when an online engine is in use.
local model = require("apps.translate.model")

local M = {}

local loaded = false
local function load()
  if loaded then return end
  loaded = true
  model.load()
end

--- The page, `w` by `h`.
function M.build(w, h)
  load()
  return require("apps.translate.view").build(function() return w end, function() return h end)
end

-- `morf ipc call tool translate VERB`.
M.verbs = {
  state = function()
    load()
    local engine = model.current()
    local found = {}
    for index, item in ipairs(model.found:get()) do found[index] = item.id end
    return { input = model.input:get(), output = model.output:get(), source = model.source:get(),
      target = model.target:get(), engine = engine and engine.id or "", offline = engine ~= nil and engine.offline,
      found = found, privacy = model.privacy(), busy = model.busy:get(), detected = model.detected:get(),
      message = model.message:get() }
  end,
  input = function(...) model.input:set(table.concat({ ... }, " ")) return true end,
  source = function(code) load() model.set_source(code) return true end,
  target = function(code) load() model.set_target(code) return true end,
  engine = function(id) load() model.set_engine(id) return true end,
  go = function() load() return model.translate() end,
  swap = function() model.swap() return true end,
  paste = function(how) model.paste(how == "selection") return true end,
  copy = function() return model.copy() end,
}

return M
