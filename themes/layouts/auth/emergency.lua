-- The emergency card: what the person chose to show, over the lock, and the
-- listed numbers to call. A call must be held, and nothing here unlocks.
local button = require("themes.layouts.auth.button")
local M = {}

--- `view`: `{ ui, s, C, icon, text }`. `spec`: `model`, `open` (fn), `close` (fn),
--- `say` (fn), `width`, `y` (fn).
function M.card(view, spec)
  local ui, s, C = view.ui, view.s, view.C
  local model, W = spec.model, spec.width
  local rows = { x = s(20), y = s(20), width = W - 2 * s(20), gap = s(10) }
  rows[#rows + 1] = view.text { id = "lock-emergency-title", text = "Emergency", font_size = s(20), font_weight = 600,
    color = C.error }
  for index, row in ipairs(model.card()) do
    rows[#rows + 1] = ui.Column { gap = 0,
      view.text { text = row.label, font_size = s(13), color = C.onSurfaceVariant },
      view.text { id = "lock-emergency-value-" .. index, text = row.value, font_size = s(17), width = W - 2 * s(20),
        wrap = true },
    }
  end
  local calls = { gap = s(10) }
  for _, number in ipairs(model.numbers()) do
    calls[#calls + 1] = ui.Column { gap = s(2), align = "center",
      button.round(view, { id = "lock-emergency-call-" .. number, name = "Call " .. number, icon = "call", hold = 800,
        size = s(52), tone = function() return C.error end,
        on_clicked = function()
          local ok, why = model.dial(number)
          spec.say(ok and ("Calling " .. number) or why, not ok)
        end }),
      view.text { text = number, font_size = s(14), color = C.onSurfaceVariant },
    }
  end
  if #calls > 0 then rows[#rows + 1] = ui.Row(calls) end
  rows[#rows + 1] = view.text { id = "lock-emergency-said", width = W - 2 * s(20), font_size = s(14),
    color = C.onSurfaceVariant, text = spec.said }
  local content = ui.Column(rows)
  return ui.Rect {
    id = "lock-emergency-card", width = W, radius = s(24), z = 40,
    anchors = { horizontal_center = true }, y = spec.y,
    height = function() return (content.layout_height or 0) + 2 * s(20) end,
    visible = spec.open, color = function() return C.surfaceContainer end,
    ui.MouseArea { anchors = { fill = true } },
    content,
    ui.Item { anchors = { right = true, right_margin = s(10), top = true, top_margin = s(10) },
      width = s(40), height = s(40),
      button.round(view, { id = "lock-emergency-close", name = "Close", icon = "close", size = s(40),
        on_clicked = spec.close }) },
  }
end

return M
