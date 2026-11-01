-- The side panels: shared geometry; the tab row and pages come from the kit.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local V = {}
function V.build(model)
  -- From the top it is a sheet: on a phone held upright the desk's width and
  -- four fifths of its height, its tabs icons alone; elsewhere a panel under
  -- the status. From a side, the side's height.
  local responsive = require("responsive")
  local top = model.edge == "top"
  local function height()
    local _, h = model.desk_size()
    -- A sheet leaves the desk below it, to tap it shut.
    if top then return responsive.panel_height(h) end
    return h - 2 * theme.BORDER
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
    on_present = model.present, icons_only = top and responsive.compact(),
  }
  morf.effect("material." .. model.id .. ".shown", function() panel.shown(model.opened:get()) end)
  local content = panel.content
  if model.edge == "right" then
    content = ui.Item { anchors = { fill = true, left_margin = theme.STRIP }, content }
  end
  if top then
    return { width = page_width(), height = height, edge = "top",
      content = content, props = { anchors = responsive.panel_anchors() } }
  end
  return { width = theme.SIDE_W + theme.STRIP, height = height, edge = model.edge,
    content = content, props = { anchors = { top = true, [model.edge] = true } } }
end
return V
