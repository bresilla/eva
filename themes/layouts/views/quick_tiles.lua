-- The quick settings' tiles: each tile's face, on the board shared with the bar
-- (themes/layouts/board.lua), which places, moves and arranges them.
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local rows = require("themes.layouts.rows")
local shared = require("themes.layouts.board")
local C = theme.color
local S = theme.space

local V = {}
local TILE_H = 60
V.badge = shared.badge

--- The card of tiles, `w` wide. `ctx.viewport` is the scroll its titles read
--- in against. Returns `{ node, height }`.
function V.build(model, w, ctx)
  local board = model.tiles
  local TRAVEL = theme.spring.spatial

  -- A tile's page opens in its panel, growing out of the tile while it is on
  -- show: each tile with a page says where it stands.
  local function grow(key) return model.reach(key) end

  local function face(t, tile)
    local id, name = t.id, t.name or t.id
    local box, small, armed, editing = tile.box, tile.small, tile.armed, tile.editing
    local function on() return t.on() == true end
    local fg = rows.ink(on, true, C.onSurface)
    local function sub() return on() and fg():alpha(0.8) or C.onSurfaceVariant end
    local more
    if t.detail and ctx.place then ctx.place(t.detail, box, tile.shown, TILE_H) end
    -- Title and status both reach the chevron's glyph, or stop short of its square.
    local MORE_W = theme.icon_box and 36 or S.TARGET
    local TEXT_W = tile.slot - S.xxl - S.l
      - (t.detail and (theme.icon_box and 8 + MORE_W + S.s or S.xxl + S.xs) or S.l + S.xs)
    local STATUS_W = t.detail and TEXT_W - S.xs or TEXT_W

    local area = kit.action {
      id = "utilities-toggle-" .. id, accessible_name = name, anchors = { fill = true }, cursor = "pointer",
      enabled = function() return not armed() end,
      on_clicked = function()
        if editing() then board.add(id) else t.set(not on()) end
      end,
      -- A small tile has no chevron: a long press opens what it would. Any
      -- other long press starts arranging the board.
      on_long_pressed = function()
        if editing() then return end
        if t.detail and small() then grow(t.detail) else tile.hold() end
      end,
      kit.icon(t.icon, 22, fg, { anchors = { vertical_center = true }, fill = t.fill or on,
        visible = not t.glyph or function() return not t.glyph().present end,
        x = function() return small() and (tile.half - 22) / 2 or S.l end,
        behavior = { x = TRAVEL } }),
      t.glyph and ui.Item { anchors = { vertical_center = true }, width = 28, height = 14,
        visible = function() return t.glyph().present end,
        x = function() return small() and (tile.half - 28) / 2 or S.m end,
        behavior = { x = TRAVEL },
        kit.battery { id = "utilities-glyph-" .. id, size = 14, status = t.glyph, color = fg, plain = on } } or ui.Item {},
      ui.Column {
        x = S.xxl + S.l, anchors = { vertical_center = true }, gap = 0,
        opacity = function() return small() and 0 or 1 end, behavior = { opacity = theme.spring.effects },
        kit.heading { id = "settings-tile-title-" .. id, scope = "settings.overview", level = "caption",
          viewport = ctx.viewport, width = TEXT_W, elide = "right", text = name,
          font_size = theme.size.normal, font_weight = 500, color = fg, ink = fg },
        kit.subtitle { width = STATUS_W, elide = "right", font_size = theme.size.small, color = sub,
          text = function()
            local s = t.status and t.status()
            if s and s ~= "" then return s end
            return on() and "On" or "Off"
          end },
      },
    }
    -- The theme's ground: its hover, its press (the chevron's too) and the
    -- shape it takes while on.
    ui.reparent(kit.tile_surface { id = "utilities-toggle-" .. id .. "-shape", area = area, on = on,
      height = TILE_H, tone = "primary", z = -1, width = function() return box().width end,
      pressed = function() return more ~= nil and more.pressed end }, area)
    if t.detail then
      more = kit.action {
        id = "utilities-more-" .. id, accessible_name = "Open " .. name, width = MORE_W, cursor = "pointer",
        anchors = { right = true, top = true, bottom = true, top_margin = 8, bottom_margin = 8, right_margin = 8 },
        visible = function() return not small() and not editing() end,
        on_clicked = function() grow(t.detail) end,
        kit.icon("chevron_right", 22, fg, { anchors = { center_in = true } }),
      }
      kit.hover(more, function(hovered) return hovered and fg():alpha(0.12) or fg():alpha(0) end, 10)
      ui.reparent(more, area)
    end
    return area
  end

  return shared.build { board = board, items = model.TOGGLES, width = w, height = TILE_H, face = face,
    prefix = "utilities", card_id = "utilities-toggles", key = "quick",
    note = function(has_spare) return has_spare and "Tap to add" or "Every tile is shown" end }
end

return V
