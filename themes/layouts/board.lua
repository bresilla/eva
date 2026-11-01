-- A board of tiles on a card, arranged by hand. Every tile is built once, the
-- first time it is shown, and kept: the board model (shell/tiles_model.lua)
-- says where each one goes, and its place, width and presence follow on
-- springs, so rearranging moves the tiles that are there instead of drawing
-- new ones.
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
local L = require("themes.layouts.parts")
local P = require("themes.layouts.page")
local widgets = require("themes.kit.widgets")
local grid = require("tile_grid")
local C = theme.color
local S = theme.space

local M = {}
local GAP = S.s
local TWO_WIDE, THREE_WIDE = 176, 232
local SPARE_HEAD = S.l + L.CAPTION_H + S.s
local ZONE_HEAD = L.CAPTION_H + S.s
local BADGE = S.xl - S.xxs
local BADGE_W, BADGE_H = S.TARGET, 30

--- How many slots fit across `inner`.
function M.columns(inner)
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
M.badge = badge

--- The card of tiles. `spec`: `board`, `items` (each with `id`, optional
--- `name`), `width`, `height` (a tile's), `prefix` (of the ids), `card_id`,
--- `key` (of the signals), `titles` (a zone's caption by its name, for a board
--- of zones), `columns` (how many slots across its inner width), `note`
--- (`has_spare`: what the Available section says), `lift` (a board always
--- arranged: under a finger a tile takes a long press to come loose, so a
--- drag over the rest scrolls), and `face(item, tile)`, the tile's own node.
--- `tile`: `box`, `shown`, `spare`, `small`, `armed`, `editing`, `hold` (a long
--- press's: the board to arranging), `slot`, `half`. Returns `{ node, height }`.
function M.build(spec)
  local board, w, TILE_H = spec.board, spec.width, spec.height
  local prefix = spec.prefix
  local inner = w - 2 * P.PAD
  local COLUMNS = (spec.columns or M.columns)(inner)
  local SLOT = (inner - (COLUMNS - 1) * GAP) / COLUMNS
  local METRICS = { half = (SLOT - GAP) / 2, gap = GAP, height = TILE_H }
  local TRAVEL = theme.spring.spatial
  local stamp = tostring({})
  local key = "eva." .. spec.key .. "."
  local zones = board.zones
  local cells = morf.signal(key .. "cells." .. stamp, { zones = {}, spare = {}, spare_rows = 0 })
  local carried = morf.signal(key .. "carried." .. stamp, "")
  local edited = morf.signal(key .. "edited." .. stamp, false)
  local lifted = morf.signal(key .. "lifted." .. stamp, "")
  local held_down = spec.lift and require("models.touchscreens").attached()
  local function editing() return board.editing:get() end

  -- A named zone keeps a row to drop into while it is empty.
  local function zone_height(zone)
    local rows = ((cells:get().zones[zone] or {}).rows) or 0
    return grid.height(spec.titles and math.max(1, rows) or rows, METRICS)
  end
  local function zone_top(index)
    local y = P.PAD + (spec.titles and ZONE_HEAD or 0)
    for i = 1, index - 1 do y = y + zone_height(zones[i]) + S.l + ZONE_HEAD end
    return y
  end
  local function main_bottom() return zone_top(#zones) + zone_height(zones[#zones]) end
  local function spare_top() return main_bottom() + SPARE_HEAD end
  local function height()
    if not editing() then return main_bottom() + P.PAD end
    local spare_rows = cells:get().spare_rows
    return spare_top() + grid.height(spare_rows, METRICS) + (spare_rows > 0 and S.l or 0) + P.BUTTON_H + P.PAD
  end

  -- The tile's box in the card, or nil while it has no place.
  local function place(id)
    local now = cells:get()
    for index, zone in ipairs(zones) do
      local cell = ((now.zones[zone] or {}).cells or {})[id]
      if cell then
        local x, y, width = grid.box(cell, METRICS)
        return P.PAD + x, zone_top(index) + y, width
      end
    end
    local cell = now.spare[id]
    if not cell then return nil end
    local x, y, width = grid.box(cell, METRICS)
    return P.PAD + x, spare_top() + y, width
  end

  local function shown_cell(id)
    local now = cells:get()
    for _, zone in ipairs(zones) do
      local cell = ((now.zones[zone] or {}).cells or {})[id]
      if cell then return cell end
    end
  end

  -- The zone under `y` in the card, and `y` inside its grid.
  local function zone_at(y)
    for index, zone in ipairs(zones) do
      if index == #zones or y < zone_top(index) + zone_height(zone) + S.s then return zone, y - zone_top(index) end
    end
  end

  local function tile(t)
    local id, name = t.id, t.name or t.id
    local at = { x = P.PAD, y = P.PAD, width = SLOT }
    local function box()
      local x, y, width = place(id)
      if x then at.x, at.y, at.width = x, y, width end
      return at
    end
    local function shown() return shown_cell(id) ~= nil end
    local function spare() return cells:get().spare[id] ~= nil end
    local function small()
      local cell = shown_cell(id) or cells:get().spare[id]
      return cell ~= nil and cell.span == 1
    end
    local function armed() return editing() and shown() and (not held_down or lifted:get() == id) end
    local function placed() return shown() or (editing() and spare()) end
    local function hold()
      if not editing() then board.editing:set(true) elseif held_down then lifted:set(id) end
    end

    local area = spec.face(t, { box = box, shown = shown, spare = spare, small = small, armed = armed,
      editing = editing, hold = hold, slot = SLOT, half = METRICS.half })

    local marks = ui.Loader { anchors = { fill = true }, keep = true, active = function() return edited:get() end,
      source = function()
        return ui.Item { anchors = { fill = true },
          badge { id = prefix .. "-hide-" .. id, name = "Hide " .. name, icon = "remove", edge = "top", visible = armed,
            tone = function() return C.errorContainer end, ink = function() return C.onErrorContainer end,
            on_clicked = function() board.hide(id) end },
          badge { id = prefix .. "-size-" .. id, name = "Change the size of " .. name, edge = "bottom", visible = armed,
            icon = function() return small() and "open_in_full" or "close_fullscreen" end,
            tone = function() return C.secondaryContainer end, ink = function() return C.onSecondaryContainer end,
            on_clicked = function() board.toggle_size(id) end },
          badge { id = prefix .. "-add-" .. id, name = "Add " .. name, icon = "add", edge = "top",
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
      id = prefix .. "-tile-" .. id, carrier = true, accessible_name = "Move " .. name,
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
        origin = { x = b.x - P.PAD + b.width / 2, y = b.y + TILE_H / 2 }
        carried:set(id)
      end,
      on_dropped = function()
        carried:set("")
        lifted:set("")
        require("haptics").fire("commit")
      end,
      on_reorder = function(step) board.step(id, step) end,
    }
    ui.reparent(body, holder)
    morf.effect(key .. "carry." .. id .. stamp, function()
      if not drag.active or not origin then return end
      local zone, y = zone_at(origin.y + drag.delta_y)
      local items = board.shown(zone)
      if board.zone_of(id) ~= zone then items[#items + 1] = { id = id, small = small() } end
      local index = grid.nearest(items, id, origin.x + drag.delta_x, y, COLUMNS, METRICS)
      if index and (items[index] or {}).id ~= id then board.move(id, index, zone) end
    end, { owner = holder })
    return holder
  end

  local wanted, layer = {}, { anchors = { fill = true } }
  for _, t in ipairs(spec.items) do
    wanted[t.id] = morf.signal(key .. "wanted." .. t.id .. stamp, false)
    layer[#layer + 1] = ui.Loader { anchors = { fill = true }, keep = true,
      z = function() return carried:get() == t.id and 10 or 0 end,
      active = function() return wanted[t.id]:get() end,
      source = function() return tile(t) end }
  end

  local available = ui.Item { x = P.PAD, y = function() return main_bottom() + S.l end, width = inner,
    height = L.CAPTION_H, visible = editing,
    L.caption { id = prefix .. "-available", width = inner, text = "Available",
      note = function() return spec.note(cells:get().spare_rows > 0) end } }
  local reset = ui.Item { x = P.PAD, width = inner, height = P.BUTTON_H, visible = editing,
    y = function()
      local spare_rows = cells:get().spare_rows
      return spare_top() + grid.height(spare_rows, METRICS) + (spare_rows > 0 and S.l or 0)
    end,
    P.button { id = prefix .. "-edit-reset", label = "Reset", icon = "restart_alt", on_clicked = board.reset } }

  local card_parts = { id = spec.card_id, width = w, height = height, radius = kit.round(P.RADIUS),
    behavior = { height = TRAVEL }, ui.Item(layer) }
  for index, zone in ipairs(zones) do
    local title = spec.titles and spec.titles[zone]
    if title then
      card_parts[#card_parts + 1] = ui.Item { x = P.PAD, width = inner, height = L.CAPTION_H,
        y = function() return zone_top(index) - ZONE_HEAD end,
        L.caption { id = prefix .. "-zone-" .. zone, width = inner, text = title } }
    end
  end
  card_parts[#card_parts + 1] = available
  card_parts[#card_parts + 1] = reset
  local card = kit.card(card_parts)

  morf.effect(key .. "layout." .. stamp, function()
    local now = { zones = {} }
    for _, zone in ipairs(zones) do
      local zone_cells, rows = grid.flow(board.shown(zone), COLUMNS)
      now.zones[zone] = { cells = zone_cells, rows = rows }
    end
    now.spare, now.spare_rows = grid.flow(board.spare(), COLUMNS)
    cells:set(now)
  end, { owner = card })
  morf.effect(key .. "wanted." .. stamp, function()
    local now, edit = cells:get(), editing()
    for id, signal in pairs(wanted) do
      if (shown_cell(id) or (edit and now.spare[id])) and not signal:get() then signal:set(true) end
    end
    if edit and not edited:get() then edited:set(true) end
  end, { owner = card })

  return { node = card, height = height }
end

return M
