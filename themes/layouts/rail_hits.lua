-- The workspace rail's press targets, shared by the themes' rails: one on
-- each workspace's slot, reaching a little way out of the edge, for a press
-- and the wheel. They stand over the panels, so the rail still answers on the
-- strip the left panel carries it out to.
local ui = require("morf.ui")
local theme = require("theme")
local M = {}

-- How far past the frame a target reaches, a side's or the bottom edge's.
local NEAR = 8
-- A touchpad turns no notches, only pixels: this many are one.
local NOTCH_PX = 15

--- `model`: the rail's (`count`, `base`, `active`, `enabled`, `bottom`,
--- `edge`, `go`, `turn`); `geometry()`: the theme's, for `top`, `item`, `gap`.
--- Returns the node to place over the desk, and the targets by workspace slot.
function M.build(model, geometry)
  local root = ui.Item { id = "rail-hits", anchors = { fill = true }, visible = model.enabled }
  local targets = {}
  local function wheel(_, _, _, pixels, _, steps)
    model.turn((steps and steps ~= 0) and steps or (pixels or 0) / NOTCH_PX)
  end
  for i = 1, model.count do
    local function id() return model.base(model.active()) + i - 1 end
    local function start() local g = geometry() return g.top + (i - 1) * (g.item + g.gap) - g.gap / 2 end
    local function length() local g = geometry() return g.item + g.gap end
    local target = ui.MouseArea { id = "rail-hit-" .. i, cursor = "pointer", accessible_role = "button",
      accessible_name = function() return "Workspace " .. id() end,
      on_clicked = function() model.go(id()) end, on_wheel = wheel }
    local reach = theme.LEFT + NEAR
    if model.bottom then
      target.x, target.width, target.height = start, length, reach
      target.y = function() return model.edge() - reach end
    else
      target.x, target.width, target.y, target.height = 0, reach, start, length
    end
    targets[i] = target
    ui.reparent(target, root)
  end
  return root, targets
end

return M
