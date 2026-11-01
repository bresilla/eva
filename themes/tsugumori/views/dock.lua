-- Tsugumori's dock: a square plate, square blocks rising out of it on a tight
-- seam, and the focused block marked at its corners as the theme marks a focus.
local ui = require("morf.ui")
local kit = require("kit")
local L = require("themes.layouts.parts")
local V = {}
function V.build(model)
  return require("themes.layouts.dock").build(model, { bubble = "box", bubble_radius = 2, radius = 2, seam = 6,
    profile = "circular",
    mark = function(_, state)
      return ui.Item { anchors = { fill = true }, z = 2, visible = function() return state.active end,
        L.decor_box("corners", { length = 6, weight = 2, inset = -2, color = kit.stroke("hot") }) }
    end })
end
return V
