-- A public warning, whole screen, for the shell. `look` as themes/call_screen.lua
-- takes; `alerts` is models/phone_alerts.lua's.
local ui = require("morf.ui")
local S = require("themes.spacing")

local M = {}

--- `spec`: `alerts`, `look`, `width`, `height` (fns).
function M.build(spec)
  local alerts, look, width, height = spec.alerts, spec.look, spec.width, spec.height
  local C = look.C
  local function text_width() return math.max(1, width() - 2 * S.xl) end
  local function high() return alerts.showing:get().level ~= "info" end
  return ui.Rect {
    id = "alert-sheet", width = width, height = height,
    color = function() return high() and C.errorContainer or C.surfaceContainerHigh end,
    ui.Column {
      gap = S.l, x = S.xl, y = function() return math.floor(height() * 0.14) end, width = text_width,
      look.icon("warning", S.xxl + S.xl, function() return high() and C.onErrorContainer or C.onSurface end),
      look.text { id = "alert-title", font_size = S.xl + S.xs, width = text_width, wrap = true,
        color = function() return high() and C.onErrorContainer or C.onSurface end,
        text = function() return alerts.showing:get().title or "" end },
      look.text { id = "alert-text", font_size = S.l + S.xxs, width = text_width, wrap = true,
        color = function() return high() and C.onErrorContainer or C.onSurface end,
        text = function() return alerts.showing:get().text or "" end },
    },
    look.action {
      id = "alert-ok", accessible_name = "OK", width = text_width, height = S.TOUCH + S.m, cursor = "pointer",
      x = S.xl, y = function() return height() - S.TOUCH - S.m - S.xxl - S.l end,
      on_clicked = alerts.dismiss,
      ui.Rect { anchors = { fill = true }, radius = look.round(S.xl),
        color = function() return high() and C.error or C.primary end },
      look.text { anchors = { center_in = true }, text = "OK", font_size = S.l + S.xxs,
        color = function() return high() and C.onError or C.onPrimary end },
    },
  }
end

return M
