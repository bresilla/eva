-- The status row of the login screens: what the machine is doing, as icons.
-- The lock adds its quiet modes; neither says the name of anything.
local M = {}

local MODE = {
  { key = "airplane", icon = "flight", on = function(mode) return mode.airplane == true end },
  { key = "dnd", icon = "do_not_disturb_on", on = function(mode) return mode.dnd == true end },
  { key = "vibrate", icon = "vibration", on = function(mode) return mode.ringer == "vibrate" end },
  { key = "silent", icon = "notifications_off", on = function(mode) return mode.ringer == "silent" end },
}

--- `view`: `{ ui, s, C, icon, text }`. `spec`: `prefix`, `status` (the model),
--- `mode` (fn giving the shell's modes, or nil), `visible`, `anchors`, `x`, `y`.
function M.row(view, spec)
  local ui, s, C = view.ui, view.s, view.C
  local status = spec.status
  local SIZE = s(20)
  local function ink() return C.onSurfaceVariant end
  local function glyph(id, name)
    return view.icon(name, SIZE, ink, { id = spec.prefix .. "-status-" .. id,
      visible = function() return name() ~= "" end })
  end
  local nodes = { id = spec.prefix .. "-status", gap = s(10), align = "center",
    visible = spec.visible, anchors = spec.anchors, x = spec.x, y = spec.y, opacity = spec.opacity,
    behavior = spec.opacity and { opacity = { duration = 320 } } or nil }
  if spec.mode then
    for _, mode in ipairs(MODE) do
      nodes[#nodes + 1] = view.icon(mode.icon, SIZE, ink, { id = spec.prefix .. "-status-" .. mode.key,
        visible = function() return mode.on(spec.mode()) end })
    end
  end
  nodes[#nodes + 1] = glyph("bluetooth", status.bluetooth_icon)
  nodes[#nodes + 1] = glyph("network", status.network_icon)
  nodes[#nodes + 1] = ui.Row { gap = s(4), align = "center",
    visible = function() return status.battery().present == true end,
    view.icon(status.battery_icon, SIZE, ink, { id = spec.prefix .. "-status-battery" }),
    view.text { id = spec.prefix .. "-status-charge", text = status.battery_words, font_size = s(14), color = ink },
  }
  return ui.Row(nodes)
end

return M
