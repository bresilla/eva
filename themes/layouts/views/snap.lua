-- Snapping's surfaces (shell/snap.lua): where a dragged window will land, the
-- layout picker, and the offer to fill the room left. The landing box is a
-- field of its own that runs from zone to zone and stretches on the way.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local card = require("themes.layouts.window_card")
local cells = require("snap_model")
local S, C = theme.space, theme.color
local V = {}

local PICK_W, PICK_H = 112, 72

function V.build(model)
  local spatial, fade = theme.spring.spatial, theme.spring.effects
  local radius = L.control_round(2 * S.xl)

  -- --------------------------------------------------------- the landing --
  local function landing()
    local zone = model.zone:get()
    return zone ~= "" and model.preview(zone) or nil
  end
  local last = { x = 0, y = 0, width = 1, height = 1 }
  local function box()
    local b = landing()
    if b then last = b end
    return last
  end
  local marker = ui.Item { id = "snap-landing",
    x = function() return box().x end, y = function() return box().y end,
    width = function() return box().width end, height = function() return box().height end,
    behavior = { x = spatial, y = spatial, width = spatial, height = spatial },
    opacity = function() return model.zone:get() ~= "" and 1 or 0 end,
    kit.surface { anchors = { fill = true }, radius = radius, color = "transparent",
      border_width = 2, border_color = kit.stroke("hot") } }
  local field = ui.Sdf { id = "snap-field", anchors = { fill = true }, blend = 0,
    fill_color = function() return C.primary:alpha(.22) end,
    opacity = function() return model.zone:get() ~= "" and 1 or 0 end, behavior = { opacity = fade },
    ui.SdfShape { id = "snap-shape", shape = "box", radius = radius, track = marker } }

  -- ------------------------------------------------------------ the picker --
  local function diagram(cell_names, on_cell, id)
    local parts = { width = PICK_W, height = PICK_H }
    for i, name in ipairs(cell_names) do
      local c = cells.CELLS[name]
      local area = kit.action { id = id .. "-cell-" .. i, accessible_name = (name:gsub("_", " ")), cursor = "pointer",
        x = c[1] * PICK_W + 1, y = c[2] * PICK_H + 1,
        width = c[3] * PICK_W - 2, height = c[4] * PICK_H - 2,
        on_clicked = function() on_cell(name) end }
      ui.reparent(kit.surface { anchors = { fill = true }, z = -1, radius = S.xs,
        color = function() return area.hovered and C.primary or C.surfaceContainerHighest end }, area)
      parts[#parts + 1] = area
    end
    return ui.Item(parts)
  end
  local grid = { x = S.l, y = S.xxl + S.s, columns = 4, gap = S.m }
  for _, layout in ipairs(cells.LAYOUTS) do
    local id = "snap-layout-" .. layout.key
    grid[#grid + 1] = ui.Column { gap = S.xs,
      diagram(layout.cells, model.choose, id),
      kit.action { id = id .. "-all", width = PICK_W, height = L.lh(L.SIZE.label), cursor = "pointer",
        accessible_name = "Lay out the workspace: " .. layout.name,
        on_clicked = function() model.choose_layout(layout.key) end,
        L.label { anchors = { fill = true }, horizontal_alignment = "center", elide = "right", text = layout.name,
          color = kit.ink("lo") } } }
  end
  local picker_w = 4 * PICK_W + 3 * S.m + 2 * S.l
  local keys = ui.Item { id = "snap-keys", width = 1, height = 1, tab_navigation = false, on_key_pressed = model.key }
  local row_h = PICK_H + S.xs + L.lh(L.SIZE.label)
  local picker = kit.card { id = "snap-picker", width = picker_w, height = S.xxl + S.s + 2 * row_h + S.m + S.l,
    anchors = { center_in = true },
    accessible_role = "dialog", accessible_name = "Snap layouts",
    visible = function() return model.picking:get() end,
    opacity = function() return model.picking:get() and 1 or 0 end,
    scale = function() return model.picking:get() and 1 or .94 end,
    behavior = { opacity = fade, scale = spatial },
    ui.MouseArea { anchors = { fill = true } },
    kit.text { x = S.l, y = S.m, text = "Snap this window", font_size = theme.size.normal, color = kit.ink("hi") },
    ui.Grid(grid) }
  grid = nil

  -- ----------------------------------------------------------- the offers --
  local function slot(address) return model.offer_slots:get()[address] or { x = 0, y = 0, width = 0, height = 0 } end
  local function offer(row)
    local address = row.address
    local index = math.floor(row.index)
    return ui.Item { id = "snap-offer-" .. index,
      x = function() return slot(address).x end, y = function() return slot(address).y end,
      width = function() return slot(address).width end, height = function() return slot(address).height end,
      behavior = { x = spatial, y = spatial, width = spatial, height = spatial },
      card.picture { radius = radius, address = function() return address end, class = function() return row.class end,
        initial = function() return row.initial_class end, title = function() return row.title end },
      ui.Item { anchors = { bottom = true, horizontal_center = true, bottom_margin = S.s }, z = 2, height = 28,
        width = function() return math.max(40, slot(address).width - 2 * S.s) end,
        card.caption { height = 28, class = function() return row.class end,
          initial = function() return row.initial_class end, title = function() return row.title end,
          room = function() return math.max(40, slot(address).width - 2 * S.s) end } },
      ui.MouseArea { id = "snap-offer-area-" .. index, anchors = { fill = true }, cursor = "pointer",
        accessible_role = "button", accessible_name = row.title,
        on_clicked = function() model.fill(address) end } }
  end
  local function free_box(i)
    local name = model.free:get()[i]
    return name and model.preview(name) or { x = 0, y = 0, width = 0, height = 0 }
  end
  local holes = { id = "snap-free", anchors = { fill = true },
    visible = function() return model.assisting:get() end }
  for i = 1, 3 do
    holes[#holes + 1] = kit.surface { id = "snap-free-" .. i, radius = radius, color = function() return C.surfaceContainer:alpha(.86) end,
      border_width = 2, border_color = kit.stroke("mark"),
      x = function() return free_box(i).x end, y = function() return free_box(i).y end,
      width = function() return free_box(i).width end, height = function() return free_box(i).height end,
      behavior = { x = spatial, y = spatial, width = spatial, height = spatial },
      visible = function() return model.free:get()[i] ~= nil end }
  end
  local assist = ui.Item { id = "snap-assist", anchors = { fill = true },
    visible = function() return model.assisting:get() end,
    ui.MouseArea { anchors = { fill = true }, on_clicked = function() model.end_assist() end },
    ui.Item(holes), ui.Repeater { model = model.offers, delegate = offer } }

  local picker_catcher = ui.MouseArea { id = "snap-catcher", anchors = { fill = true },
    visible = function() return model.picking:get() end, on_clicked = function() model.end_pick() end }

  local root = ui.Item { id = "snap", anchors = { fill = true },
    visible = function() return model.dragging:get() or model.picking:get() or model.assisting:get() end,
    field, marker, assist, picker_catcher, picker, keys }
  return { node = root, shown = function(open) keys.focus = open end }
end

return V
