-- A tool window's frame in Tsugumori: the shell's square opening, its tabs cut
-- straight out of the band, registration marks at the corners.
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local C = theme.color
local V = {}

--- `spec`: `id`, `edge` (the band's width), `tabs` (`{ node, right }`, each a
--- box of the band reaching into the opening). Returns the field.
function V.build(spec)
  local field = {
    id = spec.id .. "-frame", anchors = { fill = true },
    fill_color = function() return C.surfaceContainerHigh end, blend = 0,
    ui.SdfShape { shape = "box", anchors = { fill = true } },
    ui.SdfShape {
      id = spec.id .. "-opening", shape = "box", operation = "subtract", radius = 0,
      anchors = { fill = true, margins = spec.edge },
    },
  }
  for index, tab in ipairs(spec.tabs) do
    field[#field + 1] = ui.SdfShape {
      id = spec.id .. "-tab-" .. index, shape = "box", operation = "smooth_union", blend_group = index,
      track = tab.node, radius = 0,
    }
  end
  return ui.Item {
    id = spec.id .. "-frame-host", anchors = { fill = true },
    ui.Sdf(field),
    ui.Item { anchors = { fill = true, margins = spec.edge }, kit.decor("corners", { length = 12 }) },
  }
end

return V
