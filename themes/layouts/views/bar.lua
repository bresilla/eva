-- The bar, supplied with shared readings and actions: three zones of modules
-- along an edge, each module placed by bar_layout.lua and arranged on the board
-- in the Bar page. A desk has it framed, with the clock in the middle. A phone
-- has a status bar: the time at the left and the status at the right, unframed,
-- with a finger's height to press.
--
-- A module is built once, the first time it is on the board, and kept; its place
-- and size follow on springs, so rearranging moves what is there.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local responsive = require("responsive")
local layout = require("bar_layout")
local C = theme.color
local V = { horizontal = 40, vertical = 48 }
local S = theme.space

local function button(id, size, on_clicked, child, hint)
  local area
  area = kit.action {
    id = id, width = size, height = size, cursor = "pointer", accessible_name = hint,
    on_clicked = on_clicked,
    child,
  }
  return kit.hover(area, function(hovered)
    return hovered and C.onSurface:alpha(0.08) or C.onSurface:alpha(0)
  end, size / 2)
end

function V.build(model)
  local FORM = responsive.form()
  local PHONE, DESK = FORM == "phone", FORM == "desk"
  -- How tall a press is, and the band the icons sit in.
  local ITEM = DESK and 34 or responsive.target()
  local ICONS_H = S.xl
  local GLYPH = 20
  -- An icon's width, the overflow dot's, the percentage's and the battery's.
  local SLOT, DOT, PERCENT = S.xl, S.s, 40
  local BATTERY = 16
  local TECH = 22
  local PAD = responsive.corner()
  local stamp = model.stamp
  local function ink() return C.onSurface end
  local function reading() return model.reading:get() end
  local function lanes() return responsive.lanes(model.side() == "top" and V.horizontal or 0) end
  local function small(id) return model.board.small(id) end

  local modules = require("themes").view("bar_modules").context {
    model = model, ITEM = ITEM, ICONS_H = ICONS_H, GLYPH = GLYPH, DESK = DESK, small = small, ink = ink,
  }
  local dress = modules.dress

  -- The logo: the author's mark, in the theme's colour. A click opens the
  -- launcher.
  local mark = require("logo")
  local function logo(m, vertical)
    local area = button("bar-logo" .. (vertical and "-v" or ""), ITEM, model.toggle_launcher, ui.Item {
      anchors = { center_in = true }, width = 24, height = 24,
      ui.Path {
        x = 24 * mark.offset_x / 100, y = 0, width = 24 * mark.scale_x, height = 24,
        view_box = mark.view_box, d = mark.d,
        fill_color = kit.ink("accent"),
      },
    }, "Launcher")
    dress(area, m, vertical)
    return { node = area, size = function() return ITEM end }
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
    modules.tip(area, function() return client.title end)
    ui.reparent(ui.MouseArea { anchors = { fill = true }, accepted_buttons = { "right" },
      on_pressed = function() model.window_menu(client.address) end }, area)
    area.on_long_pressed = function() model.window_menu(client.address) end
    return kit.hover(area, function(hovered)
      if focused() then return C.primary:alpha(0.16) end
      return hovered and C.onSurface:alpha(0.07) or C.onSurface:alpha(0)
    end, 10)
  end
  -- The windows in a lane that takes what the zone leaves; more than fit
  -- scroll along it, a wheel notch a window at a time.
  local function windows(_, vertical, length)
    local list = ui.Repeater { as = vertical and "column" or "row", gap = 8, model = model.rows, delegate = window_delegate }
    local lane = require("themes.kit.scroll").make(vertical and "scroll_view" or "shelf", {
      id = "bar-windows" .. (vertical and "-v" or ""),
      width = vertical and ITEM or length, height = vertical and length or ITEM, clip = true,
      snap = "none", item_size = function() return (titles() and ITEM + 8 + TITLE_W or ITEM + 6) + 6 end, list })
    return { node = lane, flex = true,
      size = function() return (vertical and list.layout_height or list.layout_width) or 0 end }
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
  local function fixed(vertical)
    local r = reading()
    local size = vertical and ICONS_H or 2 * BATTERY + S.xs
    if r.network_icon ~= "" then size = size + SLOT end
    if r.mobile_icon ~= "" then size = size + SLOT + ((r.technology ~= "" and not vertical) and TECH or 0) end
    return size
  end
  -- The indicators the privacy module has not taken over.
  local status_keys = require("status_model").PRIVATE
  local function privacy_placed() return model.board.zone_of("privacy") ~= nil end
  local function indicators()
    local placed, out = privacy_placed(), {}
    for _, item in ipairs(reading().indicators) do
      if not (placed and status_keys[item.key]) then out[#out + 1] = item end
    end
    return out
  end
  -- The percentage's room: none on a side bar, without a battery, or by the
  -- setting, unless the battery is low.
  local function percent_room(vertical)
    local b = reading().battery
    if vertical or not b.present then return 0 end
    if require("config").get("bar.percent") == false and not b.low then return 0 end
    return PERCENT
  end
  local function status(m, vertical, length)
    local v = vertical and "-v" or ""
    local function plan()
      local r = reading()
      local sizes = { icon = SLOT, dot = DOT, fixed = fixed(vertical), percent = percent_room(vertical), level = r.battery.level }
      return require("status_model").arrange(indicators(), length() - S.l, sizes)
    end
    local nodes = { gap = 0, align = "center" }
    nodes[#nodes + 1] = slot("bar-dot" .. v, function() return plan().dot end, vertical, DOT,
      kit.surface { anchors = { center_in = true }, width = S.xs + S.xxs, height = S.xs + S.xxs, radius = 3, color = ink })
    for _, key in ipairs(model.keys) do
      local function shown()
        if status_keys[key] and privacy_placed() then return false end
        return reading().icons[key] ~= nil and not plan().hidden[key]
      end
      nodes[#nodes + 1] = slot("bar-" .. key .. v, shown, vertical, SLOT,
        kit.icon(function() return reading().icons[key] or "" end, GLYPH, ink, { anchors = { center_in = true }, fill = true }))
    end
    -- A phone's mobile network, with its generation and roaming mark, where
    -- it has one.
    local function tech_shown() return not vertical and reading().mobile_icon ~= "" and reading().technology ~= "" end
    local mobile_w = function() return SLOT + (tech_shown() and TECH or 0) end
    nodes[#nodes + 1] = ui.Item {
      id = "bar-mobile" .. v, height = ICONS_H,
      width = function() return reading().mobile_icon ~= "" and mobile_w() or 0 end,
      visible = function() return reading().mobile_icon ~= "" end,
      kit.icon(function() return reading().mobile_icon end, GLYPH, ink, { y = 2, x = 2, fill = true }),
      kit.text { x = SLOT, anchors = { vertical_center = true }, visible = tech_shown,
        font_size = theme.size.small - 2, font_weight = 700,
        text = function() return reading().technology .. (reading().roaming and " R" or "") end },
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
    local area
    area = kit.action {
      id = "bar-status" .. v, cursor = "pointer", accessible_name = m.tooltip,
      anchors = vertical and { bottom = true } or { right = true },
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
    dress(area, m, vertical)
    return { node = ui.Item { anchors = { fill = true }, area }, flex = true, hold = true,
      size = function() return fixed(vertical) + #indicators() * SLOT + S.l + percent_room(vertical) end }
  end

  -- ------------------------------------------------------------ tray --
  -- The system tray beside the status: the kit's tray item in the theme's
  -- skin, the program's own picture on it. A press activates it, a right
  -- press opens its menu.
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
    node.on_long_pressed = function() item.open_menu() end
    modules.tip(node, function() return row.title end)
    return node
  end
  local function tray(_, vertical, length)
    if not model.tray then return { node = ui.Item {}, size = function() return 0 end } end
    local suffix = vertical and "-v" or ""
    local step = TRAY + S.xs
    local list = ui.Repeater { as = vertical and "column" or "row", gap = S.xs, model = model.tray.bar,
      delegate = function(row) return tray_delegate(row, suffix) end }
    local function overflowing() return model.tray.more:len() > 0 end
    local more
    more = kit.action { id = "bar-tray-more" .. suffix, width = TRAY, height = TRAY, cursor = "pointer",
      accessible_name = "More tray items", visible = overflowing, x = function() return vertical and 0 or model.tray.bar:len() * step end,
      y = function() return vertical and model.tray.bar:len() * step or 0 end,
      on_clicked = function() modules.open_tray(more) end,
      kit.icon(vertical and "chevron_right" or "expand_more", 20, ink, { anchors = { center_in = true } }) }
    local function count() return model.tray.bar:len() + (overflowing() and 1 or 0) end
    -- What it would like: every item, and the arrow where some are tucked away.
    local function natural()
      if not model.tray_on() or model.tray.rows:len() == 0 then return 0 end
      return (model.tray.rows:len() + (overflowing() and 1 or 0)) * step - S.xs
    end
    local function shown() return count() * step - S.xs end
    morf.effect("eva.bar.tray.room" .. suffix, function()
      if not model.on() or model.vertical() ~= vertical then return end
      local given = length and length() or 0
      if given <= 0 or not model.tray_on() then return end
      model.tray.room:set(require("tray_model").room_for(given + S.xs, step, model.tray.rows:len()))
    end)
    local node = ui.Item { id = "bar-tray" .. suffix, visible = function() return natural() > 0 end,
      anchors = { center_in = true },
      width = function() return natural() > 0 and (vertical and TRAY or shown()) or 0.01 end,
      height = function() return natural() > 0 and (vertical and shown() or TRAY) or 0.01 end, list, more }
    return { node = node, size = natural, flex = true, hold = true }
  end

  -- ------------------------------------------------------------ time --
  -- The date and the time; a press opens the dashboard on a desk and the
  -- notifications on a sheet, and another shuts it. A vertical bar stacks them.
  local function clock(m, vertical)
    local v = vertical and "-v" or ""
    local function date_shown() return stamp:get().date ~= "" and not small("clock") end
    local content
    if vertical then
      content = ui.Column {
        anchors = { center_in = true }, gap = 0, align = "center",
        kit.text { text = function() return stamp:get().hour end, font_weight = 700, morph = true },
        kit.text { text = function() return stamp:get().minute end, font_weight = 700, morph = true },
        kit.text { text = function() return stamp:get().second end, font_size = theme.size.small - 3,
          color = kit.ink("lo"), visible = function() return require("config").get("bar.clock.seconds") == true end },
        kit.text { text = function() return stamp:get().meridiem end, font_size = theme.size.small - 3,
          color = kit.ink("lo"), visible = function() return stamp:get().meridiem ~= "" end },
        kit.text { text = function() return stamp:get().day end,
          font_size = theme.size.small - 3, color = kit.ink("lo") },
      }
    else
      content = ui.Row {
        anchors = { center_in = true }, gap = S.s, align = "center",
        kit.text { text = function() return stamp:get().date end, font_size = theme.size.small,
          color = kit.ink("lo"), visible = date_shown },
        kit.text { text = function() return stamp:get().time end, font_weight = 700, morph = true,
          font_size = DESK and theme.size.normal or GLYPH },
      }
    end
    local area
    area = kit.action {
      id = "bar-clock" .. v, cursor = "pointer", accessible_name = DESK and "Dashboard" or "Notifications",
      width = function() return vertical and ITEM + S.xs or (content.layout_width or 0) + 2 * S.s end,
      height = function() return vertical and (content.layout_height or 0) + S.s or ITEM end,
      anchors = { center_in = true },
      on_clicked = model.press_clock,
      wheel("workspace" .. v, model.wheel_workspace),
      content,
    }
    kit.hover(area, function(hovered)
      if DESK and model.dashboard_open() then return C.primary:alpha(0.16) end
      return hovered and C.onSurface:alpha(0.07) or C.onSurface:alpha(0)
    end, 10)
    dress(area, m, vertical)
    return { node = area, across = vertical and ITEM + S.xs or nil,
      size = function()
        if vertical then return (content.layout_height or 0) + S.s end
        return (content.layout_width or 0) + 2 * S.s
      end }
  end

  -- ---------------------------------------------------------- layout --
  local function strip_box()
    local w, h = model.screen()
    local i = model.insets()
    local side = model.side()
    if side == "top" then return 0, 0, w, i.top + theme.BORDER end
    if side == "bottom" then return 0, h - i.bottom - theme.BORDER, w, i.bottom + theme.BORDER end
    if side == "left" then return 0, 0, i.left + theme.LEFT, h end
    return w - i.right - theme.BORDER, 0, i.right + theme.BORDER, h
  end
  -- The whole screen, in the bar's own space.
  function modules.origin()
    local x, y = strip_box()
    local w, h = model.screen()
    return -x, -y, w, h
  end

  local pill = require("themes").view("bar_pill").build(modules)
  local OWN = { logo = logo, windows = windows, status = status, tray = tray, clock = clock,
    live = function() return pill.part() end }

  -- Every module along one axis: a slot each, placed by the flow.
  local function strip(vertical)
    local v = vertical and "-v" or ""
    local AT, ALONG, ACROSS = vertical and "y" or "x", vertical and "height" or "width", vertical and "width" or "height"
    local flow = morf.signal("eva.bar.flow" .. v, { cells = {}, more = {} })
    local built = morf.signal("eva.bar.built" .. v, 0)
    local parts, wanted, by_id = {}, {}, {}
    local layer = { anchors = { fill = true } }

    local function cell(id) return flow:get().cells[id] end
    local function module_slot(m)
      local kept = 0
      local function at()
        local c = cell(m.id)
        if c then kept = c.at end
        return kept
      end
      local function length()
        local c = cell(m.id)
        return c and c.size or 0
      end
      local part = (OWN[m.kind] or modules.part)(m, vertical, length)
      local function slot_length() return part.flex and math.max(1, length()) or length() end
      parts[m.id] = part
      built:set(built:get() + 1)
      local spec = { id = "bar-slot-" .. m.id .. v, clip = part.clip ~= false,
        anchors = vertical and { horizontal_center = true } or { vertical_center = true },
        [AT] = at, [ALONG] = slot_length, [ACROSS] = part.across or ITEM,
        visible = function() return part.flex or length() > 0.5 end,
        behavior = { [AT] = theme.spring.spatial, [ALONG] = theme.spring.spatial },
        part.node }
      return ui.Item(spec)
    end

    for _, m in ipairs(model.modules) do
      by_id[m.id] = m
      wanted[m.id] = morf.signal("eva.bar.wanted." .. m.id .. v, false)
      layer[#layer + 1] = ui.Loader { anchors = { fill = true }, keep = true,
        active = function() return wanted[m.id]:get() end,
        source = function() return module_slot(m) end }
    end

    -- A zone's overflow: the mark, and what folded into it.
    local function more(zone)
      local function info() return flow:get().more[zone] end
      local kept = 0
      local function at()
        local i = info()
        if i then kept = i.at end
        return kept
      end
      local area
      area = kit.action { id = "bar-more-" .. zone .. v, cursor = "pointer", accessible_name = "More",
        anchors = vertical and { horizontal_center = true } or { vertical_center = true },
        [AT] = at, width = vertical and ITEM or ICONS_H, height = vertical and ICONS_H or ITEM,
        visible = function() return info() ~= nil end,
        on_clicked = function()
          local i = info()
          if i then modules.open_more(area, i.ids) end
        end,
        kit.surface { anchors = { center_in = true }, width = S.s, height = S.s, radius = S.xs, color = ink } }
      return area
    end
    layer[#layer + 1] = more("start")
    layer[#layer + 1] = more("end")

    local root = ui.Item(layer)
    local function active(m)
      if m.active == nil then return true end
      local ok, on = pcall(m.active)
      return ok and on == true
    end
    morf.effect("eva.bar.wanted" .. v, function()
      if not model.on() or model.vertical() ~= vertical then return end
      for _, zone in ipairs(layout.ZONES) do
        for _, item in ipairs(model.board.shown(zone)) do
          if not wanted[item.id]:get() then wanted[item.id]:set(true) end
        end
      end
    end, { owner = root })
    morf.effect("eva.bar.flow" .. v, function()
      built:get()
      if not model.on() or model.vertical() ~= vertical then return end
      local zones = {}
      for _, zone in ipairs(layout.ZONES) do
        local items = {}
        for _, item in ipairs(model.board.shown(zone)) do
          local m, part = by_id[item.id], parts[item.id]
          items[#items + 1] = { id = item.id, tier = require("status_model").tier_of(m.id, m.tier),
            size = (part and active(m)) and part.size() or 0,
            flex = part and part.flex, hold = part and part.hold, island = part and part.island,
            extra = part and part.extra and part.extra() or nil }
        end
        zones[zone] = items
      end
      local w, h = model.screen()
      local spec = { zones = zones, gap = S.xs, dot = ICONS_H }
      if vertical then
        spec.from, spec.to, spec.middle = PAD, (h or 0) - PAD, (h or 0) / 2
      else
        local l = lanes()
        spec.from, spec.to, spec.middle, spec.gap_from, spec.gap_to = l.left, l.right, (w or 0) / 2, l.gap_from, l.gap_to
      end
      flow:set(layout.flow(spec))
    end, { owner = root })
    pill.follow(vertical, function() return cell("live") end)
    return root
  end

  local along = strip(false)
  local down = strip(true)
  local ground
  ground = ui.MouseArea { id = "bar-ground", anchors = { fill = true }, z = -1, accepted_buttons = { "left", "right" },
    on_pressed = function(_, _, _, _, button) if button == "right" then modules.open_bar_menu(ground) end end,
    on_long_pressed = function() modules.open_bar_menu(ground) end }
  return ui.Item {
    id = "bar",
    visible = function() return model.on() end,
    -- A pull off the bar brings out what hangs from its edge, under the finger.
    on_panned = function(phase, dx, dy, vx, vy, x, y)
      return require("phone_gestures").edge_pan(model.side(), phase, dx, dy, vx, vy, x, y)
    end,
    x = function() local x = strip_box() return x end,
    y = function() local _, y = strip_box() return y end,
    width = function() local _, _, w = strip_box() return w end,
    height = function() local _, _, _, h = strip_box() return h end,
    -- A side bar is ground a drag along it can start from, end to end.
    ui.MouseArea { anchors = { fill = true }, z = -1, visible = function() return model.vertical() end },
    -- A right press on the bare bar offers the bar's own settings.
    ground,
    ui.Item { visible = function() return not model.vertical() end, anchors = { fill = true }, along },
    ui.Item { visible = function() return model.vertical() end, anchors = { fill = true }, down },
    pill.node,
  }
end

return V
