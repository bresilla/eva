-- Settings/history navigation and notification coverage. Themes own the
-- drawer geometry and the timing at which a selected page is presented.
local morf = require("morf")
local ui = require("morf.ui")
local notifs = require("notifs")
local history = require("notification_history")
-- Its pages are the `panels.right` setting's (shell/pages.lua); on a phone it
-- comes down from the top, as quick settings do, with `panels.top`'s -- the
-- side edges are the workspaces' there.
local SHEET = require("responsive").sheets()
local tabs, bind = require("pages").tabs(SHEET and "top" or "right")
local model = require("side_panel_model").new {
  id = "sidebar", edge = SHEET and "top" or "right", tabs = tabs,
}
bind(model)
local view = require("themes").view("side_panel").build(model)
local M = { groups = history.groups, clear = history.clear, TABS = model.tabs, panel = model,
  tab = model.tab, select = model.select, showing = model.showing, height = view.height }
M.drawer = require("drawer").new {
  name = "sidebar", edge = view.edge, width = view.width, height = view.height,
  content = view.content, props = view.props, close_policy = "escape+outside",
  can_open = function() return #model.tabs > 0 end,
}
local pages = require("pages")
pages.publish("sidebar", M)
morf.effect("eva.sidebar.covered", function()
  notifs.covered:set(pages.on_show("notifications"))
end)
morf.effect("eva.sidebar.shown", function() model.opened:set(M.drawer.open:get()) end)
-- The Lule studio works while its page is on show: the panel holding
-- Settings open on it, at Theme, Lule.
morf.effect("eva.sidebar.lule", function()
  local studio = require("lule_studio")
  local settings = require("utilities")
  if not (studio.active and settings.displayed) then return end
  local page = settings.displayed:get()
  studio.active:set(pages.on_show("settings") and page == "theme/lule")
end)
return M
