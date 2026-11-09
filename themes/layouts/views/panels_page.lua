-- Settings, Eva, Panels: which panel holds which page. The board edits as the
-- quick tiles do (themes/layouts/views/quick_tiles.lua): a tile drags to its
-- place along any panel, Alt with the arrows walks it, the corner mark takes
-- it off to the Available pages or brings it back, and everything follows on
-- springs. The cards are the panels: one list of slots each, one under the
-- other, the Available pages last.
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
local TILE_H, GAP, COLUMN_W = 52, S.s, 176
local HEAD = L.CAPTION_H + S.s
local BETWEEN = S.l

function V.build(model, w, h)
  local board = model.panels
  local badge = require("themes").view("quick_tiles").badge
  local inner = w - 2 * P.PAD
  local COLUMNS = inner >= 2 * COLUMN_W + GAP and 2 or 1
  local SLOT = (inner - (COLUMNS - 1) * GAP) / COLUMNS
  local METRICS = { half = (SLOT - GAP) / 2, gap = GAP, height = TILE_H }
  local TRAVEL = theme.spring.spatial
  local stamp = tostring({})
  -- Every panel, then the spare pages, each with where it stands in the card.
  local plan = morf.signal("eva.panels.plan." .. stamp, { groups = {}, height = 0, at = {} })
  local carried = morf.signal("eva.panels.carried." .. stamp, "")
  local lifted = morf.signal("eva.panels.lifted." .. stamp, "")
  local fingers = require("models.touchscreens").attached()

  local function laid_out()
    local y, groups, at = P.PAD, {}, {}
    local function group(edge, name, keys)
      local items = {}
      for i, key in ipairs(keys) do items[i] = { id = key } end
      local cells, count = grid.flow(items, COLUMNS)
      local top = y + HEAD
      -- An empty panel keeps a row to drop a page on; nothing spare takes none.
      local bottom = top + grid.height(edge and math.max(count, 1) or count, METRICS)
      groups[#groups + 1] = { edge = edge, name = name, items = items, top = top, bottom = bottom }
      for key, cell in pairs(cells) do
        local x, cy, width = grid.box(cell, METRICS)
        at[key] = { x = P.PAD + x, y = top + cy, width = width, spare = edge == nil }
      end
      y = bottom + BETWEEN
    end
    for _, panel in ipairs(board.groups()) do group(panel.edge, panel.name, panel.keys) end
    group(nil, "Available", board.spare())
    return { groups = groups, height = y, at = at }
  end

  -- Where a tile let go at (x, y) in the card belongs.
  local function carry(key, x, y)
    local groups = plan:get().groups
    local target = groups[#groups]
    for _, group in ipairs(groups) do
      if y < group.bottom + BETWEEN / 2 then target = group break end
    end
    if not target.edge then
      if board.can_hide(key) and not plan:get().at[key].spare then board.hide(key) end
      return
    end
    local items, had = {}, false
    for i, item in ipairs(target.items) do
      items[i] = item
      had = had or item.id == key
    end
    if not had then items[#items + 1] = { id = key } end
    local index = grid.nearest(items, key, x - P.PAD, y - target.top, COLUMNS, METRICS) or 1
    local here = target.items[index]
    if not (had and here and here.id == key) then board.place(key, target.edge, index) end
  end

  local function tile(key, page)
    local last = { x = P.PAD, y = P.PAD, width = SLOT, spare = false }
    local function box()
      local at = plan:get().at[key]
      if at then last = at end
      return last
    end
    local function spare() return box().spare end
    -- Under a finger a page takes a long press to come loose, so a drag over
    -- the rest scrolls.
    local function loose() return not fingers or lifted:get() == key end
    local area = kit.action { id = "panels-page-" .. key, accessible_name = page.name, anchors = { fill = true },
      cursor = "pointer", enabled = function() return spare() or not loose() end,
      on_clicked = function() if spare() then board.add(key) end end,
      on_long_pressed = function() lifted:set(key) end,
      kit.icon(page.icon, 22, function() return C.onSurface end, { x = S.l, anchors = { vertical_center = true } }),
      kit.text { x = S.xxl + S.l, width = SLOT - S.xxl - S.l - S.xl, elide = "right", text = page.name,
        anchors = { vertical_center = true }, font_size = theme.size.small, font_weight = 500,
        color = function() return C.onSurface end },
    }
    ui.reparent(kit.tile_surface { id = "panels-page-" .. key .. "-shape", area = area,
      height = TILE_H, tone = "primary", z = -1, width = function() return box().width end }, area)
    local body = ui.Item { anchors = { fill = true },
      scale = function() return carried:get() == key and 1.04 or 1 end,
      behavior = { scale = theme.spring.fast },
      area,
      badge { id = "panels-hide-" .. key, name = "Take " .. page.name .. " off its panel", icon = "remove", edge = "top",
        visible = function() return not spare() and board.can_hide(key) end,
        tone = function() return C.errorContainer end, ink = function() return C.onErrorContainer end,
        on_clicked = function() board.hide(key) end },
      badge { id = "panels-add-" .. key, name = "Add " .. page.name, icon = "add", edge = "top", visible = spare,
        tone = function() return C.primary end, ink = function() return C.onPrimary end,
        on_clicked = function() board.add(key) end },
    }
    local origin
    local holder, drag = widgets.sortable_grid {
      id = "panels-tile-" .. key, carrier = true, accessible_name = "Move " .. page.name,
      -- A reorder of no step on the pointer: `carry` places it, and Alt with
      -- the arrows walks it.
      mode = "reorder", extent = 1e6,
      x = function() return box().x end, y = function() return box().y end,
      width = function() return box().width end, height = TILE_H,
      behavior = { x = TRAVEL, y = TRAVEL, width = TRAVEL },
      z = function() return carried:get() == key and 10 or 0 end,
      armed = function() return not spare() and loose() end, enabled = function() return not spare() and loose() end,
      focus_policy = function() return spare() and "none" or "tab" end,
      on_drag_started = function()
        local b = box()
        origin = { x = b.x + b.width / 2, y = b.y + TILE_H / 2 }
        carried:set(key)
      end,
      on_dropped = function()
        carried:set("")
        lifted:set("")
        require("haptics").fire("commit")
      end,
      on_reorder = function(step) board.step(key, step) end,
    }
    ui.reparent(body, holder)
    morf.effect("eva.panels.carry." .. key .. stamp, function()
      if drag.active and origin then carry(key, origin.x + drag.delta_x, origin.y + drag.delta_y) end
    end, { owner = holder })
    return holder
  end

  local layer = { anchors = { fill = true } }
  for _, key in ipairs(require("pages").ORDER) do
    layer[#layer + 1] = tile(key, require("pages").all[key])
  end

  -- A caption over each panel, and what an empty one says in its place.
  local heads = {}
  local function group_at(i) return plan:get().groups[i] end
  for i = 1, #board.groups() + 1 do
    local spare = i == #board.groups() + 1
    heads[#heads + 1] = ui.Item { x = P.PAD, width = inner, height = L.CAPTION_H,
      y = function() local g = group_at(i) return g and g.top - HEAD or 0 end,
      visible = function() return group_at(i) ~= nil end,
      behavior = { y = TRAVEL },
      L.caption { id = "panels-group-" .. i, width = inner,
        text = function() local g = group_at(i) return g and g.name or "" end,
        note = function()
          local g = group_at(i)
          if not g then return "" end
          if spare then return #g.items > 0 and "Tap to add" or "Every page has a panel" end
          return #g.items == 0 and "This edge opens nothing" or ""
        end } }
  end

  local reset = ui.Item { x = P.PAD, width = inner, height = P.BUTTON_H,
    y = function() return plan:get().height end,
    behavior = { y = TRAVEL },
    P.button { id = "panels-reset", width = inner, label = "Reset", icon = "restart_alt", on_clicked = board.reset } }

  local card = kit.card { id = "panels-board", width = w, radius = kit.round(P.RADIUS),
    height = function() return plan:get().height + P.BUTTON_H + P.PAD end,
    behavior = { height = TRAVEL },
    ui.Item(layer), reset, table.unpack(heads) }

  morf.effect("eva.panels.plan." .. stamp, function() plan:set(laid_out()) end, { owner = card })
  return P.page { id = "settings-panels-scroll", width = w, height = h,
    P.section { id = "settings-panels-note", width = w,
      P.row { id = "settings-panels-how", width = inner, icon = "dashboard_customize",
        on = function() return false end, title = "Drag a page to its panel",
        subtitle = "Changes land when you leave this page" } },
    card,
  }
end

return V
