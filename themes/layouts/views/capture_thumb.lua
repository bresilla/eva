-- The floating thumbnail after a shot: its picture, a press to edit, and the pin
-- in its corner. The theme gives its card, ink and motion.
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local C, S = theme.color, theme.space
local V = {}

function V.build(M, width, height)
  local press
  local pin_side = S.TARGET - S.s
  press = ui.MouseArea { id = "capture-thumb-press", anchors = { fill = true }, cursor = "pointer",
    on_clicked = function() M.edit() end,
    on_entered = M.linger,
  }
  local pin = kit.action { id = "capture-thumb-pin", width = pin_side, height = pin_side, cursor = "pointer",
    anchors = { top = true, right = true, top_margin = S.xs, right_margin = S.xs },
    on_clicked = function() M.pin() end,
    kit.surface { anchors = { fill = true }, radius = kit.round(S.m), color = function() return C.surfaceContainerHigh:alpha(.86) end },
    kit.icon("keep", 18, function() return C.onSurface end, { anchors = { center_in = true } }),
  }
  return ui.Item { id = "capture-thumb", width = width, height = height,
    opacity = function() return M.leaving:get() and 0 or 1 end,
    translate_y = function() return M.leaving:get() and S.m or 0 end,
    behavior = { opacity = theme.spring.drawer, translate_y = theme.spring.drawer },
    kit.card { anchors = { fill = true }, radius = kit.round(S.l), color = function() return C.surfaceContainerHigh end },
    ui.Rect { anchors = { fill = true, margins = S.xs }, radius = kit.round(S.m), clip = true, color = "transparent",
      ui.Image { id = "capture-thumb-image", anchors = { fill = true }, fill_mode = "preserve_aspect_crop",
        source = function() return M.source:get() end },
    },
    press, pin,
  }
end

return V
