-- The left panel's navigation. The selected theme owns the drawer dimensions,
-- tab strip, pages and transitions.
-- There is no left panel on a sheets form: its pages are the sheet's, so what
-- asks for this one is answered by the sheet.
if require("responsive").sheets() then return require("sidebar") end
local morf = require("morf")
-- Its pages are the `panels.left` setting's (shell/pages.lua).
local tabs, bind = require("pages").tabs("left")
local model = require("side_panel_model").new { id = "leftbar", edge = "left", tabs = tabs }
bind(model)
local view = require("themes").view("side_panel").build(model)
local M = { TABS = model.tabs, panel = model, WIDTH = view.width }
M.height = view.height
M.drawer = require("drawer").new {
  name = "leftbar", edge = view.edge, width = view.width, height = view.height,
  content = view.content, props = view.props, close_policy = "escape+outside",
  can_open = function() return #model.tabs > 0 end,
}
require("pages").publish("leftbar", M)
morf.effect("eva.leftbar.shown", function() model.opened:set(M.drawer.open:get()) end)
return M
