-- The Notes page: one model, wherever the page stands; the theme owns the view.
local morf = require("morf")
local M = {}
function M.build(active, w, h)
  local model = require("notes_model")
  local node, head = require("themes").view("notes").build(model, active, w, h)
  morf.effect("eva.notes.watch", function()
    local on = active()
    morf.time.timer(1, function() model.watch(on) end, false)
  end, { owner = node })
  return node, head
end
return M
