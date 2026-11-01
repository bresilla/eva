-- The Bar page's board: the bar's modules by zone, on the board the quick
-- settings' tiles use (themes/layouts/board.lua). Arranging a tile here moves its
-- module on the bar behind the page.
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local shared = require("themes.layouts.board")
local C = theme.color
local S = theme.space

local V = {}
local TILE_H = 52
local TITLES = { start = "Start", centre = "Centre", ["end"] = "End" }

--- The card of modules, `w` wide. Returns `{ node, height }`.
function V.build(model, w)
  local board = model.board

  local function face(m, tile)
    local id, name = m.id, m.name or m.id
    local area = kit.action {
      id = "bar-board-toggle-" .. id, accessible_name = name, anchors = { fill = true }, cursor = "pointer",
      enabled = function() return not tile.armed() end,
      on_clicked = function() if tile.editing() then board.add(id) end end,
      on_long_pressed = tile.hold,
      kit.icon(m.icon, 20, function() return C.onSurface end, { anchors = { vertical_center = true },
        x = function() return tile.small() and (tile.half - 20) / 2 or S.m end,
        behavior = { x = theme.spring.spatial } }),
      kit.subtitle { x = S.xl + S.m, anchors = { vertical_center = true }, width = tile.slot - S.xxl - S.xl - S.m,
        wrap = true, max_lines = 2, font_size = theme.size.small, color = function() return C.onSurface end,
        opacity = function() return tile.small() and 0 or 1 end, behavior = { opacity = theme.spring.effects },
        text = name },
    }
    ui.reparent(kit.tile_surface { id = "bar-board-toggle-" .. id .. "-shape", area = area, on = function() return false end,
      height = TILE_H, tone = "primary", z = -1, width = function() return tile.box().width end,
      pressed = function() return false end }, area)
    return area
  end

  return shared.build { board = board, items = model.items, width = w, height = TILE_H, face = face,
    prefix = "bar-board", card_id = "bar-board", key = "bar.board", titles = TITLES, lift = true,
    note = function(has_spare) return has_spare and "Tap to add, then drag along the bar" or "Every module is on the bar" end }
end

return V
