-- Dashboard navigation and visibility. Visual packages own layout and motion.
local morf = require("morf")
local ui = require("morf.ui")
local state = require("dashboard_state")
local model = require("dashboard_model")
local M = { TERMINAL_TAB=6, tab=state.tab, month_offset=model.month_offset }
local visual = require("themes").view("dashboard").build(model)
M.size, M.bud = visual.size, visual.bud
-- Over a sheet's screen it rises from the bottom edge (the top is quick
-- settings').
local EDGE = require("responsive").sheets() and "bottom" or (visual.edge or "top")
M.drawer = require("drawer").new {
  name="dashboard",edge=EDGE,width=visual.width,height=visual.height,
  content=visual.content,props=visual.props,close_policy="escape+outside",
  corners=not require("responsive").sheets() and require("panel_room").corners(EDGE,visual.place) or nil,
}
morf.effect("eva.dashboard.shown",function() state.opened:set(M.drawer.open:get()) end)
morf.effect("eva.dashboard.presentation",function()
  for index,tab in ipairs(model.tabs) do
    require("presentation").set("dashboard."..tab.key,state.opened:get() and state.displayed:get()==index)
  end
end)
function M.edge_trigger()
  return require("hover").edge {name="dashboard",drawer=M.drawer,edge=EDGE,length=visual.width,
    setting="dashboard.hover",grace_ms=50}
end
return M
