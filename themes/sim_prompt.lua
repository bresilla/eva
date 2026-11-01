-- The SIM's PIN or PUK, for the shell and the lock. `look` as
-- themes/call_screen.lua takes; `sim` is models/phone_sim.lua's.
local ui = require("morf.ui")
local S = require("themes.spacing")

local M = {}

local DOT = S.m

--- `spec`: `sim`, `look`, `width`, `height` (fns).
function M.build(spec)
  local sim, look, width, height = spec.sim, spec.look, spec.width, spec.height
  local C = look.C
  local pad = require("themes.phone_pad").build { look = look, prefix = "sim-key", digits = true,
    on_key = function(key) sim.digit(key) end }
  local dots = {}
  for index = 1, 8 do
    dots[index] = ui.Rect { width = DOT, height = DOT, radius = look.round(DOT / 2),
      visible = function() return sim.count:get() >= index end,
      color = function() return C.primary end }
  end
  local function round(id, name, icon, on_clicked, enabled, tone)
    return look.action {
      id = id, accessible_name = name, width = S.TOUCH + S.m, height = S.TOUCH + S.m, cursor = "pointer",
      enabled = enabled, on_clicked = on_clicked,
      ui.Rect { anchors = { fill = true }, radius = look.round(S.xl + S.xs + S.xxs),
        color = function()
          if tone == "go" and sim.ready() then return C.primary end
          return C.surfaceContainerHigh
        end },
      look.icon(icon, S.xl, function()
        return tone == "go" and sim.ready() and C.onPrimary or C.onSurface
      end, { anchors = { center_in = true } }),
    }
  end
  return ui.Rect {
    id = "sim-prompt", width = width, height = height, color = function() return C.surface end,
    ui.Column {
      id = "sim-body", gap = S.l, align = "center", anchors = { horizontal_center = true },
      y = function() return math.floor(height() * 0.18) end,
      look.icon("sim_card", S.xxl + S.l, function() return C.primary end),
      look.text { id = "sim-title", text = sim.title, font_size = S.xl },
      ui.Item { width = 8 * DOT + 7 * S.s, height = DOT + S.s,
        ui.Row { anchors = { center_in = true }, gap = S.s, table.unpack(dots) } },
      look.text { id = "sim-tries", font_size = S.m + S.xxs, color = function() return C.onSurfaceVariant end,
        text = function()
          local message = sim.message:get()
          if message ~= "" then return message end
          return sim.tries()
        end },
      ui.Item { width = pad.width, height = pad.height, pad.node },
      ui.Row { gap = S.xxl, align = "center",
        round("sim-back", "Delete", "backspace", sim.back),
        round("sim-go", "Unlock", "check", sim.submit, sim.ready, "go"),
      },
      look.action { id = "sim-later", accessible_name = "Later", width = S.TARGET * 3, height = S.TOUCH,
        cursor = "pointer", on_clicked = sim.later,
        look.text { anchors = { center_in = true }, text = "Later", font_size = S.l,
          color = function() return C.primary end } },
    },
  }
end

return M
