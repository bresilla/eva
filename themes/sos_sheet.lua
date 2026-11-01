-- The countdown to an emergency call, whole screen, with a way out. `look` as
-- themes/call_screen.lua takes.
local ui = require("morf.ui")
local S = require("themes.spacing")

local M = {}

--- `spec`: `left` (a signal, seconds), `cancel`, `look`, `width`, `height` (fns).
function M.build(spec)
  local look, width, height = spec.look, spec.width, spec.height
  local C = look.C
  return ui.Rect {
    id = "sos-sheet", width = width, height = height, color = function() return C.errorContainer end,
    ui.Column { gap = S.l, align = "center", anchors = { horizontal_center = true },
      y = function() return math.floor(height() * 0.22) end,
      look.icon("emergency", S.xxl + S.xl, function() return C.onErrorContainer end),
      look.text { font_size = S.xl, text = "Calling emergency services",
        color = function() return C.onErrorContainer end },
      look.text { id = "sos-left", font_size = S.xxl * 3,
        color = function() return C.onErrorContainer end,
        text = function() return tostring(spec.left:get()) end },
    },
    look.action {
      id = "sos-cancel", accessible_name = "Cancel", width = function() return width() - 2 * S.xl end,
      height = S.TOUCH + S.xl, cursor = "pointer", x = S.xl,
      y = function() return height() - S.TOUCH - S.xl - S.xxl - S.l end, on_clicked = spec.cancel,
      ui.Rect { anchors = { fill = true }, radius = look.round(S.xl), color = function() return C.error end },
      look.text { anchors = { center_in = true }, text = "Cancel", font_size = S.xl,
        color = function() return C.onError end },
    },
  }
end

return M
