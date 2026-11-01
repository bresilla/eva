-- The bar, supplied with shared readings and actions. A desk has it framed:
-- the logo and windows, the clock in the middle, the status at the right. A
-- phone and a tablet have a status bar: the time at the left and the status at
-- the right, unframed, with a finger's height to press.
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local responsive = require("responsive")
local C = theme.color
local V = { horizontal = 40, vertical = 48 }
local S = theme.space
local function button(id, size, on_clicked, child, hint)
  local area
  area = kit.action {
    id = id, width = size, height = size, cursor = "pointer",
    on_clicked = on_clicked,
    child,
  }
  return kit.hover(area, function(hovered)
    return hovered and C.onSurface:alpha(0.08) or C.onSurface:alpha(0)
  end, size / 2)
end

function V.build(model)
  local FORM = responsive.form()
  local PHONE, TABLET, DESK = FORM == "phone", FORM == "tablet", FORM == "desk"
  -- How tall a press is, and the band the icons sit in.
  local ITEM = DESK and 34 or responsive.target()
  local ICONS_H = S.xl
  local GLYPH = 20
  -- An icon's width, the overflow dot's, the percentage's and the battery's.
  local SLOT, DOT, PERCENT = S.xl, S.s, 40
  local BATTERY = 16
  local TECH = 22

  -- The logo: the author's mark, in the theme's colour. A click opens the
  -- launcher.
  local mark = require("logo")
  local function logo(suffix)
    -- A phone has no room for it, and the launcher has its own way in.
    if PHONE then return ui.Item { id = "bar-logo" .. suffix, width = 0, height = 0 } end
    return button("bar-logo" .. suffix, ITEM, model.toggle_launcher, ui.Item {
      anchors = { center_in = true }, width = 24, height = 24,
      ui.Path {
        x = 24 * mark.offset_x / 100, y = 0, width = 24 * mark.scale_x, height = 24,
        view_box = mark.view_box, d = mark.d,
        fill_color = kit.ink("accent"),
      },
    })
  end

  -- --------------------------------------------------------- windows --
  -- A button per window of the workspace on show, after Dash to Panel: the
  -- app's icon (and its title, when `bar.titles` is on and the bar lies
  -- along), a pill behind the focused one, a light behind the one under
  -- the pointer, and a mark on the bar's inner edge -- wide for the focused
  -- window, a dot for the rest. A click focuses it.
  local titles = model.titles
  local function icon_of(client)
    local hit = client.icon
    if hit and hit.name then
      return ui.Icon { width = 22, height = 22, name = hit.name, source_width = 44, source_height = 44 }
    end
    if hit and hit.path then
      return ui.Image { width = 22, height = 22, source = hit.path, fill_mode = "preserve_aspect_fit" }
    end
    return kit.icon("select_window", 22, function() return C.onSurfaceVariant end)
  end
  local TITLE_W = 140
  local function window_delegate(client)
    local function here() return true end
    local function focused() return client.focused end
    local function wide() return titles() and ITEM + 8 + TITLE_W or ITEM + 6 end
    local area
    area = kit.action {
      id = "bar-window-" .. tostring(client.address),
      cursor = "pointer",
      width = function() return here() and wide() or 0 end,
      height = function() return here() and ITEM or 0 end,
      visible = here,
      on_clicked = function() model.focus(client.address) end,
      ui.Row {
        x = 7, anchors = { vertical_center = true }, gap = 8, align = "center",
        icon_of(client),
        kit.text {
          visible = titles, width = TITLE_W - 4, elide = "right",
          font_size = theme.size.small, font_weight = 500,
          text = function() return client.title ~= "" and client.title or client.class end,
          color = function() return focused() and C.onSurface or C.onSurfaceVariant end,
        },
      },
      -- The mark on the bar's inner edge.
      kit.surface {
        height = 3, radius = 2,
        width = function() return focused() and 18 or 5 end,
        x = function() return (wide() - (focused() and 18 or 5)) / 2 end,
        y = function() return model.side() == "bottom" and 0 or ITEM - 3 end,
        color = function() return focused() and C.primary or C.onSurfaceVariant:alpha(0.7) end,
        behavior = { width = { duration = theme.duration.small }, x = { duration = theme.duration.small } },
      },
    }
    return kit.hover(area, function(hovered)
      if focused() then return C.primary:alpha(0.16) end
      return hovered and C.onSurface:alpha(0.07) or C.onSurface:alpha(0)
    end, 10)
  end
  -- The bar's row, as the screen's corners and any cutout leave it.
  local function lanes() return responsive.lanes(model.side() == "top" and V.horizontal or 0) end
  -- The windows in a lane that ends short of the clock; more than fit
  -- scroll along it, a wheel notch a window at a time.
  local CLOCK_W, CLOCK_H, PAD = 190, 64, responsive.corner()
  local LEFT_CLOCK_W = TABLET and 168 or 64
  local tail_row, tail_column
  local function windows(as)
    if PHONE then return ui.Item { width = 0, height = 0 } end
    local vertical = as == "column"
    local list = ui.Repeater { as = as, gap = 8, model = model.rows, delegate = window_delegate }
    local function room()
      local w, h = model.screen()
      w, h = w or 0, h or 0
      if vertical then return math.max(0, h / 2 - CLOCK_H / 2 - PAD - ITEM - 16) end
      local l = lanes()
      if TABLET then
        return math.max(0, l.right - l.left - ITEM - LEFT_CLOCK_W - (tail_row and tail_row.layout_width or 0) - 2 * S.xl)
      end
      return math.max(0, w / 2 - CLOCK_W / 2 - l.left - ITEM - 20)
    end
    local function along()
      local size = vertical and list.layout_height or list.layout_width
      return math.min(size or 0, room())
    end
    local lane = require("themes.kit.scroll").make(vertical and "scroll_view" or "shelf", { id = "bar-windows" .. (vertical and "-v" or ""),
      width = vertical and ITEM or along, height = vertical and along or ITEM, clip = true,
      snap = "none", item_size = function() return (titles() and ITEM + 8 + TITLE_W or ITEM + 6) + 6 end, list })
    return lane
  end

  -- ----------------------------------------------------------- status --
  -- The status says, and does nothing on its own: any of it opens the quick
  -- settings, at their top. What is not there takes no place; what comes
  -- and goes opens and shuts its gap along the row.
  local CLOSED = 0.01
  local function slot(id, shown, vertical, size, child)
    local along = vertical and "height" or "width"
    local spec = { id = id, clip = true, [vertical and "width" or "height"] = ICONS_H,
      opacity = function() return shown() and 1 or 0 end,
      behavior = { [along] = theme.spring.spatial, opacity = theme.spring.effects },
      child }
    spec[along] = function() return shown() and size or CLOSED end
    return ui.Item(spec)
  end
  local function ink() return C.onSurface end
  local function reading() return model.reading:get() end
  -- Under a desk's press area: the wheel's own way in, with its setting. A
  -- touchpad turns no notches, only pixels: this many are one.
  local NOTCH_PX = 15
  local function wheel(kind, turned)
    if not DESK then return ui.Item {} end
    return ui.MouseArea { id = "bar-wheel-" .. kind, anchors = { fill = true }, z = -1,
      visible = function() return model.wheel_on(kind:match("^%a+")) end,
      on_wheel = function(_, _, _, pixels, _, steps)
        turned((steps and steps ~= 0) and steps or (pixels or 0) / NOTCH_PX)
      end }
  end
  local function plan_room(vertical)
    if vertical then
      local _, h = model.screen()
      return math.max(0, (h or 0) / 2 - CLOCK_H / 2 - PAD - S.l)
    end
    local l = lanes()
    if l.gap_to then return l.right - l.gap_to - S.l end
    local w = model.screen()
    if DESK then return math.max(0, l.right - (w or 0) / 2 - CLOCK_W / 2 - S.l) end
    return math.max(0, l.right - l.left - LEFT_CLOCK_W - (TABLET and ITEM or 0) - S.m - S.l)
  end
  local function fixed(vertical)
    local r = reading()
    local size = vertical and ICONS_H or 2 * BATTERY + S.xs
    if r.network_icon ~= "" then size = size + SLOT end
    if r.mobile_icon ~= "" then size = size + SLOT + ((r.technology ~= "" and not vertical) and TECH or 0) end
    return size
  end
  local function tail(vertical)
    local v = vertical and "-v" or ""
    local function plan()
      return model.arrange(plan_room(vertical), { icon = SLOT, dot = DOT, fixed = fixed(vertical),
        percent = vertical and 0 or PERCENT })
    end
    local nodes = { gap = 0, align = "center" }
    nodes[#nodes + 1] = slot("bar-dot" .. v, function() return plan().dot end, vertical, DOT,
      kit.surface { anchors = { center_in = true }, width = S.xs + S.xxs, height = S.xs + S.xxs, radius = 3, color = ink })
    for _, key in ipairs(model.keys) do
      local function shown() return reading().icons[key] ~= nil and not plan().hidden[key] end
      nodes[#nodes + 1] = slot("bar-" .. key .. v, shown, vertical, SLOT,
        kit.icon(function() return reading().icons[key] or "" end, GLYPH, ink, { anchors = { center_in = true }, fill = true }))
    end
    -- A phone's mobile network, with its generation, where it has one.
    local function tech_shown() return not vertical and reading().mobile_icon ~= "" and reading().technology ~= "" end
    local mobile_w = function() return SLOT + (tech_shown() and TECH or 0) end
    nodes[#nodes + 1] = ui.Item {
      id = "bar-mobile" .. v, height = ICONS_H,
      width = function() return reading().mobile_icon ~= "" and mobile_w() or 0 end,
      visible = function() return reading().mobile_icon ~= "" end,
      kit.icon(function() return reading().mobile_icon end, GLYPH, ink, { y = 2, x = 2, fill = true }),
      kit.text { x = SLOT, anchors = { vertical_center = true }, visible = tech_shown,
        font_size = theme.size.small - 2, font_weight = 700,
        text = function() return reading().technology end },
    }
    nodes[#nodes + 1] = ui.Item {
      id = "bar-network" .. v, width = SLOT, height = ICONS_H,
      visible = function() return reading().network_icon ~= "" end,
      kit.icon(function() return reading().network_icon end, GLYPH, ink, { anchors = { center_in = true }, fill = true }),
    }
    local size = vertical and 14 or BATTERY
    nodes[#nodes + 1] = ui.Item {
      id = "bar-battery-slot" .. v, width = 2 * size + S.xs, height = ICONS_H,
      visible = function() return reading().battery.present end,
      kit.battery { id = "bar-battery" .. v, anchors = { center_in = true }, size = size,
        status = function() return reading().battery end },
    }
    if not vertical then
      nodes[#nodes + 1] = slot("bar-percent", function() return plan().percent and reading().battery.present end,
        false, PERCENT, kit.text { x = S.xxs, anchors = { vertical_center = true },
          font_size = theme.size.small, font_weight = 600,
          text = function() return reading().percentage end })
    end
    -- One segment, one press: all of it opens the quick settings.
    local row = (vertical and ui.Column or ui.Row)(nodes)
    local function label()
      local b = reading().battery
      return b.present and ("Quick settings. Battery " .. require("battery_status_model").describe(b)) or "Quick settings"
    end
    local area
    area = kit.action {
      id = "bar-status" .. v, cursor = "pointer", accessible_name = label,
      width = function() return vertical and ITEM or (row.layout_width or 160) + S.l end,
      height = function() return vertical and (row.layout_height or 160) + S.l or ITEM end,
      on_clicked = model.open_settings,
      wheel("volume" .. v, model.wheel_volume),
      ui.Item { anchors = { center_in = true },
        width = function() return row.layout_width or 0 end,
        height = function() return row.layout_height or 0 end,
        row },
    }
    if DESK then
      kit.hover(area, function(hovered)
        if model.settings_open() then return C.primary:alpha(0.16) end
        return hovered and C.onSurface:alpha(0.07) or C.onSurface:alpha(0)
      end, 10)
    end
    return area, row
  end

  -- ------------------------------------------------------------ tray --
  -- The system tray beside the status: the kit's tray item in the theme's
  -- skin, the program's own picture on it. A press activates it, a right
  -- press opens its menu. It stands down where it would run into the clock.
  local TRAY = 28
  local function tray_picture(row)
    local spec = { anchors = { center_in = true }, width = 20, height = 20 }
    if row.pixmap then spec.source = row.pixmap spec.fill_mode = "preserve_aspect_fit" return ui.Image(spec) end
    if row.file ~= "" then spec.source = row.file spec.fill_mode = "preserve_aspect_fit" return ui.Image(spec) end
    if row.icon ~= "" then spec.name, spec.source_width, spec.source_height = row.icon, 40, 40 return ui.Icon(spec) end
    return kit.icon("apps", 20, ink, { anchors = { center_in = true } })
  end
  local function tray_delegate(row, suffix)
    local node, item = require("lib.kit.composites.tray_item") {
      id = "bar-tray-item" .. suffix .. "-" .. tostring(row.address), address = row.address, size = TRAY, icon = " ",
      title = row.title, on_activated = function() model.tray.activate(row.address) end }
    ui.reparent(tray_picture(row), node)
    -- The kit's press takes the left button alone: the right one comes here.
    ui.reparent(ui.MouseArea { anchors = { fill = true }, accepted_buttons = { "right" },
      on_pressed = function() item.open_menu() end }, node)
    return node
  end
  local function tray(vertical)
    if not model.tray then return ui.Item {}, function() return 0 end end
    local suffix = vertical and "-v" or ""
    local list = ui.Repeater { as = vertical and "column" or "row", gap = S.xs, model = model.tray.rows,
      delegate = function(row) return tray_delegate(row, suffix) end }
    local function size()
      if not model.tray_on() or model.tray.rows:len() == 0 then return 0 end
      return (vertical and list.layout_height or list.layout_width) or 0
    end
    local function fits()
      if size() == 0 then return false end
      local status = (vertical and tail_column or tail_row)
      local used = (status and status[vertical and "layout_height" or "layout_width"] or 0) + S.l + S.xs + size()
      if vertical then
        local _, h = model.screen()
        return used <= (h or 0) / 2 - CLOCK_H / 2 - PAD
      end
      local w = model.screen()
      return used <= lanes().right - (w or 0) / 2 - CLOCK_W / 2
    end
    local node = ui.Item { id = "bar-tray" .. (vertical and "-v" or ""), visible = fits,
      width = function() return fits() and (list.layout_width or 0) or 0.01 end,
      height = function() return fits() and (list.layout_height or 0) or 0.01 end, list }
    return node, function() return fits() and size() + S.xs or 0 end
  end

  -- ------------------------------------------------------------ time --
  -- The date and the time, in the middle; a click opens the dashboard, and
  -- another shuts it.
  local stamp = model.stamp
  -- The time at the left, a tablet's with its date; a press pulls down the
  -- notifications.
  local function status_clock()
    return kit.action { id = "bar-clock", cursor = "pointer", accessible_name = "Notifications",
      width = LEFT_CLOCK_W, height = ITEM, on_clicked = model.open_notifications,
      ui.Row { anchors = { vertical_center = true }, gap = S.s, align = "center",
        kit.text { text = function() return stamp:get()[1] end, font_size = GLYPH, font_weight = 700, morph = true },
        TABLET and kit.text { text = function() return stamp:get()[2] end, font_size = theme.size.small,
          color = kit.ink("lo") } or nil,
      } }
  end
  local function clock(vertical)
    local area
    area = kit.action {
      id = "bar-clock" .. (vertical and "-v" or ""), cursor = "pointer",
      width = vertical and ITEM + 4 or 190, height = vertical and 64 or ITEM,
      on_clicked = model.toggle_dashboard,
      wheel("workspace" .. (vertical and "-v" or ""), model.wheel_workspace),
      vertical and ui.Column {
        anchors = { center_in = true }, gap = 0, align = "center",
        kit.text { text = function() return (stamp:get()[1]:sub(1, 2)) end, font_weight = 700, morph = true },
        kit.text { text = function() return (stamp:get()[1]:sub(4, 5)) end, font_weight = 700, morph = true },
        kit.text { text = function() return stamp:get()[3] end,
          font_size = theme.size.small - 3, color = kit.ink("lo") },
      } or ui.Row {
        anchors = { center_in = true }, gap = 8, align = "center",
        kit.text { text = function() return stamp:get()[2] end, font_size = theme.size.small,
          color = kit.ink("lo") },
        kit.text { text = function() return stamp:get()[1] end, font_weight = 700, morph = true },
      },
    }
    return kit.hover(area, function(hovered)
      if model.dashboard_open() then return C.primary:alpha(0.16) end
      return hovered and C.onSurface:alpha(0.07) or C.onSurface:alpha(0)
    end, 10)
  end

  -- ---------------------------------------------------------- layout --
  local function strip()
    local w, h = model.screen()
    local i = model.insets()
    local side = model.side()
    if side == "top" then return 0, 0, w, i.top + theme.BORDER end
    if side == "bottom" then return 0, h - i.bottom - theme.BORDER, w, i.bottom + theme.BORDER end
    if side == "left" then return 0, 0, i.left + theme.LEFT, h end
    return w - i.right - theme.BORDER, 0, i.right + theme.BORDER, h
  end
  local tail_h, row_h = tail(false)
  tail_row = row_h
  local tail_v, row_v = tail(true)
  tail_column = row_v
  local tray_h, tray_w = tray(false)
  local tray_v, tray_tall = tray(true)
  local head_h = PHONE and ui.Row { gap = 8, align = "center", status_clock() }
    or TABLET and ui.Row { gap = 8, align = "center", logo(""), status_clock(), windows("row") }
    or ui.Row { gap = 8, align = "center", logo(""), windows("row") }
  local head_v = ui.Column { gap = 8, align = "center", logo("-v"), windows("column") }
  return ui.Item {
    id = "bar",
    visible = function() return model.on() end,
    x = function() local x = strip() return x end,
    y = function() local _, y = strip() return y end,
    width = function() local _, _, w = strip() return w end,
    height = function() local _, _, _, h = strip() return h end,
    -- A side bar is ground a drag along it can start from, end to end.
    ui.MouseArea { anchors = { fill = true }, z = -1, visible = function() return model.vertical() end },
    ui.Item {
      visible = function() return not model.vertical() end,
      anchors = { fill = true },
      ui.Item { x = function() return lanes().left end, width = 1, anchors = { vertical_center = true }, height = ITEM, head_h },
      DESK and ui.Item { anchors = { center_in = true }, width = 190, height = ITEM, clock(false) } or ui.Item {},
      ui.Item {
        x = function() return lanes().right - ((row_h.layout_width or 160) + S.l) end,
        anchors = { vertical_center = true }, height = ITEM,
        width = function() return (row_h.layout_width or 160) + S.l end,
        tail_h,
      },
      ui.Item {
        x = function() return lanes().right - ((row_h.layout_width or 160) + S.l) - tray_w() end,
        anchors = { vertical_center = true }, height = TRAY, width = function() return math.max(1, tray_w()) end,
        tray_h,
      },
    },
    ui.Item {
      visible = function() return model.vertical() end,
      anchors = { fill = true },
      ui.Item { y = PAD, height = 1, anchors = { horizontal_center = true }, width = ITEM, head_v },
      ui.Item { anchors = { center_in = true }, width = ITEM + 4, height = 64, clock(true) },
      ui.Item {
        anchors = { bottom = true, bottom_margin = PAD, horizontal_center = true }, width = ITEM,
        height = function() return (row_v.layout_height or 160) + S.l end,
        tail_v,
      },
      ui.Item {
        anchors = { horizontal_center = true }, width = TRAY,
        y = function()
          local _, _, _, h = strip()
          return h - PAD - ((row_v.layout_height or 160) + S.l) - tray_tall()
        end,
        height = function() return math.max(1, tray_tall()) end,
        tray_v,
      },
    },
  }
end

return V
