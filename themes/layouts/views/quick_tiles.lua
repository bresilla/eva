-- The quick settings' tiles. Every tile is built once, the first time it is
-- shown, and kept: the board (`model.tiles`) says where each one goes, and its
-- place, width and presence follow on springs, so rearranging moves the tiles
-- that are there instead of drawing new ones.
--
-- A tile hangs on a `sortable_grid` holder beside the drag control, which is
-- there only while editing.
--
-- While editing the hidden tiles wait in the same space below the shown ones:
-- a hidden tile flies down to the Available section and an added one back.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local rows = require("themes.layouts.rows")
local L = require("themes.layouts.parts")
local P = require("themes.layouts.page")
local widgets = require("themes.kit.widgets")
local grid = require("tile_grid")
local C = theme.color
local S = theme.space

local V = {}
local TILE_H, GAP = 60, S.s
local TWO_WIDE, THREE_WIDE = 176, 232
local SPARE_HEAD = S.l + L.CAPTION_H + S.s
local BADGE = S.xl - S.xxs
local BADGE_W, BADGE_H = S.TARGET, 30

--- How many slots fit across `inner`.
local function columns(inner)
  if inner >= 3 * THREE_WIDE + 2 * GAP then return 3 end
  if inner >= 2 * TWO_WIDE + GAP then return 2 end
  return 1
end

-- A round mark in a tile's corner while editing: `id`, `name`, `icon`, `edge`
-- ("top" or "bottom"), `tone` and `ink` (fns), `visible`, `on_clicked`.
local function badge(spec)
  local press = kit.action { id = spec.id, accessible_name = spec.name, width = BADGE_W, height = BADGE_H,
    cursor = "pointer", anchors = { right = true, [spec.edge] = true }, visible = spec.visible,
    on_clicked = spec.on_clicked,
    ui.Item { anchors = { right = true, right_margin = S.xs, vertical_center = true }, width = BADGE, height = BADGE,
      kit.shape { anchors = { fill = true }, shape = "circle", color = spec.tone },
      kit.icon(spec.icon, 16, spec.ink, { anchors = { center_in = true } }) } }
  return press
end

--- The card of tiles, `w` wide. `ctx.viewport` is the scroll its titles read
--- in against. Returns `{ node, height }`.
function V.build(model, w, ctx)
  local board = model.tiles
  local inner = w - 2 * P.PAD
  local COLUMNS = columns(inner)
  local SLOT = (inner - (COLUMNS - 1) * GAP) / COLUMNS
  local METRICS = { half = (SLOT - GAP) / 2, gap = GAP, height = TILE_H }
  local TRAVEL = theme.spring.spatial
  local stamp = tostring({})
  local cells = morf.signal("eva.quick.cells." .. stamp, { shown = {}, spare = {}, rows = 0, spare_rows = 0 })
  local carried = morf.signal("eva.quick.carried." .. stamp, "")
  local edited = morf.signal("eva.quick.edited." .. stamp, false)
  local function editing() return board.editing:get() end

  local function main_bottom() return P.PAD + grid.height(cells:get().rows, METRICS) end
  local function spare_top() return main_bottom() + SPARE_HEAD end
  local function height()
    if not editing() then return main_bottom() + P.PAD end
    local spare_rows = cells:get().spare_rows
    return spare_top() + grid.height(spare_rows, METRICS) + (spare_rows > 0 and S.l or 0) + P.BUTTON_H + P.PAD
  end

  -- The tile's box in the card, or nil while it has no place.
  local function place(id)
    local now = cells:get()
    local cell = now.shown[id]
    local top = P.PAD
    if not cell then cell, top = now.spare[id], spare_top() end
    if not cell then return nil end
    local x, y, width = grid.box(cell, METRICS)
    return P.PAD + x, top + y, width
  end

  local function tile(t)
    local id, name = t.id, t.name or t.id
    local at = { x = P.PAD, y = P.PAD, width = SLOT }
    local function box()
      local x, y, width = place(id)
      if x then at.x, at.y, at.width = x, y, width end
      return at
    end
    local function shown() return cells:get().shown[id] ~= nil end
    local function spare() return cells:get().spare[id] ~= nil end
    local function small()
      local now = cells:get()
      local cell = now.shown[id] or now.spare[id]
      return cell ~= nil and cell.span == 1
    end
    local function armed() return editing() and shown() end
    local function placed() return shown() or (editing() and spare()) end
    local function on() return t.on() == true end
    local fg = rows.ink(on, true, C.onSurface)
    local function sub() return on() and fg():alpha(0.8) or C.onSurfaceVariant end
    local more
    -- A title reaches the chevron's glyph, a status stops at its box.
    local TEXT_W = SLOT - S.xxl - S.l - (t.detail and S.xxl + S.xs or S.l + S.xs)
    local STATUS_W = t.detail and TEXT_W - S.m or TEXT_W

    local area = kit.action {
      id = "utilities-toggle-" .. id, accessible_name = name, anchors = { fill = true }, cursor = "pointer",
      enabled = function() return not armed() end,
      on_clicked = function()
        if editing() then board.add(id) else t.set(not on()) end
      end,
      -- A small tile has no chevron: a long press opens what it would.
      on_long_pressed = t.detail and function()
        if not editing() then model.detail:set(t.detail) end
      end or nil,
      kit.icon(t.icon, 22, fg, { anchors = { vertical_center = true }, fill = t.fill or on,
        x = function() return small() and (METRICS.half - 22) / 2 or S.l end,
        behavior = { x = TRAVEL } }),
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
        id = "utilities-more-" .. id, accessible_name = "Open " .. name, width = S.TARGET, cursor = "pointer",
        anchors = { right = true, top = true, bottom = true, top_margin = 8, bottom_margin = 8, right_margin = 8 },
        visible = function() return not small() and not editing() end,
        on_clicked = function() model.detail:set(t.detail) end,
        kit.icon("chevron_right", 22, fg, { anchors = { center_in = true } }),
      }
      kit.hover(more, function(hovered) return hovered and fg():alpha(0.12) or fg():alpha(0) end, 10)
      ui.reparent(more, area)
    end

    local marks = ui.Loader { anchors = { fill = true }, keep = true, active = function() return edited:get() end,
      source = function()
        return ui.Item { anchors = { fill = true },
          badge { id = "utilities-hide-" .. id, name = "Hide " .. name, icon = "remove", edge = "top", visible = armed,
            tone = function() return C.errorContainer end, ink = function() return C.onErrorContainer end,
            on_clicked = function() board.hide(id) end },
          badge { id = "utilities-size-" .. id, name = "Change the size of " .. name, edge = "bottom", visible = armed,
            icon = function() return small() and "open_in_full" or "close_fullscreen" end,
            tone = function() return C.secondaryContainer end, ink = function() return C.onSecondaryContainer end,
            on_clicked = function() board.toggle_size(id) end },
          badge { id = "utilities-add-" .. id, name = "Add " .. name, icon = "add", edge = "top",
            visible = function() return editing() and spare() end,
            tone = function() return C.primary end, ink = function() return C.onPrimary end,
            on_clicked = function() board.add(id) end },
        }
      end }

    local body = ui.Item { anchors = { fill = true },
      scale = function()
        if carried:get() == id then return 1.04 end
        return placed() and 1 or 0.9
      end,
      behavior = { scale = theme.spring.fast },
      area, marks }
    local presence = ui.claims(body, {
      here = { when = placed, motion = theme.spring.effects, set = { opacity = 1 } },
      gone = { set = { opacity = 0 } },
    })

    local origin
    local holder, drag = widgets.sortable_grid {
      id = "utilities-tile-" .. id, carrier = true, accessible_name = "Move " .. name,
      -- A reorder of no step on the pointer: the grid places a carried tile,
      -- and Alt with the arrows walks it.
      mode = "reorder", extent = 1e6,
      x = function() return box().x end, y = function() return box().y end,
      width = function() return box().width end, height = TILE_H,
      behavior = { x = TRAVEL, y = TRAVEL, width = TRAVEL },
      visible = function() return placed() or presence.here.presence:get() > 0.01 end,
      armed = armed, enabled = armed,
      focus_policy = function() return armed() and "tab" or "none" end,
      on_drag_started = function()
        local b = box()
        origin = { x = b.x - P.PAD + b.width / 2, y = b.y - P.PAD + TILE_H / 2 }
        carried:set(id)
      end,
      on_dropped = function() carried:set("") end,
      on_reorder = function(step)
        for index, item in ipairs(board.shown()) do
          if item.id == id then board.move(id, index + step) return end
        end
      end,
    }
    ui.reparent(body, holder)
    morf.effect("eva.quick.carry." .. id .. stamp, function()
      if not drag.active or not origin then return end
      local items = board.shown()
      local index = grid.nearest(items, id, origin.x + drag.delta_x, origin.y + drag.delta_y, COLUMNS, METRICS)
      if index and (items[index] or {}).id ~= id then board.move(id, index) end
    end, { owner = holder })
    return holder
  end

  local wanted, layer = {}, { anchors = { fill = true } }
  for _, t in ipairs(model.TOGGLES) do
    wanted[t.id] = morf.signal("eva.quick.wanted." .. t.id .. stamp, false)
    layer[#layer + 1] = ui.Loader { anchors = { fill = true }, keep = true,
      z = function() return carried:get() == t.id and 10 or 0 end,
      active = function() return wanted[t.id]:get() end,
      source = function() return tile(t) end }
  end

  local available = ui.Item { x = P.PAD, y = function() return main_bottom() + S.l end, width = inner,
    height = L.CAPTION_H, visible = editing,
    L.caption { id = "utilities-available", width = inner, text = "Available",
      note = function() return cells:get().spare_rows > 0 and "Tap to add" or "Every tile is shown" end } }
  local reset = ui.Item { x = P.PAD, width = inner, height = P.BUTTON_H, visible = editing,
    y = function()
      local spare_rows = cells:get().spare_rows
      return spare_top() + grid.height(spare_rows, METRICS) + (spare_rows > 0 and S.l or 0)
    end,
    P.button { id = "utilities-edit-reset", label = "Reset", icon = "restart_alt", on_clicked = board.reset } }

  local card = kit.card { id = "utilities-toggles", width = w, height = height, radius = kit.round(P.RADIUS),
    behavior = { height = TRAVEL }, ui.Item(layer), available, reset }

  morf.effect("eva.quick.layout." .. stamp, function()
    local shown, spare = board.shown(), board.spare()
    local a, a_rows = grid.flow(shown, COLUMNS)
    local b, b_rows = grid.flow(spare, COLUMNS)
    cells:set { shown = a, spare = b, rows = a_rows, spare_rows = b_rows }
  end, { owner = card })
  morf.effect("eva.quick.wanted." .. stamp, function()
    local now, edit = cells:get(), editing()
    for id, signal in pairs(wanted) do
      if (now.shown[id] or (edit and now.spare[id])) and not signal:get() then signal:set(true) end
    end
    if edit and not edited:get() then edited:set(true) end
  end, { owner = card })

  return { node = card, height = height }
end

return V
