-- The login screen's accessibility menu: a button, and the choices it opens.
local button = require("themes.layouts.auth.button")
local M = {}

--- `view`: `{ ui, s, C, icon, text }`. `spec`: `access` (the model), `options`,
--- `anchors`, `x`, `y`, `visible`.
function M.panel(view, spec)
  local ui, s, C = view.ui, view.s, view.C
  local access = spec.access
  local WIDTH = s(280)
  local rows = { x = s(12), y = s(12), width = WIDTH - 2 * s(12), gap = s(4) }
  for _, option in ipairs(spec.options) do
    local on = function() return access.on(option.key) end
    rows[#rows + 1] = ui.MouseArea {
      id = "greet-access-" .. option.key, width = WIDTH - 2 * s(12), height = s(44), cursor = "pointer",
      accessible_name = option.name, on_clicked = function() access.toggle(option.key) end,
      ui.Rect { id = "greet-access-" .. option.key .. "-surface", anchors = { fill = true }, radius = s(12),
        color = function() return on() and C.primary or C.surfaceContainerHigh end },
      ui.Row { x = s(12), anchors = { vertical_center = true }, gap = s(10), align = "center",
        view.icon(option.icon, s(20), function() return on() and C.onPrimary or C.onSurface end),
        view.text { text = option.name, font_size = s(15),
          color = function() return on() and C.onPrimary or C.onSurface end },
      },
    }
  end
  local content = ui.Column(rows)
  return ui.Rect {
    id = "greet-access-panel", width = WIDTH, radius = s(20), z = 40, x = spec.x, y = spec.y, anchors = spec.anchors,
    height = function() return (content.layout_height or 0) + 2 * s(12) end,
    visible = function() return access.open:get() and (not spec.visible or spec.visible()) end,
    color = function() return C.surfaceContainer end,
    ui.MouseArea { anchors = { fill = true } },
    content,
  }
end

function M.button(view, spec)
  return button.round(view, { id = "greet-access", name = "Accessibility", icon = "accessibility_new",
    on = function() return spec.access.open:get() end,
    on_clicked = function() spec.access.open:set(not spec.access.open:get()) end })
end

return M
