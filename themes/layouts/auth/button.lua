-- The buttons of the login screens: round icon buttons, and chips with a word.
-- A button given `hold` counts only once held that long, filling as it goes,
-- so a pocket or a sleeve cannot press it. Skins restyle `*-surface` nodes.
local morf = require("morf")
local M = {}

--- `view` is `{ ui, s, C, icon, text }`. `spec`: `id`, `name`, `icon`,
--- `on_clicked`, `size`, `hold` (ms), `on` (fn: lit), `tone` (fn: a colour).
function M.round(view, spec)
  local ui, s, C = view.ui, view.s, view.C
  local size = spec.size or s(44)
  local area
  local held = morf.signal((spec.id or "button") .. ".held", 0)
  local waiting
  local function let_go()
    if waiting then waiting:cancel() waiting = nil end
    held:set(0)
  end
  local hold = spec.hold or 0
  area = ui.MouseArea {
    id = spec.id, width = size, height = size, cursor = "pointer", accessible_name = spec.name,
    visible = spec.visible,
    on_clicked = hold == 0 and spec.on_clicked or nil,
    on_pressed = hold > 0 and function()
      held:set(1)
      waiting = morf.time.timer(hold, function()
        waiting = nil
        held:set(0)
        spec.on_clicked()
      end, false)
    end or nil,
    on_released = hold > 0 and let_go or nil,
    on_touch_canceled = hold > 0 and let_go or nil,
    scale = function() return (area and area.pressed) and .9 or 1 end,
    behavior = { scale = ui.spring { stiffness = 700, damping = 18 } },
    ui.Rect {
      id = spec.id .. "-surface", anchors = { fill = true }, radius = size / 2,
      color = function()
        if spec.on and spec.on() then return C.primary end
        return (area and area.hovered) and C.surfaceContainerHighest or C.surfaceContainerHigh
      end,
      behavior = { color = { duration = 160 } },
    },
    ui.Rect {
      anchors = { center_in = true }, radius = size / 2, color = C.primary,
      width = function() return held:get() * size end, height = function() return held:get() * size end,
      behavior = { width = { duration = hold }, height = { duration = hold } },
      visible = hold > 0,
    },
    view.icon(spec.icon, math.floor(size * .5), function()
      if (spec.on and spec.on()) or held:get() > 0 then return C.onPrimary end
      return spec.tone and spec.tone() or C.onSurface
    end, { anchors = { center_in = true } }),
  }
  return area
end

--- A chip: `id`, `icon`, `text` (fn or string), `width`, `on_clicked`, `visible`.
function M.chip(view, spec)
  local ui, s, C = view.ui, view.s, view.C
  local width, height = spec.width or s(92), s(40)
  return ui.MouseArea {
    id = spec.id, width = width, height = height, cursor = "pointer", visible = spec.visible,
    accessible_name = spec.name, on_clicked = spec.on_clicked,
    ui.Rect { id = spec.id .. "-chip-surface", anchors = { fill = true }, radius = height / 2,
      color = function() return C.secondaryContainer end },
    ui.Row { anchors = { center_in = true }, gap = s(6), align = "center",
      view.icon(spec.icon, s(18), C.onSecondaryContainer),
      spec.text and view.text { id = spec.id .. "-label", width = spec.label_width, elide = spec.label_width and "right" or nil,
        font_size = s(14), font_weight = 500, color = C.onSecondaryContainer, text = spec.text } or nil,
    },
  }
end

return M
