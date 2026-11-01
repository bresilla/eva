-- Dialling without unlocking, for the lock: only a number that reaches the
-- emergency services will go, and the person flagged in the address book can
-- be seen. `look` as themes/call_screen.lua takes.
local morf = require("morf")
local ui = require("morf.ui")
local S = require("themes.spacing")

local M = {}

--- `spec`: `phone`, `book`, `look`, `width`, `height` (fns), `open` (a signal).
function M.build(spec)
  local phone, look, width, height = spec.phone, spec.look, spec.width, spec.height
  local C = look.C
  local number = morf.signal("eva.emergency.number", "")
  local refused = morf.signal("eva.emergency.refused", false)
  local function close()
    number:set("")
    refused:set(false)
    spec.open:set(false)
  end
  local pad = require("themes.phone_pad").build { look = look, prefix = "emergency-key",
    on_key = function(key)
      refused:set(false)
      number:set(number:get() .. key)
    end }
  local function call()
    if phone.emergency(number:get()) then
      number:set("")
      spec.open:set(false)
    else
      refused:set(true)
    end
  end
  local person = spec.book and spec.book.emergency() or nil
  return ui.Rect {
    id = "emergency-pad", width = width, height = height, color = function() return C.surface end,
    ui.Column {
      gap = S.l, align = "center", anchors = { horizontal_center = true },
      y = function() return math.floor(height() * 0.12) end,
      look.text { text = "Emergency call", font_size = S.xl,
        color = function() return C.error end },
      look.text { id = "emergency-number", font_size = S.xxl,
        text = function() local n = number:get() return n ~= "" and n or " " end },
      look.text { id = "emergency-note", font_size = S.m + S.xxs,
        color = function() return refused:get() and C.error or C.onSurfaceVariant end,
        text = function()
          if refused:get() then return "Only emergency numbers can be called while locked" end
          return "Emergency numbers: " .. table.concat(phone.emergency_numbers(), ", ")
        end },
      person and look.text { id = "emergency-contact", font_size = S.m + S.xxs,
        text = "In an emergency: " .. person.name } or nil,
      ui.Item { width = pad.width, height = pad.height, pad.node },
      ui.Row { gap = S.xxl, align = "center",
        look.action { id = "emergency-close", accessible_name = "Close", width = S.TOUCH + S.m,
          height = S.TOUCH + S.m, cursor = "pointer", on_clicked = close,
          look.icon("close", S.xl, function() return C.onSurface end, { anchors = { center_in = true } }) },
        look.action { id = "emergency-call", accessible_name = "Call", width = S.TOUCH + S.xl,
          height = S.TOUCH + S.xl, cursor = "pointer", on_clicked = call,
          ui.Rect { anchors = { fill = true }, radius = look.round((S.TOUCH + S.xl) / 2),
            color = function() return C.error end },
          look.icon("call", S.xl + S.xs, function() return C.onError end, { anchors = { center_in = true } }) },
        look.action { id = "emergency-back", accessible_name = "Delete", width = S.TOUCH + S.m,
          height = S.TOUCH + S.m, cursor = "pointer",
          on_clicked = function() number:set(number:get():sub(1, -2)) end,
          look.icon("backspace", S.xl, function() return C.onSurface end, { anchors = { center_in = true } }) },
      },
    },
  }
end

return M
