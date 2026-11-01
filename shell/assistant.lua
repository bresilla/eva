-- The Assistant page: one model, whichever panel holds it; the selected theme
-- owns the view.
local M = {}
function M.build(ctx, w, h)
  local model = setmetatable({ active = ctx.active }, { __index = require("assistant_model") })
  return require("themes").view("assistant").build(model, w, h)
end
return M
