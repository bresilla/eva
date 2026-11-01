-- The side panels: shared geometry; the tab row and pages come from the kit.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local V = {}
function V.build(model)
  -- From the top it is a sheet, its tabs icons alone: the desk's width on a
  -- phone held upright, elsewhere a panel under the status, and as tall as the
  -- page on show wants, up to its most. From a side, the side's height.
  local responsive = require("responsive")
  local top = model.edge == "top"
  local tabbed_layout = require("themes.layouts.tabbed")
  local function height()
    local _, h = model.desk_size()
    if not top then return h - 2 * theme.BORDER end
    -- A sheet leaves at least a fifth of the desk below it, to tap it shut.
    local most = responsive.panel_height(h)
    local wanted = model.fit()
    if not wanted then return most end
    return math.min(most, math.ceil(wanted) + tabbed_layout.TABS_H + 2 * tabbed_layout.PAD)
  end
  local function page_width()
    if not top then return theme.SIDE_W end
    return responsive.panel_width()
  end
  local tabs = {}
  for i, tab in ipairs(model.tabs) do
    tabs[i] = { key = tab.key, name = tab.name, icon = tab.icon,
      build = function(w, h) return model.page(tab.key, w, h) end }
  end
  local panel = require("kit").tabbed {
    id = model.id, width = page_width(), height = height, tabs = tabs,
    tab = model.tab, publish = false,
    close = function() require(model.id).drawer.set(false) end,
    dismiss = ({ top = "up", left = "left", right = "right" })[model.edge],
    on_present = model.present, icons_only = top,
  }
  morf.effect("material." .. model.id .. ".shown", function() panel.shown(model.opened:get()) end)
  local content = panel.content
  if model.edge == "right" then
    content = ui.Item { anchors = { fill = true, left_margin = theme.STRIP }, content }
  end
  if top then
    return { width = page_width(), height = height, edge = "top",
      content = content, props = { anchors = responsive.panel_anchors(),
        behavior = { height = theme.spring.drawer } } }
  end
  return { width = theme.SIDE_W + theme.STRIP, height = height, edge = model.edge,
    content = content, props = { anchors = { top = true, [model.edge] = true } } }
end
return V
