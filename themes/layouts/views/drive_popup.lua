-- A drive that was just plugged in: a small card in the screen's corner with
-- what can be done to it. On a surface of its own, over everything.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local S = theme.space

local M = {}

M.SHOWN = 12000
local WIDTH, HEIGHT = 360, 148

local layer, timer

function M.close()
  if timer then timer:cancel() timer = nil end
  if layer then layer:destroy() layer = nil end
end

--- Shows `row` (a udisks volume). `actions`: `open`, `eject`, `settings`, each
--- taking the row; `human` writes a size.
function M.show(row, actions)
  M.close()
  local inner = WIDTH - 2 * P.PAD
  local function act(fn) return function() M.close() fn(row) end end
  local card = kit.card { id = "drive-popup", width = WIDTH, height = HEIGHT, radius = kit.round(P.RADIUS),
    ui.Column { x = P.PAD, y = P.PAD, gap = S.s, width = inner,
      P.row { id = "drive-popup-row", width = inner, height = 56, icon = row.encrypted and "lock" or "usb", title = row.name,
        subtitle = actions.human(row.size) .. (row.encrypted and " · Encrypted" or "") },
      P.buttons { width = inner,
        { id = "drive-popup-open", label = row.encrypted and "Unlock" or "Open", tone = "primary",
          on_clicked = act(row.encrypted and actions.settings or actions.open) },
        { id = "drive-popup-eject", label = "Eject", on_clicked = act(actions.eject) },
        { id = "drive-popup-close", label = "Close", on_clicked = M.close } },
    } }
  layer = morf.window.layer { blend = "srgb", namespace = "eva-drive", layer = "overlay",
    anchors = { top = true, right = true }, margin_top = S.xl + S.xl, margin_right = S.xl,
    width = WIDTH, height = HEIGHT, exclusive_zone = -1, keyboard_focus = "none", visible = true,
    root = ui.Item { width = WIDTH, height = HEIGHT, card } }
  timer = morf.time.timer(M.SHOWN, M.close, false)
  return card
end

return M
