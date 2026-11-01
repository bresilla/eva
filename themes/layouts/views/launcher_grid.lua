-- The launcher's icon grid: rows of tiles in the results' own list, category chips
-- over them, and an alphabet down the side. A press opens, a long press or a right
-- click lists a tile's actions.
--
-- A row is one press area over plain nodes, told which tile by where it was
-- pressed.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local C = theme.color
local S = theme.space
local V = {}

V.CELL_H = 104
V.CHIPS_H = 40
local ICON = 48

--- `name`'s icon at `size`, or nil where `icon_of` finds none.
local function picture(icon_of, name, size)
  local hit = name and name ~= "" and icon_of(name) or nil
  if not hit then return nil end
  if hit.name then
    return ui.Icon { width = size, height = size, name = hit.name, source_width = 96, source_height = 96 }
  end
  return ui.Image { width = size, height = size, source = hit.path, fill_mode = "preserve_aspect_fit" }
end

--- A folder's art: up to four of its apps on a tinted ground.
local function folder_art(icon_of, tile, size)
  local mini = (size - 3 * S.xs) // 2
  local ground = kit.surface { width = size, height = size, radius = kit.round(size / 3),
    color = function() return C.secondaryContainer end }
  for i, name in ipairs(tile.members or {}) do
    local node = picture(icon_of, name, mini)
      or kit.surface { width = mini, height = mini, radius = kit.round(mini / 3),
        color = function() return C.surfaceContainerHighest end }
    node.x = S.xs + ((i - 1) % 2) * (mini + S.xs)
    node.y = S.xs + ((i - 1) // 2) * (mini + S.xs)
    ui.reparent(node, ground)
  end
  if #(tile.members or {}) == 0 then
    ui.reparent(kit.icon("folder", size // 2, function() return C.onSecondaryContainer end,
      { anchors = { center_in = true } }), ground)
  end
  return ground
end

--- One tile's art at `size`: its app's icon, a folder's apps, or a glyph on a
--- tinted ground. `icon_of(name)` finds an icon (apps.icon).
function V.art(icon_of, tile, size)
  size = size or ICON
  if tile.kind == "folder" then return folder_art(icon_of, tile, size) end
  return picture(icon_of, tile.icon, size)
    or kit.surface { width = size, height = size, radius = kit.round(size / 3),
      color = function() return C.surfaceContainerHighest end,
      kit.icon(tile.material or "apps", size // 2, function() return C.onSurfaceVariant end,
        { anchors = { center_in = true } }) }
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
          cell.art = V.art(M.icon, tile)
          ui.reparent(cell.art, cell.box)
        end
        cell.key = key
      end
      if tile then
        cell.label.text = tile.name or ""
        cell.node.accessible_name = tile.name or ""
        cell.pin.visible = tile.pinned == true
        cell.fresh.visible = tile.fresh == true
        cell.box.opacity = tile.spent and 0.4 or 1
      end
    end
  end
  refill()

  local function tile_at(x)
    local i = math.floor(x / cell_w) + 1
    return bound.entry.cells[i], i
  end
  local press = ui.MouseArea {
    anchors = { fill = true }, cursor = "pointer", accepted_buttons = "all",
    on_clicked = function(_, _, x, _, button)
      local tile = tile_at(x)
      if not tile then return end
      if button == "right" then M.act_on(tile.key) return end
      M.activate(M.tile_row(tile.key))
    end,
    on_long_pressed = function(sx, sy, x)
      local tile = tile_at(x)
      if tile then ctx.carrier.lift(tile, sx, sy) end
    end,
    on_released = function(sx, sy) ctx.carrier.drop(sx, sy) end,
    on_touch_moved = function(_, sx, sy) ctx.carrier.carry(sx, sy) end,
    on_position_changed = function(sx, sy, _, _, x)
      ctx.carrier.carry(sx, sy)
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

--- What a held app becomes: a chip under the finger and places over the grid
--- to drop it on, together `width` wide. Let go where it was, its actions open;
--- dropped on a place, that place's action runs; dropped on another tile, the
--- two go in a folder, where `carrier.under(x, y)` says what tile is there.
--- Returns `node`, `held`, `lift(tile, x, y)`, `carry(x, y)`, `drop(x, y)`,
--- points being the surface's.
function V.carrier(M, width)
  local held = morf.signal("eva.launcher.held", false)
  local C_H = S.TARGET
  local holding = function() return held:get() ~= false end
  local target, root, carrier
  local PLACES = {
    { id = "launcher-pin-target", icon = "keep", label = "Pin to favourites", wanted = function() return true end,
      run = function(key) return M.pin(key) end },
    { id = "launcher-home-target", icon = "add_to_home_screen", label = "Add to home",
      wanted = function() return M.can_home() end, run = function(key) return M.to_home(key) end },
    { id = "launcher-out-target", icon = "folder_off", label = "Take out of folder",
      wanted = function() return M.folder:get() ~= "" end, run = function(key) return M.unfile(key) end },
  }
  local function places()
    local out = {}
    for _, place in ipairs(PLACES) do
      if place.wanted() then out[#out + 1] = place end
    end
    return out
  end
  -- The place a point is over: any height above the strip's foot, by column.
  local function over(x, y)
    if y >= (target.layout_y or 0) + (target.layout_height or 0) then return nil end
    local list = places()
    local at = math.floor((x - (target.layout_x or 0)) / (width / #list)) + 1
    return list[math.max(1, math.min(#list, at))]
  end
  local strip = {}
  for _, place in ipairs(PLACES) do
    local function index()
      for i, shown in ipairs(places()) do if shown == place then return i end end
    end
    strip[#strip + 1] = kit.surface { id = place.id, height = S.TOUCH, radius = kit.round(S.m),
      visible = function() return index() ~= nil end,
      x = function() return ((index() or 1) - 1) * width / #places() end,
      width = function() return width / #places() - (#places() > 1 and S.xs or 0) end,
      color = function()
        local now = held:get()
        return now and now.moved and over(now.x, now.y) == place and C.primaryContainer or C.surfaceContainerHigh
      end,
      ui.Row { anchors = { center_in = true }, gap = S.xs, align = "center",
        kit.icon(place.icon, 18, function() return C.primary end),
        kit.text { text = place.label, font_size = theme.size.small, color = function() return C.onSurface end } } }
  end
  strip.width, strip.height, strip.visible = width, S.TOUCH, holding
  target = ui.Item(strip)
  local chip = kit.surface { id = "launcher-held", z = 1, width = S.xxl * 4, height = C_H, radius = C_H / 2, visible = holding,
    x = function() local now = held:get() return now and now.x - (root.layout_x or 0) - S.xxl * 2 or 0 end,
    y = function() local now = held:get() return now and now.y - (root.layout_y or 0) - C_H or 0 end,
    color = function() return C.secondaryContainer end,
    kit.text { anchors = { center_in = true }, width = S.xxl * 4 - 2 * S.s, horizontal_alignment = "center", elide = "right",
      font_size = theme.size.small, color = function() return C.onSecondaryContainer end,
      text = function() local now = held:get() return now and now.name or "" end } }
  root = ui.Item { anchors = { fill = true }, z = 20, target, chip }
  carrier = { node = root, target = target, held = holding }
  function carrier.lift(tile, x, y)
    require("haptics").fire("long")
    held:set { key = tile.key, name = tile.name, x = x, y = y, from_x = x, from_y = y, moved = false }
  end
  function carrier.carry(x, y)
    local now = held:get()
    if not now then return end
    local moved = now.moved or math.max(math.abs(x - now.from_x), math.abs(y - now.from_y)) >= S.s
    held:set { key = now.key, name = now.name, x = x, y = y, from_x = now.from_x, from_y = now.from_y, moved = moved }
    if carrier.hover and not over(x, y) then carrier.hover(x, y) end
  end
  function carrier.drop(x, y)
    local now = held:get()
    if not now then return end
    held:set(false)
    if not now.moved then M.act_on(now.key) return end
    local place = over(x, y)
    local under = not place and carrier.under and carrier.under(x, y)
    local done = place and place.run(now.key) or under and under ~= now.key and M.gather(now.key, under)
    if done then require("haptics").fire("commit") end
  end
  return carrier
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
      if M.can_install() then rows[#rows + 1] = { key = "get", name = "Get apps", icon = "add_circle" } end
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
        elseif chip.key == "get" then M.activate_query("> get ")
        else M.choose_category(chip.category) end
      end,
      kit.surface { anchors = { fill = true }, radius = kit.round((V.CHIPS_H - S.s) / 2),
        color = function() return on() and C.secondaryContainer or C.surfaceContainerHigh end },
      ui.Row { anchors = { center_in = true }, gap = S.xs, align = "center",
        chip.icon and kit.icon(chip.icon, 16, function() return C.onSurfaceVariant end) or nil, label },
    }
  end
  local row = ui.Repeater { as = "row", gap = S.s, model = model, delegate = delegate }
  local flick = ui.Flickable { id = "launcher-chips", width = width, height = V.CHIPS_H, clip = true, row }
  -- Pulled past either end the chips run on elastically.
  return ui.Item { width = width, height = V.CHIPS_H, flick,
    on_panned = require("themes.overscroll").new { flick = flick, sideways = true,
      room = function() return (row.layout_width or 0) - (flick.layout_width or 0) end }.on_panned }
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
