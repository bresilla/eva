-- The twelve keys of a phone, for whatever is asking: tones in a call, a SIM
-- PIN, an emergency number, the dialler. `look` as themes/call_screen.lua takes.
--
--   local pad = require("themes.phone_pad").build { look = look, prefix = "call-key",
--     on_key = function(key) end }
--   pad.width, pad.height
local ui = require("morf.ui")
local S = require("themes.spacing")

local M = {}

M.CELL = S.TOUCH + S.xl
M.KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" }
local LETTERS = { ["2"] = "ABC", ["3"] = "DEF", ["4"] = "GHI", ["5"] = "JKL", ["6"] = "MNO",
  ["7"] = "PQRS", ["8"] = "TUV", ["9"] = "WXYZ", ["0"] = "+" }

--- `spec`: `look`, `prefix` (each key is `<prefix>-<key>`), `on_key(key)`,
--- `on_long(key)`, `digits` (true leaves out * and #, as a PIN wants).
function M.build(spec)
  local look, C = spec.look, spec.look.C
  local function press(key)
    return look.action {
      id = spec.prefix .. "-" .. key, accessible_name = key, width = M.CELL, height = M.CELL, cursor = "pointer",
      on_clicked = function() spec.on_key(key) end,
      on_long_pressed = spec.on_long and function() spec.on_long(key) end or nil,
      ui.Rect { anchors = { fill = true }, radius = look.round(M.CELL / 2),
        color = function() return C.surfaceContainerHigh end },
      ui.Column { anchors = { center_in = true }, gap = 0, align = "center",
        look.text { text = key, font_size = S.xl + S.xs },
        look.text { text = LETTERS[key] or " ", font_size = S.m - S.xxs,
          color = function() return C.onSurfaceVariant end },
      },
    }
  end
  local grid = { columns = 3, column_gap = S.l, row_gap = S.m }
  for _, key in ipairs(M.KEYS) do
    if spec.digits and (key == "*" or key == "#") then grid[#grid + 1] = ui.Item { width = M.CELL, height = M.CELL }
    else grid[#grid + 1] = press(key) end
  end
  local node = ui.Grid(grid)
  return { node = node, width = 3 * M.CELL + 2 * S.l, height = 4 * M.CELL + 3 * S.m }
end

return M
