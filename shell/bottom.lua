-- Bottom workspace lifecycle and navigation; each theme owns its composition.
-- There is no bottom panel on a sheets form: its pages are the sheet's, so
-- what asks for this one is answered by the sheet.
if require("responsive").sheets() then return require("sidebar") end
local morf = require("morf")
local room = require("panel_room")
local model = require("bottom_model").new()
local view = require("themes").view("bottom").build(model)
local M = { TABS = model.tabs, panel = model }
M.width = type(view.width) == "function" and view.width or function() return view.width end
M.height = type(view.height) == "function" and view.height or function() return view.height end
M.WIDTH = M.width()
M.drawer = require("drawer").new {
  name = "bottom", edge = view.edge or "bottom", width = view.width, height = view.height,
  content = view.content, props = view.props, close_policy = "escape+outside",
  can_open = function() return #model.tabs > 0 end,
  corners = room.corners("bottom", function() return room.span(room.WANT, room.LEAST) end),
}
require("pages").publish("bottom", M)
morf.effect("eva.bottom.shown", function() model.opened:set(M.drawer.open:get()) end)
return M
