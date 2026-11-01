-- The dock's body, shared by the themes' views: a plate and a bubble per icon,
-- all shapes of one field. An icon near the pointer grows, its bubble rises out
-- of the plate on a smooth seam, and it pushes its neighbours aside. `style`
-- says what the theme makes of it: `bubble` (a shape name), `radius` (the
-- plate's), `seam`, and `mark(index, row)` a node over each icon.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local card = require("themes.layouts.window_card")
local S, C = theme.space, theme.color
local M = {}

local PREVIEW_W, PREVIEW_H = 200, 128

function M.build(model, style)
  local spatial, fade, quick = theme.spring.spatial, theme.spring.effects, theme.spring.fast
  local gap = S.s
  local function vertical() return model.vertical() end
  local function size() return model.size() end
  local function taskbar() return model.mode() == "taskbar" end
  local function screen()
    local s = (morf.screens or {})[1] or {}
    return s.width or 1920, s.height or 1080
  end

  -- The icons' sizes, and where the row starts along the edge.
  local function count() return model.rows:len() + (model.overflow:get() > 0 and 1 or 0) end
  local function sizes()
    local at = model.pointer:get()
    local gain = model.magnifies() and model.GAIN or 0
    return model.sizes(count(), size(), gap, at >= 0 and at or nil, gain, model.REACH)
  end
  local function length()
    local _, total = sizes()
    return total + 2 * S.s
  end
  local function span()
    local w, h = screen()
    return vertical() and h or w
  end
  local function start() return (span() - length()) / 2 + S.s end
  local function along(i)
    local list = sizes()
    local at = start()
    for k = 1, i - 1 do at = at + (list[k] or 0) + gap end
    return at, list[i] or size()
  end

  -- Across the edge: the distance of the plate's far side from the edge.
  local depth = function() return size() + 2 * S.s end
  local margin = function() return taskbar() and 0 or theme.BORDER + S.s end
  local function plate_box()
    local w, h = screen()
    local d = depth()
    if taskbar() then return { x = 0, y = h - d, width = w, height = d } end
    if model.edge() == "bottom" then return { x = start() - S.s, y = h - d - margin(), width = length(), height = d } end
    if model.edge() == "left" then return { x = margin(), y = start() - S.s, width = d, height = length() } end
    return { x = w - d - margin(), y = start() - S.s, width = d, height = length() }
  end
  model.attach(plate_box)

  -- An icon's box: it stands on the plate's inner side and grows off the edge.
  local function icon_box(i)
    local at, s = along(i)
    local b, inset = plate_box(), S.s
    if model.edge() == "bottom" then return { x = at, y = b.y + b.height - inset - s, width = s, height = s } end
    if model.edge() == "left" then return { x = b.x + inset, y = at, width = s, height = s } end
    return { x = b.x + b.width - inset - s, y = at, width = s, height = s }
  end

  -- How far it slides off the edge when hidden.
  local function hidden_by() return model.shown() and 0 or depth() + margin() + S.xl * 2 end
  local function hide_x()
    if model.edge() == "left" then return -hidden_by() end
    if model.edge() == "right" then return hidden_by() end
    return 0
  end
  local function hide_y() return model.edge() == "bottom" and hidden_by() or 0 end

  local plate = ui.Item { id = "dock-plate",
    x = function() return plate_box().x end, y = function() return plate_box().y end,
    width = function() return plate_box().width end, height = function() return plate_box().height end,
    behavior = { x = quick, y = quick, width = quick, height = quick } }

  -- ------------------------------------------------------------ the field --
  local radius = style.radius or size() / 2
  local field = { id = "dock-field", anchors = { fill = true }, fill_color = function() return C.surfaceContainer end,
    blend = style.seam, blend_profile = style.profile or "quadratic", shadow_color = "#00000050", shadow_blur = 8,
    ui.SdfShape { id = "dock-shape", shape = "box", radius = function() return taskbar() and 0 or radius end, track = plate } }
  local bubbles = {}
  for i = 1, model.MAX_ICONS + 1 do
    local holder = ui.Item { id = "dock-bubble-" .. i,
      x = function() return icon_box(i).x end, y = function() return icon_box(i).y end,
      width = function() return icon_box(i).width end, height = function() return icon_box(i).height end,
      visible = function() return i <= count() end,
      behavior = { x = quick, y = quick, width = quick, height = quick } }
    bubbles[i] = holder
    field[#field + 1] = ui.SdfShape { id = "dock-bubble-shape-" .. i, shape = style.bubble, operation = "smooth_union",
      radius = style.bubble == "box" and (style.bubble_radius or 0) or nil, track = holder }
  end
  local sdf = ui.Sdf(field)

  -- ------------------------------------------------------------- an icon --
  local function delegate(row)
    local key = row.key
    local index = morf.signal("eva.dock.index." .. key, math.floor(row.index))
    local state = morf.state { count = math.floor(row.count), active = row.active, urgent = row.urgent,
      unread = math.floor(row.unread), pinned = row.pinned, missing = row.missing, name = row.name,
      first = row.first_running }
    local function box() return icon_box(index:get()) end
    local dragging
    local dots = {}
    for d = 1, 3 do
      dots[d] = kit.surface { id = "dock-dot-" .. math.floor(row.index) .. "-" .. d, width = S.xs, height = S.xs, radius = S.xxs,
        x = function() return box().width / 2 + (d - 2) * (S.xs + S.xxs) - S.xxs end,
        y = function() return box().height + S.xxs end,
        color = function() return state.active and C.primary or C.onSurfaceVariant end,
        visible = function() return state.count >= d end }
    end
    local badge = kit.surface { id = "dock-badge-" .. math.floor(row.index), z = 3, width = S.l + S.xxs, height = S.l + S.xxs,
      radius = (S.l + S.xxs) / 2, anchors = { top = true, right = true }, color = function() return C.error end,
      visible = function() return state.unread > 0 end,
      L.label { anchors = { center_in = true }, text = function() return tostring(state.unread) end,
        font_size = L.SIZE.micro, color = function() return C.onError end } }
    local divider = kit.surface { id = "dock-divider-" .. math.floor(row.index), width = 1, z = 2,
      x = -gap / 2, y = S.xs, height = function() return box().height - 2 * S.xs end,
      color = function() return C.outlineVariant end, visible = function() return state.first end }
    local area = ui.MouseArea { id = "dock-icon-area-" .. math.floor(row.index), anchors = { fill = true }, cursor = "pointer",
      accepted_buttons = { "left", "middle", "right" },
      accessible_role = "button", accessible_name = function() return state.name end,
      on_entered = function() model.peek(key) end,
      on_clicked = function(_, _, _, _, button)
        if button == "middle" then model.close(key)
        elseif button == "right" then model.open_menu(key)
        else model.activate(key) end
      end,
      on_wheel = function(_, _, _, _, _, step) model.cycle(key, step) end,
      on_drag_started = function() if state.pinned then dragging = index:get() end end,
      on_dragged = function(x, y)
        if not dragging then return end
        local at = vertical() and y or x
        local to = math.max(1, math.floor((at - start()) / (size() + gap)) + 1)
        if to ~= dragging and model.reorder(dragging, to) then dragging = to end
      end,
      on_released = function() dragging = nil end }
    local node = L.item { id = "dock-icon-" .. math.floor(row.index),
      x = function() return box().x end, y = function() return box().y end,
      width = function() return box().width end, height = function() return box().height end,
      behavior = { x = quick, y = quick, width = quick, height = quick },
      opacity = function() return state.missing and .4 or 1 end,
      loop = function()
        if not (state.urgent or model.launching:get() == key) then return nil end
        return { translate_y = { from = 0, to = -S.m, duration = 320, easing = "out_quad", alternate = true } }
      end,
      divider,
      ui.Item { anchors = { fill = true, margins = S.xs }, id = "dock-glyph-" .. math.floor(row.index),
        ui.Icon { anchors = { fill = true }, name = row.icon ~= "" and row.icon or "application-x-executable",
          source_width = 96, source_height = 96, visible = row.icon ~= "" },
        ui.Item { anchors = { center_in = true }, width = size() - 2 * S.xs, height = size() - 2 * S.xs,
          visible = row.icon == "", card.icon(row.class, row.initial_class, size() - 2 * S.xs) } },
      style.mark and style.mark(function() return index:get() end, state) or nil,
      dots[1], dots[2], dots[3], badge, area }
    return node, function(next_row)
      index:set(math.floor(next_row.index))
      state.count, state.active, state.urgent = math.floor(next_row.count), next_row.active, next_row.urgent
      state.unread, state.pinned, state.missing = math.floor(next_row.unread), next_row.pinned, next_row.missing
      state.name, state.first = next_row.name, next_row.first_running
    end
  end

  local more = kit.action { id = "dock-more", accessible_name = "More windows", cursor = "pointer",
    x = function() return icon_box(count()).x end, y = function() return icon_box(count()).y end,
    width = function() return icon_box(count()).width end, height = function() return icon_box(count()).height end,
    visible = function() return model.overflow:get() > 0 end,
    on_clicked = function() require("overview").open() end,
    L.label { anchors = { center_in = true }, text = function() return "+" .. model.overflow:get() end,
      color = kit.ink("hi") } }

  -- -------------------------------------------------------- the right press --
  local function menu_items()
    local key = model.menu_for:get()
    return key ~= "" and model.menu(key) or {}
  end
  local action_menu = require("themes.layouts.action_menu")
  local function menu_at(h)
    local b = plate_box()
    local w, screen_h = screen()
    local key, x = model.menu_for:get(), b.x
    for r = 1, model.rows:len() do
      local row = model.rows:get(r)
      if row.key == key then x = icon_box(math.floor(row.index)).x end
    end
    if model.edge() == "left" then return b.x + b.width + S.s, math.min(screen_h - h, b.y) end
    if model.edge() == "right" then return b.x - action_menu.WIDTH - S.s, math.min(screen_h - h, b.y) end
    return math.max(S.s, math.min(w - action_menu.WIDTH - S.s, x)), b.y - h - S.m
  end
  local menu = action_menu.build { id = "dock-menu", name = "Application menu", items = menu_items, at = menu_at,
    close = model.close_menu, opened = function() return model.menu_for:get() ~= "" end }

  -- -------------------------------------------------------------- previews --
  local function shown_windows()
    local key = model.preview_for:get()
    return key ~= "" and model.windows_of(key) or {}
  end
  local function preview_box()
    local n = math.min(#shown_windows(), 4)
    local b = plate_box()
    local w = n * PREVIEW_W + (n + 1) * S.s
    return { x = math.max(S.s, b.x + b.width / 2 - w / 2), y = b.y - PREVIEW_H - 2 * S.s - S.m, width = w }
  end
  local previews = { id = "dock-previews", z = 9, height = PREVIEW_H + 2 * S.s,
    x = function() return preview_box().x end, y = function() return preview_box().y end,
    width = function() return preview_box().width end,
    visible = function() return #shown_windows() > 0 and model.edge() == "bottom" end,
    opacity = function() return #shown_windows() > 0 and 1 or 0 end, behavior = { opacity = fade },
    kit.card { anchors = { fill = true } } }
  for i = 1, 4 do
    local function address() local c = shown_windows()[i] return c and c.address or "" end
    previews[#previews + 1] = ui.Item { id = "dock-preview-" .. i, x = S.s + (i - 1) * (PREVIEW_W + S.s), y = S.s,
      width = PREVIEW_W, height = PREVIEW_H, visible = function() return address() ~= "" end,
      card.picture { radius = S.s, address = address, class = function() local c = shown_windows()[i] return c and c.class or "" end,
        title = function() return "" end },
      ui.MouseArea { id = "dock-preview-area-" .. i, anchors = { fill = true }, cursor = "pointer",
        accessible_role = "button", accessible_name = "Window",
        on_clicked = function() require("windows_model").focus(address()) end } }
  end

  -- ------------------------------------------------------------- the root --
  local zone = ui.MouseArea { id = "dock-zone",
    x = function() local b = plate_box() return b.x - S.xl end,
    y = function() local b = plate_box() return b.y - (model.edge() == "bottom" and size() * model.GAIN + S.s or S.xl) end,
    width = function() local b = plate_box() return b.width + 2 * S.xl end,
    height = function()
      local b = plate_box()
      return b.height + (model.edge() == "bottom" and size() * model.GAIN + S.s + margin() or 2 * S.xl)
    end,
    visible = function() return model.shown() end,
    on_entered = model.entered, on_exited = model.left,
    on_position_changed = function(x, y)
      local at = (vertical() and y or x) - start()
      model.pointer:set(math.max(0, at))
    end }
  morf.effect("eva.dock.hover", function()
    if zone.contains_pointer then model.entered() elseif model.near:get() and model.autohide() ~= "off" then model.left() end
  end, { owner = zone })
  local strip = ui.MouseArea { id = "dock-strip",
    x = function()
      if model.edge() == "right" then return screen() - theme.BORDER - S.xs end
      return model.edge() == "left" and 0 or (screen() - length()) / 2
    end,
    y = function()
      local _, h = screen()
      if model.edge() == "bottom" then return h - theme.BORDER - S.xs end
      return (h - length()) / 2
    end,
    width = function() return vertical() and theme.BORDER + S.xs or length() end,
    height = function() return vertical() and length() or theme.BORDER + S.xs end,
    visible = function() return model.on() and not model.shown() end }
  -- The pointer over the strip, whatever is drawn above it.
  morf.effect("eva.dock.edge", function()
    if strip.contains_pointer then model.edge_entered() else model.edge_left() end
  end, { owner = strip })

  local content = { id = "dock-body", anchors = { fill = true },
    translate_x = hide_x, translate_y = hide_y,
    behavior = { translate_x = theme.spring.drawer, translate_y = theme.spring.drawer },
    stretch = theme.stretch and theme.stretch.drawer or nil,
    zone, sdf, plate, ui.Repeater { id = "dock-icons", model = model.rows, delegate = delegate }, more }
  for _, bubble in ipairs(bubbles) do content[#content + 1] = bubble end
  local root = ui.Item { id = "dock", anchors = { fill = true },
    accessible_role = "toolbar", accessible_name = "Dock",
    visible = function() return model.on() end,
    ui.Item(content), strip, ui.Item(previews), menu }
  return { node = root }
end

return M
