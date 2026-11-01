-- A list model of a view's own, following one a shared model keeps. A page can
-- stand in two panels at once, and each copy repeats over its own list.
--
--     local keeper = ui.Item { width = 1, height = 1 }   -- placed in the view
--     ui.Repeater { model = mirror.new(model.rows, "id", keeper), ... }
local morf = require("morf")
local M = {}
local made = 0

--- A list that follows `source`, matched by the field `key`, for as long as
--- the node `owner` stands.
function M.new(source, key, owner)
  local rows = morf.list_model({})
  made = made + 1
  morf.effect("mirror." .. made, function()
    local out = {}
    for i = 1, source:len() do out[i] = source:get(i) end
    rows:replace(out, key)
  end, { owner = owner })
  return rows
end

return M
