-- A pinned shot: the picture on its card, a press to close it and a drag to move
-- it, with the mouse or a finger.
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local C, S = theme.color, theme.space
local V = {}

function V.build(M, one)
  local start, moved, last
  local index = one.index
  -- The surface moves under the pointer, so each report is already the distance
  -- from where the press took hold. A mouse and a finger report by different
  -- handlers, and a mouse by both, so a report is taken once.
  local function report(sx, sy)
    if not start or (last and last.x == sx and last.y == sy) then return end
    last = { x = sx, y = sy }
    local dx, dy = sx - start.x, sy - start.y
    if not moved and dx * dx + dy * dy < M.SLOP * M.SLOP then return end
    moved = true
    M.nudge(one, dx, dy)
  end
  return ui.Item { id = "capture-pin-" .. index, width = one.width, height = one.height,
    kit.card { anchors = { fill = true }, radius = kit.round(S.m), color = function() return C.surfaceContainerHigh end },
    ui.Rect { anchors = { fill = true, margins = S.xxs }, radius = kit.round(S.s), clip = true, color = "transparent",
      ui.Image { id = "capture-pin-image-" .. index, anchors = { fill = true }, fill_mode = "preserve_aspect_fit",
        source = function() return one.source:get() end },
    },
    ui.MouseArea { id = "capture-pin-press-" .. index, anchors = { fill = true }, cursor = "move",
      on_pressed = function(sx, sy) start, moved, last = { x = sx, y = sy }, false, nil end,
      on_position_changed = report,
      on_dragged = report,
      on_released = function()
        local stayed = start and not moved
        start = nil
        if stayed then M.close(one) end
      end,
    },
  }
end

return V
