-- The twelve keys of a phone, for whatever is asking: tones in a call, a SIM
-- PIN, an emergency number, the dialler, a PIN whose digits change places.
-- `look` as themes/call_screen.lua takes.
--
--   local pad = require("themes.phone_pad").build { look = look, prefix = "call-key",
--     on_key = function(key) end }
--   pad.width, pad.height
local morf = require("morf")
local ui = require("morf.ui")
local S = require("themes.spacing")

local M = {}

M.CELL = S.TOUCH + S.xl
M.KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#" }
local LETTERS = { ["2"] = "ABC", ["3"] = "DEF", ["4"] = "GHI", ["5"] = "JKL", ["6"] = "MNO",
  ["7"] = "PQRS", ["8"] = "TUV", ["9"] = "WXYZ", ["0"] = "+" }
-- What stands for a key that is no digit, and what it is called.
local GLYPHS, NAMES = { backspace = "backspace", enter = "arrow_forward" }, { backspace = "Delete", enter = "Unlock" }

local function get(value) if type(value) == "function" then return value() end return value end

--- `spec`: `look`, `prefix` (each key is `<prefix>-<key>`), `on_key(key)`,
--- `on_long(key)`, `digits` (true leaves out * and #, as a PIN wants). `order`
--- (fn, the twelve keys in their places) lets keys move: each is then
--- `<prefix>-<place>`, and "backspace" and "enter" stand among the digits. `cell_w`
--- and `cell_h`, numbers or fns, size a key; `enabled` (fn) says when they take a press.
function M.build(spec)
  local look, C = spec.look, spec.look.C
  local cell_w, cell_h = spec.cell_w or M.CELL, spec.cell_h or M.CELL
  local function press(place)
    local function key() return spec.order and spec.order()[place] or M.KEYS[place] end
    local face
    if spec.order then
      face = ui.Item { anchors = { center_in = true }, width = S.xl + S.xs, height = S.xl + S.xs,
        look.text { id = spec.prefix .. "-" .. place .. "-label", anchors = { center_in = true }, font_size = S.xl + S.xs,
          text = function() return GLYPHS[key()] and "" or key() end },
        look.icon(function() return GLYPHS[key()] or "dialpad" end, S.xl + S.xs, function() return C.onSurface end,
          { anchors = { center_in = true }, visible = function() return GLYPHS[key()] ~= nil end }) }
    else
      face = ui.Column { anchors = { center_in = true }, gap = 0, align = "center",
        look.text { text = key(), font_size = S.xl + S.xs },
        look.text { text = LETTERS[key()] or " ", font_size = S.m - S.xxs,
          color = function() return C.onSurfaceVariant end },
      }
    end
    return look.action {
      id = spec.prefix .. "-" .. (spec.order and place or key()), width = cell_w, height = cell_h, cursor = "pointer",
      accessible_role = "button", accessible_name = function() return NAMES[key()] or key() end, enabled = spec.enabled,
      on_clicked = function() spec.on_key(key()) end,
      on_long_pressed = spec.on_long and function() spec.on_long(key()) end or nil,
      ui.Rect { anchors = { fill = true }, radius = function() return look.round(math.min(get(cell_w), get(cell_h)) / 2) end,
        color = function() return C.surfaceContainerHigh end },
      face,
    }
  end
  local grid = { columns = 3, column_gap = S.l, row_gap = S.m }
  if spec.order then grid.column_gap, grid.row_gap = S.s, S.s end
  for place, key in ipairs(M.KEYS) do
    if spec.digits and (key == "*" or key == "#") then grid[#grid + 1] = ui.Item { width = M.CELL, height = M.CELL }
    else grid[#grid + 1] = press(place) end
  end
  local node = ui.Grid(grid)
  return { node = node, width = 3 * M.CELL + 2 * S.l, height = 4 * M.CELL + 3 * S.m }
end

--- The keys of a PIN pad in a random order: nine digits, then delete, the tenth and
--- enter. `pick(n)` is a number from 1 to `n`, every one as likely.
function M.shuffled(pick)
  local digits = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }
  for i = #digits, 2, -1 do
    local j = pick(i)
    digits[i], digits[j] = digits[j], digits[i]
  end
  table.insert(digits, 10, "backspace")
  digits[#digits + 1] = "enter"
  return digits
end

--- A PIN pad over a panel, its digits in a new order each time it comes up.
--- `spec`: `look`, `prefix`, `shown` (fn, a new order at each rise), `enabled` (fn),
--- `width` and `height` (the panel's, fns), `panel` (its colour) and `send(event)`,
--- which hears `{ text }` or `{ key = "backspace" | "enter" }`.
function M.scrambled(spec)
  local pick = require("lib.shell.launcher.password").pick
  local order = morf.signal(spec.prefix .. ".order", M.shuffled(pick))
  local PAD = S.s
  local pad = M.build { look = spec.look, prefix = spec.prefix, enabled = spec.enabled,
    order = function() return order:get() end,
    cell_w = function() return (spec.width() - 2 * PAD - 2 * S.s) / 3 end,
    cell_h = function() return (spec.height() - 2 * PAD - 3 * S.s) / 4 end,
    on_key = function(key)
      if GLYPHS[key] then spec.send { key = key } else spec.send { text = key } end
    end }
  pad.node.x, pad.node.y = PAD, PAD
  local node = ui.Rect { id = spec.prefix, anchors = { fill = true }, z = 5, color = spec.panel,
    ui.MouseArea { anchors = { fill = true } }, pad.node }
  local was = false
  morf.effect(spec.prefix .. ".shuffle", function()
    local up = spec.shown()
    if up and not was then order:set(M.shuffled(pick)) end
    was = up
  end, { owner = node })
  return node
end

return M
