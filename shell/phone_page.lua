-- The Phone page: one model, wherever the page stands; the theme owns the view.
local morf = require("morf")
local M = {}
function M.build(active, w, h)
  local model = require("phone_model")
  local node, head = require("themes").view("phone").build(model, active, w, h)
  morf.effect("eva.phone.watch", function()
    local on = active()
    morf.time.timer(1, function() model.watch(on) end, false)
  end, { owner = node })
  return node, head
end
return M
