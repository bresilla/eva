-- The Drop page: one model, whichever panel holds it; the selected theme owns
-- the view.
local morf = require("morf")
local M = {}
function M.build(ctx, w, h)
  local model = require("drop_model")
  local node, head = require("themes").view("drop").build(model, ctx.active, w, h)
  morf.effect("eva.drop.watch", function()
    local on = ctx.active()
    morf.time.timer(1, function() model.watch(on) end, false)
  end, { owner = node })
  return node, head
end
return M
