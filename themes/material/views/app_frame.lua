-- A tool window's frame in Material: the shell's rounded opening, its tabs
-- growing out of the band on circular seams, the same inward shadow.
local ui = require("morf.ui")
local theme = require("theme")
local V = {}

--- `spec`: `id`, `edge` (the band's width), `tabs` (`{ node, right }`, each a
--- box of the band reaching into the opening). Returns the field.
function V.build(spec)
  local round = theme.ROUNDING
  local field = {
    id = spec.id .. "-frame", anchors = { fill = true }, fill_color = function() return theme.color.surface end,
    blend = theme.SEAM, blend_profile = "circular", shadow_color = "#000000a0", shadow_blur = 6,
    ui.SdfShape { shape = "box", anchors = { fill = true } },
    ui.SdfShape {
      id = spec.id .. "-opening", shape = "box", operation = "subtract", radius = round,
      anchors = { fill = true, margins = spec.edge },
    },
  }
  for index, tab in ipairs(spec.tabs) do
    field[#field + 1] = ui.SdfShape {
      id = spec.id .. "-tab-" .. index, shape = "box", operation = "smooth_union", blend_group = index,
      track = tab.node, bottom_left_radius = tab.right and round or 0, bottom_right_radius = tab.right and 0 or round,
    }
  end
  return ui.Sdf(field)
end

return V
