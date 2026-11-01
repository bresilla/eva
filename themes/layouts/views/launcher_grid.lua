-- The launcher's icon grid: rows of tiles in the results' own list, category chips
-- over them, and an alphabet down the side. A press opens, a long press or a right
-- click lists a tile's actions.
--
-- A row is one press area over plain nodes, told which tile by where it was
-- pressed: a screen of apps stays cheap to build and to rebind as it scrolls.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local C = theme.color
local S = theme.space
local V = {}

V.CELL_MIN, V.CELL_MAX = 72, 96
V.CELL_H = 104
V.CHIPS_H = 40
local ICON = 48

--- One tile's art: its app's icon, or a glyph on a tinted ground.
local function art(M, tile)
  local hit = tile.icon and tile.icon ~= "" and M.icon(tile.icon) or nil
  if tile.kind == "folder" or not hit then
    return kit.surface { width = ICON, height = ICON, radius = kit.round(ICON / 3),
      color = function() return tile.kind == "folder" and C.secondaryContainer or C.surfaceContainerHighest end,
      kit.icon(tile.material or "apps", 26, function() return C.onSurfaceVariant end, { anchors = { center_in = true } }) }
  end
  if hit.name then
    return ui.Icon { width = ICON, height = ICON, name = hit.name, source_width = 96, source_height = 96 }
  end
  return ui.Image { width = ICON, height = ICON, source = hit.path, fill_mode = "preserve_aspect_fit" }
end

--- A row of `columns` tiles, `ctx.cell` wide each, rebindable as the list scrolls.
function V.row(M, entry, columns, ctx)
  local cell_w = ctx.cell
  local bound = { entry = entry }
  local cells = {}
  for i = 1, columns do
    local box = ui.Item { width = ICON, height = ICON, anchors = { horizontal_center = true }, y = S.s }
    local label = kit.text {
      y = S.s + ICON + S.xs, x = S.xs, width = cell_w - S.s, horizontal_alignment = "center", elide = "right",
      font_size = theme.size.small, color = function() return C.onSurface end, text = "",
    }
    local pin = kit.icon("keep", 14, function() return C.primary end, { x = cell_w - S.l - S.s, y = S.xs, visible = false })
    local fresh = ui.Rect { x = cell_w - S.l - S.xs, y = S.s, width = S.s, height = S.s, radius = S.xs, visible = false,
      color = function() return C.primary end }
    local node = ui.Item { x = (i - 1) * cell_w, width = cell_w, height = V.CELL_H, visible = false,
      accessible_role = "button", box, label, pin, fresh }
    cells[i] = { node = node, box = box, label = label, pin = pin, fresh = fresh, key = "" }
  end
  local function refill()
    for i, cell in ipairs(cells) do
      local tile = bound.entry.cells[i]
      local key = tile and tile.key or ""
      cell.node.visible = tile ~= nil
      if cell.key ~= key then
        if cell.art then ui.destroy(cell.art, true) cell.art = nil end
        if tile then
          cell.art = art(M, tile)
          ui.reparent(cell.art, cell.box)
        end
        cell.key = key
      end
      if tile then
        cell.label.text = tile.name or ""
        cell.node.accessible_name = tile.name or ""
        cell.pin.visible = tile.pinned == true
        cell.fresh.visible = tile.fresh == true
      end
    end
  end
  refill()

  local function tile_at(x)
    local i = math.floor(x / cell_w) + 1
    return bound.entry.cells[i], i
  end
  local press = ui.MouseArea {
    anchors = { fill = true }, cursor = "pointer",
    on_clicked = function(_, _, x, _, button)
      local tile = tile_at(x)
      if not tile then return end
      if button == "right" then M.act_on(tile.key) return end
      M.activate(M.tile_row(tile.key))
    end,
    on_long_pressed = function(_, _, x)
      local tile = tile_at(x)
      if tile then M.act_on(tile.key) end
    end,
    on_position_changed = function(_, _, _, _, x)
      local tile, i = tile_at(x)
      if not tile then return end
      local at = ctx.index_of(bound.entry.key)
      if at and (M.selected:get() ~= at or M.cell:get() ~= i) then
        M.selected:set(at)
        M.cell:set(i)
      end
    end,
  }
  local nodes = { id = "launcher-tiles-" .. entry.key, width = columns * cell_w, height = V.CELL_H }
  for i, cell in ipairs(cells) do nodes[i] = cell.node end
  nodes[#nodes + 1] = press
  local row = ui.Item(nodes)
  return row, function(next_entry)
    bound.entry = next_entry
    row.id = "launcher-tiles-" .. next_entry.key
    refill()
  end
end

--- The chips over the grid: every app, the modes, and each category; inside a
--- folder, the way back.
function V.chips(M, width)
  local model = morf.list_model({})
  morf.effect("eva.launcher.chips", function()
    if not M.opened:get() then return end
    local rows = {}
    if M.folder:get() ~= "" then rows[1] = { key = "back", name = "Back", icon = "arrow_back" }
    else
      for _, chip in ipairs(M.chips()) do rows[#rows + 1] = { key = "c:" .. chip.key, name = chip.name, category = chip.key } end
      table.insert(rows, 2, { key = "modes", name = "Modes", icon = "category" })
    end
    model:replace(rows, "key")
  end)
  local function delegate(chip)
    local function on()
      return chip.category ~= nil and M.category:get() == chip.category and M.folder:get() == ""
    end
    local label = kit.text { text = chip.name, font_size = theme.size.small, font_weight = 500,
      color = function() return on() and C.onSecondaryContainer or C.onSurfaceVariant end }
    local width_of = function() return (label.layout_width or 40) + 2 * S.m + (chip.icon and S.l + S.xs or 0) end
    return kit.action {
      id = "launcher-chip-" .. chip.key, accessible_name = chip.name, width = width_of, height = V.CHIPS_H - S.s, cursor = "pointer",
      on_clicked = function()
        if chip.key == "back" then M.open_folder("")
        elseif chip.key == "modes" then M.set_query("> ")
        else M.choose_category(chip.category) end
      end,
      kit.surface { anchors = { fill = true }, radius = kit.round((V.CHIPS_H - S.s) / 2),
        color = function() return on() and C.secondaryContainer or C.surfaceContainerHigh end },
      ui.Row { anchors = { center_in = true }, gap = S.xs, align = "center",
        chip.icon and kit.icon(chip.icon, 16, function() return C.onSurfaceVariant end) or nil, label },
    }
  end
  return ui.Flickable {
    id = "launcher-chips", width = width, height = V.CHIPS_H, clip = true,
    ui.Repeater { as = "row", gap = S.s, model = model, delegate = delegate },
  }
end

--- The alphabet down the grid's side: a press or a drag goes to a letter.
function V.alphabet(M, height, jump)
  local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local labels = {}
  for i = 1, #LETTERS do
    labels[i] = kit.text { text = LETTERS:sub(i, i), width = S.l, horizontal_alignment = "center",
      font_size = theme.size.smaller, color = function() return C.onSurfaceVariant end,
      height = function() return height() / #LETTERS end, vertical_alignment = "center" }
  end
  local function at(y)
    local index = math.max(1, math.min(#LETTERS, math.floor(y / height() * #LETTERS) + 1))
    jump(LETTERS:sub(index, index))
  end
  return ui.Item {
    id = "launcher-alphabet", width = S.xl, height = height,
    ui.Column { anchors = { right = true, top = true }, gap = 0, table.unpack(labels) },
    ui.MouseArea { anchors = { fill = true }, drag_axis = "y",
      on_pressed = function(_, _, _, y) at(y) end,
      on_dragged = function(_, _, _, _, _, y) at(y) end },
  }
end

return V
