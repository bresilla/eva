-- A short menu of actions on a thing: an overview card's right press. `spec`: `id`, `items()` (each `{ label, icon, run }`), `at()` (where
-- it stands: `x, y`, given the height it wants), `close()`, `opened()`.
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local S, C = theme.space, theme.color
local M = {}

M.WIDTH, M.ROW = 260, S.TARGET
local MAX = 12

function M.height(count) return count * M.ROW + 2 * S.s end

function M.build(spec)
  local rows = { x = S.s, y = S.s, gap = 0 }
  for i = 1, MAX do
    local function item() return spec.items()[i] end
    local area = kit.action { id = spec.id .. "-" .. i, width = M.WIDTH - 2 * S.s, height = M.ROW, cursor = "pointer",
      accessible_name = function() local it = item() return it and it.label or "" end,
      visible = function() return item() ~= nil end,
      on_clicked = function()
        local it = item()
        spec.close()
        if it then it.run() end
      end,
      kit.icon(function() local it = item() return it and it.icon or "" end, 18, kit.ink("lo"), { x = S.s, y = (M.ROW - 18) / 2 }),
      kit.text { x = S.xxl, y = 0, height = M.ROW, width = M.WIDTH - 2 * S.s - S.xxl - S.s, vertical_alignment = "center",
        elide = "right", font_size = L.SIZE.body, color = kit.ink("hi"),
        text = function() local it = item() return it and it.label or "" end } }
    kit.hover(area, function(hovered) return hovered and C.onSurface:alpha(.08) or C.onSurface:alpha(0) end, S.xs)
    rows[#rows + 1] = area
  end
  local function height() return M.height(#spec.items()) end
  local menu = kit.card { id = spec.id, width = M.WIDTH, z = 10,
    x = function() return (spec.at(height())) end,
    y = function() return select(2, spec.at(height())) end,
    height = height,
    accessible_role = "menu", accessible_name = spec.name or "Menu",
    visible = spec.opened,
    ui.MouseArea { anchors = { fill = true } },
    ui.Column(rows) }
  require("themes.kit.popup").track(menu, { open = spec.opened, close_policy = "escape+outside",
    on_close = spec.close })
  return menu
end

return M
