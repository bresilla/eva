-- The bottom workspace: a side panel's model over `panels.bottom`'s pages.
-- Visual themes receive it; they do not own integrations or settings.
local M = {}
function M.new()
  local tabs, bind = require("pages").tabs("bottom")
  local model = require("side_panel_model").new { id = "bottom", edge = "bottom", tabs = tabs }
  bind(model)
  return model
end
return M
