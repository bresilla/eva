-- The bottom workspace: shared dimensions; the tabbed body comes from the kit.
-- As wide as it chooses, among the side panels (shell/panel_room.lua), and as
-- tall as the page on show stands, up to three fifths of the desk.
local morf = require("morf")
local theme = require("theme")
local V = {}
local TALLEST = 1252
function V.build(model)
  local room = require("panel_room")
  local tabbed_layout = require("themes.layouts.tabbed")
  local function x() return (room.span(room.WANT, room.LEAST)) end
  local function width() return select(2, room.span(room.WANT, room.LEAST)) end
  local function height()
    local _, h = model.desk_size()
    local most = math.floor(math.min(TALLEST, h - 2 * theme.BORDER - 40) * .6)
    local wanted = model.fit()
    if not wanted then return most end
    return math.min(most, math.ceil(wanted) + tabbed_layout.TABS_H + 2 * tabbed_layout.PAD)
  end
  local tabs = {}
  for i, tab in ipairs(model.tabs) do
    tabs[i] = { key = tab.key, name = tab.name, icon = tab.icon,
      build = function(w, h) return model.page(tab.key, w, h) end }
  end
  local panel = require("kit").tabbed { id = "bottom", width = width, height = height,
    tabs = tabs, tab = model.tab, publish = false, on_present = model.present, dismiss = "down",
    close = function() require("bottom").drawer.set(false) end }
  morf.effect("material.bottom.shown", function() panel.shown(model.opened:get()) end)
  return { width = width, height = height, content = panel.content,
    props = { anchors = { bottom = true }, x = x,
      behavior = { x = theme.spring.drawer, width = theme.spring.drawer, height = theme.spring.drawer } } }
end
return V
