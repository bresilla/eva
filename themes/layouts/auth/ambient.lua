-- The lock's ambient face on a phone with a panel that can stay lit: black, with
-- a dim clock, a mark for each app with something new, and what is playing. It
-- moves a little each minute so nothing stays lit in one place.
local morf = require("morf")
local M = {}

local DRIFT = { { 0, 0 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { -1, -1 }, { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }

--- `view`: `{ ui, s, C, icon, text }`. `spec`: `clock`, `day`, `notifications` (the
--- model, or nil), `title` (fn or nil), `shown` (fn), `width`, `height`.
function M.build(view, spec)
  local ui, s, C = view.ui, view.s, view.C
  local function step()
    return DRIFT[(tonumber(morf.time.minute_clock:get():sub(-2)) or 0) % #DRIFT + 1]
  end
  local dim = C.onSurfaceVariant:alpha(.75)
  local dots = { id = "lock-ambient-dots", gap = s(10), anchors = { horizontal_center = true } }
  for index = 1, 6 do
    dots[#dots + 1] = ui.Rect { width = s(10), height = s(10), radius = s(5), color = dim,
      visible = function()
        local model = spec.notifications
        return model ~= nil and model.items()[index] ~= nil
      end }
  end
  return ui.Rect {
    id = "lock-ambient", anchors = { fill = true }, color = "#000000", z = 9000, visible = spec.shown,
    ui.Column {
      anchors = { horizontal_center = true }, gap = s(6), align = "center",
      y = math.floor(spec.height * .22),
      translate_x = function() return step()[1] * s(14) end,
      translate_y = function() return step()[2] * s(14) end,
      view.text { id = "lock-ambient-clock", text = function() return spec.clock:get() end,
        font_size = s(96), font_weight = 300, color = dim },
      view.text { id = "lock-ambient-date", text = function() return spec.day:get() end,
        font_size = s(18), color = dim },
      ui.Item { width = 1, height = s(16) },
      ui.Row(dots),
      view.text { id = "lock-ambient-title", width = math.max(1, spec.width - s(96)), elide = "right",
        horizontal_alignment = "center", font_size = s(15), color = dim,
        visible = function() return spec.title ~= nil and spec.title() ~= "" end,
        text = function() return spec.title and spec.title() or "" end },
    },
  }
end

return M
