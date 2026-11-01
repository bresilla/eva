-- The desktop's widgets. Each is built once, the first time it is shown, and
-- kept: the board says where it goes, and its place, width and presence follow
-- on springs, as the quick settings' tiles do. While arranging, a widget carries
-- the same marks as a tile: hide at the top, size at the bottom.
--
-- A phone's and a tablet's home is the same layer with pages: a track of them
-- that slides under a finger, icons standing beside the widgets and arranged the
-- same way, and dots saying which page is on show.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local config = require("config")
local P = require("themes.layouts.page")
local widgets = require("themes.kit.widgets")
local C, S = theme.color, theme.space

local V = {}
local INSET = S.l
local ICON = S.xxl + S.xl
-- How near a screen's side a carried thing turns the page, and how long it waits.
local TURN_REACH, TURN_MS = S.xxl, 450

local function badge(spec) return require("themes").view("quick_tiles").badge(spec) end

--- An app or a folder on a page: its art and name. A press opens it, a hold or
--- a right press offers what can be done to it.
local function icon_face(row, ctx, model, armed, menu_for)
  local spent = row.kind == "app" and row.id:match("^app:(.*)$") or nil
  local art = ui.Item { id = "desktop-icon-art-" .. row.id, width = ICON, height = ICON, y = S.s,
    x = function() return (ctx.w() - ICON) / 2 end,
    opacity = function() return spent and require("screen_time_model").spent(spent) and 0.4 or 1 end,
    require("themes").view("launcher_grid").art(require("apps").icon, row, ICON) }
  local name = kit.text { id = "desktop-icon-name-" .. row.id, y = S.s + ICON + S.xs, x = S.xs, text = row.name, elide = "right",
    width = function() return ctx.w() - S.s end, horizontal_alignment = "center", font_size = theme.size.small,
    color = ctx.ink, visible = function() return config.get("desktop.home.labels") == true end }
  local held = false
  return ui.Item { width = ctx.w, height = ctx.h, art, name,
    ui.MouseArea { id = "desktop-icon-" .. row.id, anchors = { fill = true }, cursor = "pointer", accepted_buttons = { "left", "right" },
      accessible_role = "button", accessible_name = row.name, enabled = function() return not armed() end,
      on_clicked = function(_, _, _, _, button)
        if button == "right" then menu_for:set(row.id) else model.open(row.id) end
      end,
      on_long_pressed = function()
        require("haptics").fire("long")
        held = true
      end,
      on_released = function()
        if held then menu_for:set(row.id) end
        held = false
      end } }
end

-- A veil with the time cut out of it, so the picture itself is the digits.
local function stencil(model)
  return ui.Rect { id = "desktop-stencil", anchors = { fill = true }, radius = kit.round(P.RADIUS),
    visible = function() return config.get("desktop.chrome") == "stencil" end,
    color = morf.color("#000000"):alpha(0.6), mask_invert = true,
    mask = ui.Text { anchors = { center_in = true }, font_family = theme.font, font_size = 104, font_weight = 800,
      text = function() morf.time.minute_clock:get() return model.clock_text() end } }
end

-- The ground a widget stands on, through the picture where the surface has it.
local function ground(id, dark)
  return ui.Rect { id = "desktop-ground-" .. id, anchors = { fill = true }, radius = kit.round(P.RADIUS),
    visible = function()
      local chrome = config.get("desktop.chrome")
      return chrome ~= "none" and not (chrome == "stencil" and id == "clock")
    end,
    color = function()
      if config.get("desktop.chrome") == "solid" then return C.surfaceContainer end
      return dark() and morf.color("#ffffff"):alpha(0.28) or morf.color("#000000"):alpha(0.28)
    end,
    glass = { blur = 24, saturation = 1.4, rim = 0.5, frost = 1, refraction = 10 },
    backdrop_tint = function() return C.primary:alpha(0.1) end }
end

--- The widgets, filling their surface. `model` is shell/desktop_model.lua.
function V.build(model)
  local faces = require("themes").view("desktop_faces")
  local board = model.board
  local stamp = tostring({})
  local spots = morf.signal("eva.desktop.spots." .. stamp, {})
  local shown = morf.signal("eva.desktop.shown." .. stamp, {})
  local carried = morf.signal("eva.desktop.carried." .. stamp, "")
  local menu_for = morf.signal("eva.desktop.icon_menu." .. stamp, "")
  local TRAVEL = theme.spring.spatial
  local function editing() return board.editing:get() end
  local function page_width() morf.window.screens_revision() return ((morf.screens or {})[1] or {}).width or 1280 end
  local function screen_height() morf.window.screens_revision() return ((morf.screens or {})[1] or {}).height or 800 end

  -- A carried thing held against a side turns to the page that way, a new one
  -- past the last.
  local turning, turn_way
  local function stop_turning()
    if turning then turning:cancel() end
    turning, turn_way = nil, nil
  end
  local function turn_page(id, way)
    local to = model.current() + way
    if to < 1 then return end
    if to > model.page_count() and not model.add_page() then return end
    if model.to_page(id, to) then
      model.page:set(to)
      require("haptics").fire("commit")
    end
  end
  local function watch_side(id, x, w)
    if not model.home() then return end
    local middle = x + w / 2
    local way = middle > page_width() - TURN_REACH and 1 or middle < TURN_REACH and -1 or nil
    if way == turn_way then return end
    stop_turning()
    if way then
      turn_way = way
      turning = morf.time.timer(TURN_MS, function()
        turning, turn_way = nil, nil
        turn_page(id, way)
      end, false)
    end
  end

  local function tile(widget)
    local id, name, plain = widget.id, widget.name, widget.face ~= nil
    local at = { x = 0, y = 0, page = 1 }
    local function here() return shown:get()[id] ~= nil end
    local function small() local s = shown:get()[id] return s ~= nil and s.small == true end
    local function spot()
      local s = spots:get()[id]
      if s then at.x, at.y, at.width, at.page = s.x, s.y, s.width, s.page or 1 end
      return at
    end
    local function width() local w = model.size(id, small()) return spot().width or w end
    local function height() local _, h = model.size(id, small()) return h end
    local function armed() return editing() and here() end
    local function dark()
      local s = spot()
      if config.get("desktop.chrome") == "solid" then return false end
      return model.dark_ink(s.x, s.y, width(), height()) == true
    end
    local function ink()
      if config.get("desktop.chrome") == "solid" then return C.onSurface end
      return dark() and morf.color("#14141a") or morf.color("#f7f7fa")
    end
    local function soft() return ink():alpha(0.72) end

    local inset = plain and 0 or INSET
    local ctx = { small = small, ink = ink, soft = soft,
      w = function() return width() - 2 * inset end, h = function() return height() - 2 * inset end }
    -- A carried widget leans into the way it is going.
    local lean = morf.signal("eva.desktop.lean." .. id .. stamp, 0)
    local body = ui.Item { id = "desktop-widget-" .. id, anchors = { fill = true },
      scale = function()
        if carried:get() == id then return 1.04 end
        return here() and 1 or 0.9
      end,
      transform_matrix = function() return { 1, 0, lean:get(), 1 } end,
      behavior = { scale = theme.spring.fast },
      not plain and ground(id, dark) or ui.Item {},
      id == "clock" and stencil(model) or ui.Item {},
      ui.Item { x = inset, y = inset, width = ctx.w, height = ctx.h,
        visible = function() return not (id == "clock" and config.get("desktop.chrome") == "stencil") end,
        plain and widget.face(ctx, armed) or faces[id](ctx, model, here) },
    }
    local presence = ui.claims(body, {
      here = { when = here, motion = theme.spring.effects, set = { opacity = 1 } },
      gone = { set = { opacity = 0 } },
    })
    local marks = ui.Item { anchors = { fill = true }, z = 5, visible = armed,
      badge { id = "desktop-hide-" .. id, name = "Hide " .. name, icon = "remove", edge = "top", visible = armed,
        tone = function() return C.errorContainer end, ink = function() return C.onErrorContainer end,
        on_clicked = function() board.hide(id) end },
      plain and ui.Item {} or badge { id = "desktop-size-" .. id, name = "Change the size of " .. name, edge = "bottom", visible = armed,
        icon = function() return small() and "open_in_full" or "close_fullscreen" end,
        tone = function() return C.secondaryContainer end, ink = function() return C.onSecondaryContainer end,
        on_clicked = function() board.toggle_size(id) end },
    }
    local last, origin = { x = 0, y = 0 }, nil
    local holder, drag = widgets.sortable_grid {
      id = "desktop-tile-" .. id, carrier = true, accessible_name = "Move " .. name,
      mode = "reorder", extent = 1e6,
      x = function() return spot().x + (spot().page - 1) * page_width() end, y = function() return spot().y end,
      width = width, height = height,
      behavior = { x = TRAVEL, y = TRAVEL, width = TRAVEL, height = TRAVEL },
      visible = function() return here() or presence.here.presence:get() > 0.01 end,
      armed = armed, enabled = armed,
      focus_policy = function() return armed() and "tab" or "none" end,
      on_drag_started = function()
        local s = spot()
        origin = { x = s.x, y = s.y }
        last = { x = 0, y = 0 }
        carried:set(id)
      end,
      on_dropped = function()
        carried:set("")
        lean:set(0)
        stop_turning()
        if origin and model.free() then model.move_to(id, origin.x + last.x, origin.y + last.y) end
        origin = nil
      end,
      on_reorder = function(step)
        if model.free() then
          local s = spot()
          model.move_to(id, s.x + step * S.xxl, s.y)
          return
        end
        local zone = board.zone_of(id)
        for index, item in ipairs(board.shown(zone)) do
          if item.id == id then board.move(id, index + step, zone) return end
        end
      end,
    }
    ui.reparent(body, holder)
    ui.reparent(marks, holder)
    morf.effect("eva.desktop.carry." .. id .. stamp, function()
      if not drag.active or not origin then return end
      local moved = drag.delta_x - last.x
      last = { x = drag.delta_x, y = drag.delta_y }
      lean:set(math.max(-0.06, math.min(0.06, -moved / 400)))
      watch_side(id, origin.x + last.x, width())
      if not model.free() then model.reorder(id, origin.x + last.x, origin.y + last.y) end
    end, { owner = holder })
    return holder
  end

  -- The icons on the pages, rebuilt with the list of them.
  local icon_rows = morf.list_model({})
  local function icon_delegate(row)
    return tile { id = row.id, name = row.name, face = function(ctx, armed)
      return icon_face(row, ctx, model, armed, menu_for)
    end }
  end

  local wanted, layer = {}, { id = "desktop-track", anchors = { fill = true } }
  layer[#layer + 1] = ui.Repeater { id = "desktop-icons", model = icon_rows, delegate = icon_delegate }
  for _, widget in ipairs(model.CATALOGUE) do
    wanted[widget.id] = morf.signal("eva.desktop.wanted." .. widget.id .. stamp, false)
    layer[#layer + 1] = ui.Loader { anchors = { fill = true }, keep = true,
      z = function() return carried:get() == widget.id and 10 or 0 end,
      active = function() return wanted[widget.id]:get() end,
      source = function() return tile(widget) end }
  end

  -- What a press on the bare desktop offers, and the bar while arranging.
  local menu_at = morf.signal("eva.desktop.menu." .. stamp, false)
  local function open_settings(page)
    menu_at:set(false)
    require("utilities").request(page)
    require("sidebar").select("settings")
    require("sidebar").drawer.set(true)
  end
  local menu = kit.card { id = "desktop-menu", width = S.xxl * 7, height = 3 * P.BUTTON_H + 2 * S.s + 2 * S.s, z = 20,
    x = function() local m = menu_at:get() return m and m.x or 0 end,
    y = function() local m = menu_at:get() return m and m.y or 0 end,
    visible = function() return menu_at:get() ~= false end,
    ui.Column { x = S.s, y = S.s, width = S.xxl * 7 - 2 * S.s, gap = S.s,
      P.button { id = "desktop-menu-wallpaper", label = "Wallpaper", icon = "wallpaper", width = S.xxl * 7 - 2 * S.s,
        on_clicked = function() open_settings("theme/wallpaper") end },
      P.button { id = "desktop-menu-arrange", label = "Arrange", icon = "dashboard_customize", width = S.xxl * 7 - 2 * S.s,
        on_clicked = function() menu_at:set(false) model.set_editing(true) end },
      P.button { id = "desktop-menu-settings", label = "Widgets", icon = "widgets", width = S.xxl * 7 - 2 * S.s,
        on_clicked = function() open_settings("theme/desktop") end },
    } }

  local spare_rows = morf.list_model({})
  -- On a home the tray also adds apps and pages, and scrolls where it is too
  -- wide for the screen.
  local function home_only(node) node.visible = model.home return node end
  local function button(id, name, icon, on_clicked)
    return kit.action { id = id, accessible_name = name, width = P.BUTTON_H, height = P.BUTTON_H, cursor = "pointer",
      on_clicked = on_clicked, kit.icon(icon, 22, kit.ink("hi"), { anchors = { center_in = true } }) }
  end
  local spare = ui.Row { gap = S.s, align = "center",
    P.button { id = "desktop-done", label = "Done", icon = "check", tone = "primary", on_clicked = function() model.set_editing(false) end },
    P.button { id = "desktop-reset", label = "Reset", icon = "restart_alt", on_clicked = function() board.reset() end },
    home_only(button("desktop-add-apps", "Add apps", "apps", function() require("launcher").drawer.set(true) end)),
    home_only(button("desktop-add-page", "Add a page", "note_add", function()
      local page = model.add_page()
      if page then model.page:set(page) end
    end)),
    home_only(button("desktop-drop-page", "Remove this page", "delete", function() model.drop_page(model.current()) end)),
    home_only(button("desktop-wallpaper", "Wallpaper", "wallpaper", function() open_settings("theme/wallpaper") end)),
    ui.Repeater { as = "row", gap = S.s, model = spare_rows, delegate = function(row)
      return button("desktop-add-" .. row.id, "Add " .. row.name, row.icon, function() board.add(row.id) end)
    end } }
  local function tray_inner() return math.min(spare.layout_width or 0, page_width() - 2 * S.l - 2 * S.s) end
  local tray_flick = ui.Flickable { id = "desktop-tray-scroll", x = S.s, y = S.s, width = tray_inner, height = P.BUTTON_H, clip = true, spare }
  local tray = kit.card { id = "desktop-arrange", z = 20, width = function() return tray_inner() + 2 * S.s end,
    height = P.BUTTON_H + 2 * S.s, anchors = { horizontal_center = true },
    y = function() return screen_height() - S.xxl * 2 - P.BUTTON_H - 2 * S.s - (model.home() and model.foot() or 0) end,
    visible = editing, tray_flick,
    on_panned = require("themes.overscroll").new { flick = tray_flick, sideways = true,
      room = function() return (spare.layout_width or 0) - (tray_flick.layout_width or 0) end }.on_panned }

  -- What a page's dots say, and a press on one goes to.
  local dots = { id = "desktop-dots", gap = S.s, align = "center", anchors = { horizontal_center = true },
    y = function() return screen_height() - model.foot() + (model.DOTS - S.l) / 2 end,
    visible = function() return model.home() and model.page_count() > 1 end }
  for page = 1, model.MAX_PAGES do
    local function current() return model.current() == page end
    dots[#dots + 1] = kit.action { id = "desktop-dot-" .. page, accessible_name = "Page " .. page, width = S.l, height = S.l,
      cursor = "pointer", visible = function() return page <= model.page_count() end,
      on_clicked = function() model.page:set(page) end,
      ui.Rect { anchors = { center_in = true }, radius = S.xs,
        width = function() return current() and S.m or S.s end, height = function() return current() and S.m or S.s end,
        behavior = { width = theme.spring.fast, height = theme.spring.fast },
        color = function() return current() and C.primary or C.onSurface:alpha(0.45) end } }
  end

  local press_timer
  local after_hold = false
  local function stop_press() if press_timer then press_timer:cancel() press_timer = nil end end
  -- A hold on a home arranges it, unless its layout is locked; elsewhere it opens
  -- the menu.
  local function held(x, y)
    press_timer = nil
    after_hold = true
    if model.home() and config.get("desktop.home.locked") ~= true then
      require("haptics").fire("long")
      model.set_editing(true)
    else
      menu_at:set { x = x, y = y }
    end
  end
  local ground_press = ui.MouseArea { id = "desktop-ground", anchors = { fill = true }, z = -1, accepted_buttons = { "left", "right" },
    on_position_changed = function(x, y) require("wallpaper").pointer(x, y) end,
    on_pressed = function(x, y, _, _, button)
      if menu_at:get() then menu_at:set(false) return end
      if button == "right" then menu_at:set { x = x, y = y } return end
      stop_press()
      press_timer = morf.time.timer(500, function() held(x, y) end, false)
    end,
    on_released = stop_press,
    -- A tap on the bare page ends arranging; the lift of the hold that began it does not.
    on_clicked = function()
      if not after_hold and model.home() and editing() then model.set_editing(false) end
      after_hold = false
    end,
  }
  local drops = ui.DropArea { anchors = { fill = true }, z = -2, keys = { "files" },
    on_dropped = function(drop)
      local path = (drop.paths or {})[1]
      if path and path:lower():match("%.[%a]+$") then require("wallpaper_model").choose(path) end
    end }

  local function icon_menu_items()
    local id = menu_for:get()
    return id ~= "" and model.menu(id) or {}
  end
  local action_menu = require("themes.layouts.action_menu")
  local function icon_menu_at(h)
    local s = spots:get()[menu_for:get()]
    if not s then return S.s, S.s end
    local x = math.max(S.s, math.min(page_width() - action_menu.WIDTH - S.s, s.x))
    local below = s.y + model.ICON_H + S.xs
    return x, below + h < screen_height() - model.foot() and below or math.max(S.s, s.y - h - S.xs)
  end
  local icon_menu = action_menu.build { id = "desktop-icon-menu", name = "Application menu", items = icon_menu_items,
    at = icon_menu_at, close = function() menu_for:set("") end, opened = function() return menu_for:get() ~= "" end }

  local track = ui.Item(layer)
  local pager_spec = { id = "desktop." .. stamp, track = track, tab = model.page, count = 1,
    offset = function(page) return (page - 1) * page_width() end }
  local pager = require("pager_drag").new(pager_spec)
  local root = ui.Item { id = "desktop", anchors = { fill = true }, ground_press, drops, track, ui.Row(dots), tray, menu, icon_menu,
    on_panned = function(phase, ...)
      if phase == "begin" then
        if not model.home() or carried:get() ~= "" then return false end
        stop_press()
      end
      return pager.on_panned(phase, ...)
    end }
  morf.effect("eva.desktop.pages." .. stamp, function() pager_spec.count = model.page_count() end, { owner = root })
  morf.effect("eva.desktop.layout." .. stamp, function()
    require("lib.shell.launcher.rows").revision:get()
    local out, icons = {}, {}
    for _, item in ipairs(model.everything()) do
      out[item.id] = item
      if model.is_icon(item.id) then icons[#icons + 1] = model.icon_row(item.id) end
    end
    shown:set(out)
    spots:set(model.layout())
    icon_rows:replace(icons, "id")
    for id, signal in pairs(wanted) do
      if out[id] and not signal:get() then signal:set(true) end
    end
  end, { owner = root })
  morf.effect("eva.desktop.spare." .. stamp, function()
    local rows = {}
    for _, item in ipairs(board.spare()) do
      local widget = model.BY_ID[item.id]
      rows[#rows + 1] = { id = item.id, name = widget.name, icon = widget.icon }
    end
    spare_rows:replace(rows, "id")
  end, { owner = root })
  return root
end

return V
