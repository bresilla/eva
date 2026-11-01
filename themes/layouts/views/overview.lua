-- The overview (shell/overview.lua): the workspaces in a strip with a window
-- map on each, the search under them, and the cards. A card is a window's
-- picture on a shape of one field: the field's seam is wide while the cards
-- are still on their windows, so they part from each other like a liquid, and
-- closes as they land. Only kit calls and theme tokens draw.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local card = require("themes.layouts.window_card")
local shots = require("window_shots")
local S, C = theme.space, theme.color
local V = {}

-- A field holds 16 layers; the cards past this draw on their own.
local LAYERS = 14
local SEAM = 48

function V.build(model)
  local spatial = theme.spring.spatial
  local fade = theme.spring.effects
  local pull = model.pull
  local function radius() return L.control_round(2 * S.xl) end
  local function lerp(a, b, t) return a + (b - a) * t end
  local nodes = {}

  -- Each card's box: from its window to its slot, as far as the pull has gone.
  local function box(address)
    local slot = model.slots:get()[address]
    local rect = model.rect(address)
    local t = pull:get()
    if not slot then return rect end
    return { x = lerp(rect.x - model.scrolled:get(), slot.x, t), y = lerp(rect.y, slot.y, t),
      width = lerp(rect.width, slot.width, t), height = lerp(rect.height, slot.height, t) }
  end
  local function cards() return model.layout() == "cards" end

  -- ------------------------------------------------------------ the field --
  local shapes = {}
  local field = { id = "overview-field", anchors = { fill = true },
    fill_color = function() return C.surfaceContainerHigh end,
    blend = function() return SEAM * (1 - pull:get()) end,
    behavior = { blend = fade } }
  for i = 1, LAYERS do
    shapes[i] = ui.SdfShape { id = "overview-shape-" .. i, shape = "box", radius = radius(), opacity = 0,
      operation = i == 1 and "union" or "smooth_union" }
    field[#field + 1] = shapes[i]
  end
  local sdf = ui.Sdf(field)
  local function bind_shapes()
    local i = 0
    for r = 1, model.cards:len() do
      local node = nodes[model.cards:get(r).address]
      if node and i < LAYERS then
        i = i + 1
        shapes[i].track = node
        shapes[i].opacity = 1
      end
    end
    for k = i + 1, LAYERS do
      shapes[k].track = nil
      shapes[k].opacity = 0
    end
  end

  -- -------------------------------------------------------------- a card --
  local function delegate(row)
    local address = row.address
    row.index = math.floor(row.index)
    local title, class = morf.signal("eva.overview.card.title." .. address, row.title), row.class
    local function selected() return model.selected:get() == address end
    local function dragged() return model.drag.address == address end
    local area, node
    local pressed_on
    local function on_pan(phase, dx, dy, _, vy)
      if model.layout() ~= "cards" then return false end
      if phase == "begin" then return dy < 0 and math.abs(dy) > math.abs(dx) end
      if phase == "update" then node.translate_y = math.min(0, dy)
      elseif phase == "end" and model.thrown(dy, vy) then
        morf.animation.play { { node = node, property = "translate_y", to = -2 * (node.height or 800),
          duration = theme.bounce.fast.duration, easing = theme.bounce.fast.easing },
          on_finished = function() model.close_window(address) end }
      else
        morf.animation.play { { node = node, property = "translate_y", to = 0,
          duration = theme.bounce.spatial.duration, easing = theme.bounce.spatial.easing } }
      end
    end
    area = ui.MouseArea { id = "overview-card-area-" .. row.index, anchors = { fill = true }, cursor = "pointer",
      accepted_buttons = { "left", "middle", "right" },
      accessible_role = "button", accessible_name = function() return title:get() end,
      on_panned = on_pan,
      on_pressed = function(x, y, _, _, button) pressed_on = { x = x, y = y, button = button } end,
      on_clicked = function(_, _, _, _, button)
        if button == "middle" then model.close_window(address)
        elseif button == "right" then model.menu_for:set(address)
        else model.activate(address) end
      end,
      on_long_pressed = function() model.menu_for:set(address) end,
      on_drag_started = function(x, y)
        if model.layout() == "cards" then return end
        local from = pressed_on or { x = x, y = y }
        model.drag_start(address, from.x, from.y)
      end,
      on_dragged = function(x, y) model.drag_move(x, y) end,
      on_released = function() model.drag_end() end,
    }
    local close = kit.action { id = "overview-card-close-" .. row.index, width = S.xl, height = S.xl,
      accessible_name = "Close window", cursor = "pointer",
      anchors = { top = true, right = true, top_margin = S.xs, right_margin = S.xs }, z = 3,
      visible = function()
        return model.layout() ~= "cards" and (area.hovered or selected())
      end,
      on_clicked = function() model.close_window(address) end,
      kit.surface { anchors = { fill = true }, radius = S.xs, color = function() return C.surfaceContainerHighest end },
      kit.icon("close", 16, kit.ink("hi"), { anchors = { center_in = true } }) }
    node = ui.Item { id = "overview-card-" .. row.index,
      x = function() return box(address).x end, y = function() return box(address).y end,
      width = function() return box(address).width end, height = function() return box(address).height end,
      opacity = function() return dragged() and .3 or 1 end,
      behavior = { x = spatial, y = spatial, width = spatial, height = spatial, opacity = fade },
      stretch = theme.stretch and theme.stretch.drawer or nil,
      exit = { opacity = 0, scale = .9, duration = theme.bounce.fast.duration, easing = theme.bounce.fast.easing },
      card.picture { id = "overview-card-picture-" .. row.index, radius = radius(),
        address = function() return address end, class = function() return class end,
        initial = function() return row.initial_class end, title = function() return title:get() end },
      ui.Item { id = "overview-card-caption-" .. row.index, anchors = { horizontal_center = true },
        y = function()
          if cards() then return -(32 + S.s) end
          return box(address).height - 32 - S.s
        end,
        width = function() return math.min(280, math.max(40, box(address).width - 2 * S.s)) end, height = 32, z = 2,
        opacity = function() return pull:get() end, behavior = { opacity = fade },
        card.caption { id = "overview-card-title-" .. row.index, class = function() return class end,
          initial = function() return row.initial_class end, title = function() return title:get() end,
          room = function() return math.max(40, box(address).width - 2 * S.s) end } },
      kit.surface { id = "overview-card-focus-" .. row.index, anchors = { fill = true }, z = 2, color = "transparent",
        radius = radius(), border_width = 2, border_color = kit.stroke("hot"),
        visible = function() return selected() and not cards() end },
      kit.surface { id = "overview-card-kept-" .. row.index, z = 3, width = S.xl, height = S.xl, radius = S.s,
        anchors = { top = true, left = true, top_margin = S.xs, left_margin = S.xs },
        color = function() return C.surfaceContainerHighest end,
        visible = function() return model.is_kept(address) end,
        kit.icon("lock", 14, kit.ink("hi"), { anchors = { center_in = true } }) },
      area, close,
      kit.action { id = "overview-card-more-" .. row.index, width = S.TARGET, height = S.TARGET, z = 4,
        accessible_name = "Window actions", cursor = "pointer",
        anchors = { right = true, right_margin = -S.xs }, y = -(S.TARGET + S.xs),
        visible = cards,
        on_clicked = function() model.menu_for:set(address) end,
        kit.icon("more_vert", 20, kit.ink("hi"), { anchors = { center_in = true } }) },
    }
    nodes[address] = node
    return node, function(next_row)
      title:set(next_row.title)
      class = next_row.class
    end
  end

  local repeater = ui.Repeater { id = "overview-cards", model = model.cards, delegate = delegate }
  local track = ui.Item { id = "overview-track", anchors = { fill = true }, sdf, repeater }
  morf.effect("eva.overview.shapes", function()
    model.cards:len()
    model.slots:get()
    morf.time.timer(1, bind_shapes, false)
  end)

  -- ------------------------------------------------------------- the strip --
  local function desk_box(id) return model.strip:get()[tostring(id)] or { x = 0, y = 0, width = 0, height = 0 } end
  local function desk_delegate(row)
    local id = math.tointeger(math.floor(row.id))
    local name = morf.signal("eva.overview.desk.name." .. id, row.name)
    local function viewing() return model.viewing:get() == id end
    local function over() return model.drag.over == id end
    local minis = morf.list_model({})
    morf.effect("eva.overview.desk." .. id, function()
      model.strip:get()
      local rows = {}
      for _, d in ipairs(model.desk_rows or {}) do
        if d.id == id then
          for i, c in ipairs(d.windows) do
            rows[i] = { address = c.address, class = c.class, initial_class = c.initial_class }
          end
        end
      end
      minis:replace(rows, "address")
    end)
    local function mini(m)
      local function rect()
        local b, r = desk_box(id), model.rect(m.address)
        local w, h = model.size()
        local fx, fy = b.width / math.max(1, w), b.height / math.max(1, h)
        return { x = r.x * fx, y = r.y * fy, width = math.max(4, r.width * fx), height = math.max(4, r.height * fy) }
      end
      return ui.Item { x = function() return rect().x end, y = function() return rect().y end,
        width = function() return rect().width end, height = function() return rect().height end,
        card.picture { radius = S.xs, glyph = 16, address = function() return m.address end,
          class = function() return m.class end, initial = function() return m.initial_class end,
          title = function() return "" end } }
    end
    local area = ui.MouseArea { id = "overview-desk-area-" .. id, anchors = { fill = true }, cursor = "pointer",
      accessible_role = "button", accessible_name = function() return "Workspace " .. name:get() end,
      on_clicked = function() if viewing() then model.enter(id) else model.view(id) end end,
      on_double_clicked = function() model.rename(id) end }
    return kit.surface { id = "overview-desk-" .. id,
      x = function() return desk_box(id).x end, y = function() return desk_box(id).y end,
      width = function() return desk_box(id).width end, height = function() return desk_box(id).height end,
      behavior = { x = spatial, y = spatial, width = spatial, height = spatial },
      radius = radius() / 2,
      color = function() return viewing() and C.surfaceContainerHighest or C.surfaceContainer end,
      border_width = function() return (over() or viewing()) and 2 or 0 end,
      border_color = kit.stroke("hot"),
      scale = function() return over() and 1.05 or 1 end, behavior_scale = nil,
      ui.Item { anchors = { fill = true }, clip = true,
        ui.Repeater { model = minis, delegate = mini } },
      kit.surface { anchors = { left = true, bottom = true, left_margin = S.xs, bottom_margin = S.xs }, z = 2,
        height = L.lh(L.SIZE.label), radius = S.xs,
        width = function() return math.min(desk_box(id).width - 2 * S.xs, S.s * 2 + 8 * #name:get()) end,
        color = function() return C.surface:alpha(.8) end,
        L.label { anchors = { fill = true, left_margin = S.xs, right_margin = S.xs }, elide = "right",
          text = function() return name:get() end, color = kit.ink("hi") } },
      area,
    }, function(next_row) name:set(next_row.name) end
  end
  local strip = ui.Repeater { id = "overview-strip", model = model.desks, delegate = desk_delegate }

  -- ------------------------------------------------------------ the search --
  local field_w = 420
  local input = ui.TextInput { id = "overview-search", anchors = { fill = true, left_margin = S.xxl, right_margin = S.m },
    vertical_alignment = "center", tab_navigation = false,
    font_family = theme.font, font_size = theme.size.normal,
    color = function() return C.onSurface end,
    placeholder = "Type to find a window", placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end,
    selection_color = function() return C.primary:alpha(.35) end,
    on_text_changed = function(text) model.query:set(text) end,
    on_accepted = function() model.activate() end,
    on_escape = function() model.close() end,
    on_key_pressed = model.key }
  local search = kit.card { id = "overview-search-box", width = field_w, height = model.SEARCH_H,
    x = function() return (select(1, model.size()) - field_w) / 2 end, y = S.xl + model.STRIP_H + S.l,
    opacity = function() return pull:get() end, behavior = { opacity = fade },
    visible = function() return model.layout() ~= "cards" end,
    ui.Item { width = S.xl, height = S.xl, x = S.s, y = (model.SEARCH_H - S.xl) / 2,
      kit.icon("search", S.xl - S.xs, kit.ink("lo"), { anchors = { center_in = true } }) },
    input }

  -- ------------------------------------- how it tiles, and the scratchpads --
  local row_y = S.xl + model.STRIP_H + S.l
  local function row_shown() return not cards() end
  local layouts = { id = "overview-layouts", gap = S.xs, y = row_y + (model.SEARCH_H - S.TARGET) / 2,
    x = function() return (select(1, model.size()) - field_w) / 2 - 4 * 84 - 3 * S.xs - S.l end,
    opacity = function() return pull:get() end, behavior = { opacity = fade }, visible = row_shown }
  for _, layout in ipairs(model.LAYOUTS) do
    local function chosen() return model.layout_of(model.viewing:get()) == layout end
    layouts[#layouts + 1] = kit.action { id = "overview-layout-" .. layout, width = 84, height = S.TARGET, cursor = "pointer",
      accessible_name = "Tile as " .. layout,
      on_clicked = function() model.choose_layout(layout) end,
      kit.surface { anchors = { fill = true }, radius = L.control_round(S.TARGET),
        color = function() return chosen() and C.secondaryContainer or C.surfaceContainerHigh end },
      L.label { anchors = { center_in = true }, text = layout:gsub("^%l", string.upper),
        color = function() return chosen() and C.onSecondaryContainer or C.onSurfaceVariant end } }
  end
  local function pad_delegate(row)
    local name = row.name
    local count = morf.signal("eva.overview.pad.count." .. name, math.floor(row.count))
    local shown = morf.signal("eva.overview.pad.shown." .. name, row.shown == true)
    local function over() return model.drag.pad == name end
    return kit.action { id = "overview-pad-" .. math.floor(row.index), width = model.PAD_W, height = S.TARGET, cursor = "pointer",
      accessible_name = "Scratchpad " .. name,
      x = function() return model.pad_box(math.floor(row.index)).x end, y = function() return model.pad_box(math.floor(row.index)).y end,
      on_clicked = function() model.close() model.toggle_scratch(name) end,
      kit.surface { anchors = { fill = true }, radius = L.control_round(S.TARGET),
        color = function() return (shown:get() or over()) and C.secondaryContainer or C.surfaceContainerHigh end,
        border_width = function() return over() and 2 or 0 end, border_color = kit.stroke("hot") },
      kit.icon(row.icon, 18, kit.ink("lo"), { x = S.s, y = (S.TARGET - 18) / 2 }),
      kit.text { x = S.xl + S.xs, y = 0, height = S.TARGET, vertical_alignment = "center", elide = "right",
        width = model.PAD_W - S.xl - S.xs - S.xl, text = name, font_size = L.SIZE.body, color = kit.ink("hi") },
      L.label { anchors = { right = true, vertical_center = true, right_margin = S.s },
        text = function() return count:get() > 0 and tostring(count:get()) or "" end, color = kit.ink("lo") } },
      function(next_row)
        count:set(math.floor(next_row.count))
        shown:set(next_row.shown == true)
      end
  end
  local pads = ui.Item { id = "overview-pads", anchors = { fill = true }, visible = row_shown,
    opacity = function() return pull:get() end, behavior = { opacity = fade },
    ui.Repeater { model = model.pads, delegate = pad_delegate } }

  -- --------------------------------------------------------- naming a desk --
  local name_input = ui.TextInput { id = "overview-name", anchors = { fill = true, left_margin = S.m, right_margin = S.m },
    vertical_alignment = "center", tab_navigation = false, font_family = theme.font, font_size = theme.size.normal,
    color = function() return C.onSurface end, placeholder = "Name this workspace",
    placeholder_color = function() return C.onSurfaceVariant end, caret_color = function() return C.primary end,
    on_accepted = function(text) model.named(text or "") end,
    on_escape = function() model.renaming:set(0) end }
  local naming = kit.card { id = "overview-naming", width = field_w, height = model.SEARCH_H, z = 6,
    x = function() return (select(1, model.size()) - field_w) / 2 end, y = row_y,
    visible = function() return model.renaming:get() ~= 0 end,
    name_input }
  morf.effect("eva.overview.naming", function()
    local id = model.renaming:get()
    if id ~= 0 then
      name_input.text = require("workspaces_model").name(id)
      name_input.focus = true
    elseif model.opened:get() then input.focus = true end
  end)

  local empty = L.label { id = "overview-empty", anchors = { center_in = true }, font_size = L.SIZE.value,
    color = kit.ink("lo"), visible = function() return model.opened:get() and model.cards:len() == 0 end,
    text = function() return model.query:get() ~= "" and "No window matches" or "Nothing on this workspace" end }

  -- ------------------------------------------------------- what is dragged --
  local ghost = ui.Item { id = "overview-ghost", z = 5,
    x = function() return model.drag.x end, y = function() return model.drag.y end,
    width = function() return model.drag.width end, height = function() return model.drag.height end,
    scale = .7, visible = function() return model.drag.address ~= "" end,
    card.picture { radius = radius(), address = function() return model.drag.address end,
      class = function() return "" end, title = function() return "" end } }

  -- ------------------------------------------------------------- the root --
  local dim = kit.surface { id = "overview-dim", anchors = { fill = true },
    color = function() return C.surface:alpha(.78) end,
    opacity = function() return pull:get() end, behavior = { opacity = fade } }
  local stepper = require("gesture_motion")
  local running
  local function rest_at(target, velocity)
    if running then running:stop() end
    local step = model.card_box(2).x - model.card_box(1).x
    running = morf.animation.play { stepper.step(track, "translate_x", target, velocity, step),
      on_finished = function() running = nil end }
    model.scrolled:set(target)
  end
  local function row_limit()
    local step = model.card_box(2).x - model.card_box(1).x
    return -math.max(0, model.cards:len() - 1) * step, step
  end
  local catcher = ui.MouseArea { id = "overview-catcher", anchors = { fill = true },
    on_clicked = function() model.close() end,
    on_wheel = function(_, _, _, _, _, step_y)
      if not cards() then model.scroll(step_y > 0 and 1 or -1) return end
      local limit, step = row_limit()
      rest_at(math.max(limit, math.min(0, model.scrolled:get() - (step_y > 0 and step or -step))))
    end }
  local clear = kit.action { id = "overview-clear", width = 160, height = S.TOUCH, cursor = "pointer", z = 2,
    accessible_name = "Clear all",
    anchors = { bottom = true, horizontal_center = true, bottom_margin = S.xxl },
    visible = function() return cards() and model.cards:len() > 0 end,
    on_clicked = function() model.clear_all() end,
    kit.surface { anchors = { fill = true }, radius = S.TOUCH / 2, color = function() return C.surfaceContainerHigh end },
    L.label { anchors = { center_in = true }, text = "Clear all", font_size = L.SIZE.body, color = kit.ink("hi") } }
  local action_menu = require("themes.layouts.action_menu")
  local menu = action_menu.build { id = "overview-menu", name = "Window actions",
    items = function()
      local a = model.menu_for:get()
      return a ~= "" and model.card_actions(a) or {}
    end,
    at = function(h)
      local slot = model.slots:get()[model.menu_for:get()] or { x = 0, y = 0, width = 0, height = 0 }
      local w, screen_h = model.size()
      local scroll = cards() and model.scrolled:get() or 0
      return math.max(S.s, math.min(w - action_menu.WIDTH - S.s, slot.x + scroll + slot.width / 2 - action_menu.WIDTH / 2)),
        math.max(S.s, math.min(screen_h - h - S.s, slot.y + slot.height / 2 - h / 2))
    end,
    close = function() model.menu_for:set("") end,
    opened = function() return model.menu_for:get() ~= "" end }

  local lingering = morf.signal("eva.overview.lingering", false)
  local leaving
  morf.effect("eva.overview.linger", function()
    local open = model.opened:get()
    if leaving then leaving:cancel() leaving = nil end
    if open then lingering:set(true) return end
    leaving = morf.time.timer(theme.bounce.spatial.duration, function() leaving = nil lingering:set(false) end, false)
  end)

  local strip_shown = ui.Item { id = "overview-strip-holder", anchors = { fill = true },
    visible = function() return not cards() end, strip }
  local root = ui.Item { id = "overview", anchors = { fill = true },
    accessible_role = "dialog", accessible_name = "Overview",
    visible = function() return model.opened:get() or lingering:get() end,
    dim, catcher, track, strip_shown, search, ui.Row(layouts), pads, naming, empty, ghost, clear, menu }

  -- Along the row of cards, under a finger; it rests on a card.
  local origin
  root.on_panned = function(phase, dx, dy, vx)
    if not cards() then return false end
    if phase == "begin" then
      if math.abs(dx) < math.abs(dy) then return false end
      if running then running:stop() running = nil end
      origin = track.translate_x or 0
      return true
    end
    local limit, step = row_limit()
    if phase == "update" then
      track.translate_x = math.max(limit, math.min(0, origin + dx))
    else
      local throw = origin + dx + (vx or 0) * .15
      rest_at(math.max(limit, math.min(0, math.floor(throw / step + .5) * step)), vx)
    end
  end

  return { node = root, shown = function(open)
    input.text = ""
    input.focus = open
    if open then
      track.translate_x = 0
      model.scrolled:set(0)
    end
  end }
end

return V
