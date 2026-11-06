-- eva-text's page in the Tools window: a developer's scratchpad, its transforms
-- and generators: case, lines, encodings, JSON, hashes, UUIDs, passwords.
local model = require("apps.text.model")

local M = {}

--- The page, `w` by `h`.
function M.build(w, h)
  return require("apps.text.view").build(function() return w end, function() return h end)
end

-- `morf ipc call tool text VERB`.
M.verbs = {
  state = function()
    return { text = model.text:get(), tab = model.tab:get(), undo = model.undoing:get(), made = model.made:get(),
      message = model.message:get() }
  end,
  text = function(...) model.text:set(table.concat({ ... }, " ")) return true end,
  apply = function(id) return model.apply(id) end,
  undo = function() return model.undo() end,
  tab = function(index) model.tab:set(tonumber(index)) return true end,
  make = function(kind)
    if kind == "passphrase" then model.make_passphrase() else model.make_password() end
    return true
  end,
  uuid = function() model.uuid() return true end,
  copy_secret = function() return model.copy_secret() end,
}

return M
