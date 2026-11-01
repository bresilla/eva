-- How the bar's modules are drawn, from the catalogue's data (shell/bar_modules.lua).
-- A part is `{ node, size, flex, hold, island, across, clip }`: `size()` is what it
-- wants along the bar, and the rest say how bar_layout.lua treats it.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local popup = require("themes.kit.popup")
local C = theme.color
local S = theme.space

local V = {}
local NOTCH_PX = 15
local TEXT_MAX = 220
local CELL = S.xl + S.xxs

local function get(v)
  if type(v) == "function" then return v() end
  return v
end

--- What the modules share: `spec` has `model`, `ITEM`, `ICONS_H`, `GLYPH`, `DESK`,
--- `small(id)` and `ink()`. Returns `{ part, dress, tip, open_more, open_menu }`.
function V.context(spec)
  local model, ITEM, ICONS_H, GLYPH = spec.model, spec.ITEM, spec.ICONS_H, spec.GLYPH
  local small, ink = spec.small, spec.ink
  local M = { model = model, ITEM = ITEM, ICONS_H = ICONS_H, GLYPH = GLYPH }

  --- A tooltip on `target`, under a bar along an edge and beside a side one.
  --- `vertical` is the strip it stands on, nil for either.
  function M.tip(target, text, vertical, when)
    popup.tooltip(target, { text = text, placement = vertical and "right" or "bottom",
      when = function()
        if not model.on() or (vertical ~= nil and model.vertical() ~= vertical) then return false end
        return when == nil or when()
      end }, 500)
  end

  local menus = {}
  -- `items` in a menu at `area`, replacing the one this `key` left.
  local function open_items(key, area, items)
    if menus[key] and menus[key].node then
      menus[key].close()
      ui.destroy(menus[key].node)
    end
    menus[key] = popup.make("menu", { id = "bar-menu-" .. key, items = items, width = 240, padding = S.xs })
    menus[key].open(area)
  end

  --- A right press: the module's own items, then the bar's.
  function M.open_menu(area, m)
    local items = {}
    for _, item in ipairs(m.menu and m.menu() or {}) do items[#items + 1] = item end
    items[#items + 1] = { label = "Arrange the bar", icon = "tune", on_clicked = model.open_bar_page }
    items[#items + 1] = { label = "Remove from the bar", icon = "remove", on_clicked = function() model.board.hide(m.id) end }
    open_items(m.id, area, items)
  end

  --- A right press on the bare bar.
  function M.open_bar_menu(area)
    open_items("bar", area, {
      { label = "Arrange the bar", icon = "tune", on_clicked = model.open_bar_page },
      { label = "Quick settings", icon = "tune", on_clicked = model.open_settings },
      { label = "Dashboard", icon = "dashboard", on_clicked = model.toggle_dashboard },
    })
  end

  --- What folded into a zone's overflow, each a press away.
  function M.open_more(area, ids)
    local items = {}
    for _, id in ipairs(ids) do
      for _, m in ipairs(model.modules) do
        if m.id == id then
          local text = m.text and m.text() or ""
          items[#items + 1] = { label = text ~= "" and (m.name .. ": " .. text) or m.name,
            icon = type(m.icon) == "function" and m.icon() or m.icon, on_clicked = m.press or function() end }
        end
      end
    end
    open_items("more", area, items)
  end

  --- The tray's items behind the arrow, and the way to arrange them.
  function M.open_tray(area)
    local items = {}
    for i = 1, model.tray.more:len() do
      local row = model.tray.more:get(i)
      items[#items + 1] = { label = row.title ~= "" and row.title or row.id, icon = "apps",
        on_clicked = function() model.tray.activate(row.address) end }
    end
    items[#items + 1] = { label = "Arrange the tray", icon = "tune", on_clicked = function() require("utilities").request("bar/tray") end }
    open_items("tray", area, items)
  end

  --- Which apps use what, then what stopped lately.
  function M.open_privacy(area)
    local privacy, items = model.privacy, {}
    for _, row in ipairs(privacy.rows()) do
      for _, user in ipairs(row.users) do
        items[#items + 1] = { label = row.name .. ": " .. user.app, icon = row.icon, on_clicked = function() end }
      end
    end
    for i, past in ipairs(privacy.history()) do
      if i <= 5 then
        items[#items + 1] = { label = ("%s %s"):format(past.app, morf.time.format("%H:%M", past.ended)),
          icon = "history", enabled = false, on_clicked = function() end }
      end
    end
    if #items == 0 then items[1] = { label = "Nothing is in use", icon = "check", on_clicked = function() end } end
    open_items("privacy", area, items)
  end

  --- `area` with its tooltip and its right press.
  function M.dress(area, m, vertical)
    if m.tooltip then M.tip(area, m.tooltip, vertical) end
    ui.reparent(ui.MouseArea { id = "bar-right-" .. m.id .. (vertical and "-v" or ""), anchors = { fill = true },
      accepted_buttons = { "right" }, on_pressed = function() M.open_menu(area, m) end }, area)
    return area
  end

  local function tone(m)
    return function()
      local name = m.tone and m.tone()
      if name == nil or name == false then return ink() end
      return kit.signal(name)()
    end
  end

  -- The module's press area round `content`, with hover, tooltip, right press
  -- and wheel.
  local function chip(m, vertical, content)
    local suffix = vertical and "-v" or ""
    local area
    area = kit.action { id = "bar-module-" .. m.id .. suffix, cursor = "pointer", anchors = { fill = true },
      accessible_name = function()
        local text = m.text and m.text() or ""
        return text ~= "" and (m.name .. " " .. text) or m.name
      end,
      on_clicked = function()
        if m.press then m.press() else M.open_menu(area, m) end
      end,
      on_long_pressed = function() M.open_menu(area, m) end,
      m.wheel and ui.MouseArea { anchors = { fill = true }, z = -1, accepted_buttons = {},
        on_wheel = function(_, _, _, pixels, _, steps)
          m.wheel((steps and steps ~= 0) and steps or (pixels or 0) / NOTCH_PX)
        end } or ui.Item {},
      content }
    kit.hover(area, function(hovered) return hovered and C.onSurface:alpha(0.07) or C.onSurface:alpha(0) end, S.s)
    M.dress(area, m, vertical)
    return area
  end

  -- A ring round an icon: `value()` of the way round.
  local function ring(value, color)
    local r = 10
    return ui.Path { anchors = { center_in = true }, width = 24, height = 24, view_box = { 0, 0, 24, 24 },
      d = ("M12 %d A%d %d 0 1 1 11.99 %d"):format(12 - r, r, r, 12 - r),
      fill_color = "transparent", stroke_color = color, stroke_width = 2, stroke_cap = "round",
      trim_end = function() return math.max(0.001, value() or 0) end, behavior = { trim_end = theme.spring.effects } }
  end

  local function readout(m, vertical)
    local color = tone(m)
    local function words() return m.text and m.text() or "" end
    local function label_on() return not small(m.id) and words() ~= "" end
    local icon = ui.Item { width = ICONS_H, height = ICONS_H,
      m.gauge and ui.Path { anchors = { center_in = true }, width = 24, height = 24, view_box = { 0, 0, 24, 24 },
        d = "M12 2 A10 10 0 1 1 11.99 2", fill_color = "transparent", stroke_width = 2,
        stroke_color = function() return C.onSurface:alpha(0.14) end } or ui.Item {},
      m.gauge and ring(m.gauge, color) or ui.Item {},
      kit.icon(m.icon, m.gauge and 14 or GLYPH, color, { anchors = { center_in = true },
        fill = function() return m.tone ~= nil and m.tone() ~= nil end }) }
    local font_size = vertical and theme.size.small - 3 or theme.size.small
    local measure = kit.text { text = words, font_size = font_size, font_weight = 600, opacity = 0 }
    local label = kit.text { text = words, visible = label_on, color = color, elide = "right",
      font_size = font_size, font_weight = 600, horizontal_alignment = vertical and "center" or nil,
      width = function() return vertical and ITEM or math.min(measure.layout_width or 0, m.width or TEXT_MAX) end }
    local content = (vertical and ui.Column or ui.Row) { anchors = { center_in = true }, gap = vertical and 0 or S.xxs,
      align = "center", icon, label }
    local holder = ui.Item { anchors = { fill = true }, content, ui.Item { width = 1, height = 1, clip = true, measure } }
    return { node = chip(m, vertical, holder), size = function()
      local along = vertical and (content.layout_height or 0) or (content.layout_width or 0)
      return along + (vertical and S.xxs or S.s)
    end }
  end

  -- The workspaces: a distance field whose occupied ones run together where
  -- they stand side by side, and the active one sliding over them.
  local function workspaces(m, vertical)
    local AT, MOST = vertical and "y" or "x", 10
    local function rows() return require("bar_modules").workspaces() end
    local function count() return #rows() end
    local field = { anchors = { fill = true }, blend = S.s, blend_profile = "circular",
      fill_color = function() return C.onSurface:alpha(0.12) end }
    local nodes = {}
    for i = 1, MOST do
      local inset = S.xxs
      field[#field + 1] = ui.SdfShape { id = "bar-workspace-occupied-" .. i, shape = "box",
        operation = i == 1 and "union" or "smooth_union", radius = kit.round((CELL - 2 * inset) / 2),
        [AT] = (i - 1) * CELL + inset, [vertical and "x" or "y"] = (ITEM - CELL) / 2 + inset,
        width = CELL - 2 * inset, height = CELL - 2 * inset,
        opacity = function()
          local row = rows()[i]
          return row and row.occupied and 1 or 0
        end, behavior = { opacity = theme.spring.effects } }
      nodes[i] = kit.action { id = "bar-workspace-" .. i .. (vertical and "-v" or ""), cursor = "pointer",
        accessible_name = "Workspace " .. i, [AT] = (i - 1) * CELL, [vertical and "x" or "y"] = (ITEM - CELL) / 2,
        width = CELL, height = CELL, visible = function() return i <= count() end,
        on_clicked = function()
          local row = rows()[i]
          if row then model.go_workspace(row.id) end
        end,
        kit.text { anchors = { center_in = true }, font_size = theme.size.small, font_weight = 600,
          text = function()
            local row = rows()[i]
            return row and ("%d"):format((row.id - 1) % 10 + 1) or ""
          end,
          color = function()
            local row = rows()[i]
            if row and row.active then return C.onPrimary end
            return row and row.occupied and C.onSurface or C.onSurfaceVariant
          end } }
    end
    local function index()
      for i, row in ipairs(rows()) do if row.active then return i end end
      return 1
    end
    local active = ui.Item { id = "bar-workspace-active" .. (vertical and "-v" or ""), width = CELL, height = CELL,
      [AT] = function() return (index() - 1) * CELL end, [vertical and "x" or "y"] = (ITEM - CELL) / 2,
      behavior = { [AT] = theme.spring.spatial }, stretch = { stiffness = 300, damping = 22, scale = 0.12 } }
    local mark = ui.Sdf { anchors = { fill = true }, fill_color = function() return C.primary end,
      ui.SdfShape { shape = "box", radius = kit.round(CELL / 2), track = active } }
    local holder = { id = "bar-module-workspaces" .. (vertical and "-v" or ""), anchors = { fill = true },
      ui.Sdf(field), active, mark }
    for _, node in ipairs(nodes) do holder[#holder + 1] = node end
    local area
    area = ui.MouseArea { anchors = { fill = true }, z = -1,
      on_wheel = function(_, _, _, pixels, _, steps) m.wheel((steps and steps ~= 0) and steps or (pixels or 0) / NOTCH_PX) end,
      accepted_buttons = { "right" }, on_pressed = function() M.open_menu(area, m) end }
    holder[#holder + 1] = area
    M.tip(area, m.tooltip, vertical)
    return { node = ui.Item(holder), across = ITEM, size = function() return count() * CELL end }
  end

  -- What is using the microphone, camera and screen: a mark for each, on a
  -- tinted pill, and a press names them.
  local function privacy(m, vertical)
    local kinds = require("privacy_model").KINDS
    local icons = require("privacy_model").ICONS
    local function using(kind) return model.privacy.in_use(kind) end
    local nodes = { anchors = { center_in = true }, gap = S.xxs, align = "center" }
    for _, kind in ipairs(kinds) do
      nodes[#nodes + 1] = kit.icon(icons[kind], 16, kit.signal("ok"), { id = "bar-privacy-" .. kind .. (vertical and "-v" or ""),
        visible = function() return using(kind) end, fill = true })
    end
    local row = (vertical and ui.Column or ui.Row)(nodes)
    local area
    area = kit.action { id = "bar-module-privacy" .. (vertical and "-v" or ""), cursor = "pointer", anchors = { fill = true },
      accessible_name = function() return "In use. " .. table.concat(model.privacy.summary(), ". ") end,
      on_clicked = function() M.open_privacy(area) end, on_long_pressed = function() M.open_privacy(area) end,
      kit.surface { anchors = { center_in = true }, radius = kit.round(S.m),
        width = function() return vertical and ICONS_H + S.xs or (row.layout_width or 0) + S.m end,
        height = function() return vertical and (row.layout_height or 0) + S.m or ICONS_H + S.xs end,
        color = function() return kit.signal("ok")():alpha(0.14) end },
      row }
    M.dress(area, m, vertical)
    model.open_privacy = function() M.open_privacy(area) end
    return { node = area, size = function()
      local along = (vertical and row.layout_height or row.layout_width) or 0
      return along > 0 and along + S.l or 0
    end }
  end

  -- A battery glyph and level for each Bluetooth and wireless device.
  local BATTERY_ICONS = { headset = "headset_mic", headphones = "headphones", ["audio-headset"] = "headset_mic",
    ["audio-headphones"] = "headphones", mouse = "mouse", ["input-mouse"] = "mouse", keyboard = "keyboard",
    ["input-keyboard"] = "keyboard", gaming_input = "sports_esports", ["input-gaming"] = "sports_esports",
    phone = "smartphone" }
  local function batteries(m, vertical)
    local rows = morf.list_model({})
    local row = ui.Repeater { as = vertical and "column" or "row", gap = S.xs, anchors = { center_in = true }, model = rows,
      delegate = function(entry)
        return ui.Row { id = "bar-device-" .. entry.name:gsub("%W", "-"), gap = S.xxs, align = "center",
          kit.icon(BATTERY_ICONS[entry.kind] or "bluetooth", 16, ink),
          kit.text { text = ("%d%%"):format(entry.level), font_size = theme.size.small, font_weight = 600,
            color = function()
              if entry.level <= 10 then return kit.signal("alert")() end
              return entry.level <= 20 and kit.signal("warn")() or ink()
            end } }
      end }
    morf.effect("eva.bar.devices" .. (vertical and "-v" or ""), function()
      if model.on() then rows:replace(require("bar_modules").batteries(), "name") end
    end)
    return { node = chip(m, vertical, row), size = function()
      return ((vertical and row.layout_height or row.layout_width) or 0) + S.s
    end }
  end

  local function battery(m, vertical)
    local content = ui.Row { anchors = { center_in = true }, gap = S.xs, align = "center",
      kit.battery { id = "bar-module-battery-glyph" .. (vertical and "-v" or ""), size = 14,
        status = function() return model.reading:get().battery end },
      kit.text { text = function() return model.reading:get().percentage end, font_size = theme.size.small, font_weight = 600,
        visible = function() return not vertical and not small(m.id) end } }
    return { node = chip(m, vertical, content), size = function() return (content.layout_width or 0) + S.s end }
  end

  -- A bar per CPU core, one path.
  local function cores(m, vertical)
    local W, GAP = S.xs - 1, 1
    local function values()
      if not model.on() then return {} end
      return require("lib.services.sysinfo").cpu().cores or {}
    end
    local function width() return #values() * (W + GAP) end
    local function d()
      local out = {}
      for i, core in ipairs(values()) do
        local h = math.max(2, (core.usage or 0) / 100 * ICONS_H)
        out[i] = ("M%g %gh%gv%gh-%gz"):format((i - 1) * (W + GAP), ICONS_H - h, W, h, W)
      end
      return #out > 0 and table.concat(out) or "M0 0"
    end
    local content = ui.Path { anchors = { center_in = true }, width = width, height = ICONS_H,
      view_box = function() return { 0, 0, math.max(1, width()), ICONS_H } end, d = d, fill_color = kit.ink("accent") }
    return { node = chip(m, vertical, content), size = function() return vertical and ICONS_H or width() + S.s end }
  end

  -- The hours and minutes as lit dots, one column per digit.
  local function binary(m, vertical)
    local DOT, GAP = S.xs, S.xxs
    local function d(lit)
      morf.time.minute_clock:get()
      local digits, out = morf.time.format("%H%M"), {}
      for column = 1, 4 do
        local value = tonumber(digits:sub(column, column)) or 0
        for bit = 0, 3 do
          if ((value >> bit) & 1 == 1) == lit then
            local x, y = (column - 1) * (DOT + GAP), (3 - bit) * (DOT + GAP)
            out[#out + 1] = ("M%d %dh%dv%dh-%dz"):format(x, y, DOT, DOT, DOT)
          end
        end
      end
      return #out > 0 and table.concat(out) or "M0 0"
    end
    local size = 4 * DOT + 3 * GAP
    local content = ui.Item { anchors = { center_in = true }, width = size, height = size,
      ui.Path { anchors = { fill = true }, view_box = { 0, 0, size, size }, d = function() return d(false) end,
        fill_color = function() return C.onSurface:alpha(0.16) end },
      ui.Path { anchors = { fill = true }, view_box = { 0, 0, size, size }, d = function() return d(true) end,
        fill_color = kit.ink("accent") } }
    return { node = chip(m, vertical, content), size = function() return size + S.s end }
  end

  -- What is playing: the art, the title, and the chip filling with its progress.
  local function media(m, vertical)
    local state = require("media_state")
    local W = 200
    local function on() return model.on() and state.something() end
    local fraction = state.fraction(on)
    local fill = ui.Item { id = "bar-media-progress" .. (vertical and "-v" or ""),
      x = 0, y = 0, height = ITEM, width = function() return (vertical and ITEM or W) * fraction() end,
      behavior = { width = theme.spring.effects } }
    local ground = ui.Sdf { anchors = { fill = true }, fill_color = function() return C.primary:alpha(0.2) end,
      ui.SdfShape { shape = "box", anchors = { fill = true, margins = S.xs }, radius = kit.round(S.m) },
      ui.SdfShape { shape = "box", track = fill, operation = "intersect" } }
    local art = ui.Image { width = GLYPH, height = GLYPH, fill_mode = "preserve_aspect_crop",
      source = function() return require("lib.util.remote").file(state.active().art_url) or "" end,
      visible = function() return tostring(state.active().art_url or "") ~= "" end,
      mask = ui.Sdf { anchors = { fill = true }, ui.SdfShape { shape = "circle", anchors = { fill = true } } } }
    local content = (vertical and ui.Column or ui.Row) { anchors = { left = true, left_margin = vertical and 0 or S.m,
        vertical_center = true }, gap = S.xs, align = "center",
      kit.icon(function() return state.playing() and "pause" or "play_arrow" end, GLYPH, ink, { fill = true }),
      art,
      kit.text { text = state.field("title"), width = vertical and 0 or W - 2 * S.l - 2 * GLYPH, elide = "right",
        visible = function() return not vertical and not small(m.id) end,
        font_size = theme.size.small, font_weight = 600 } }
    local holder = ui.Item { anchors = { fill = true }, fill, ground }
    local area = chip(m, vertical, content)
    return { node = ui.Item { anchors = { fill = true }, holder, area },
      size = function() return (vertical or small(m.id)) and ITEM or W end }
  end

  -- The spectrum of what is playing.
  local function visualiser(m, vertical)
    local BANDS, W = 14, 56
    local bars = require("media_state").small_spectrum("bar" .. (vertical and "-v" or ""), BANDS,
      function() return model.on() and model.board.zone_of(m.id) ~= nil end)
    local content = kit.spectrum { id = "bar-visualiser" .. (vertical and "-v" or ""), anchors = { center_in = true },
      width = vertical and ICONS_H or W, height = vertical and S.m or ICONS_H - S.xs, channel = bars, gap = 2 }
    return { node = chip(m, vertical, content), size = function() return vertical and ICONS_H or W + S.s end }
  end

  local function spacer(m, vertical)
    return { node = ui.Item { id = "bar-module-" .. m.id .. (vertical and "-v" or "") }, size = function() return S.xl end }
  end

  local function divider(m, vertical)
    local node = ui.Item { id = "bar-module-" .. m.id .. (vertical and "-v" or ""), anchors = { fill = true },
      kit.surface { anchors = { center_in = true }, radius = 1, color = function() return C.onSurface:alpha(0.2) end,
        width = vertical and S.l or 1, height = vertical and 1 or S.l } }
    return { node = node, size = function() return S.s end }
  end

  local function title(m, vertical)
    m.width = m.width or 260
    return readout(m, vertical)
  end

  local KINDS = { workspaces = workspaces, privacy = privacy, batteries = batteries, battery = battery, cores = cores,
    binary = binary, media = media, visualiser = visualiser, spacer = spacer, divider = divider, title = title }

  --- The part of module `m`.
  function M.part(m, vertical, length)
    return (KINDS[m.kind] or readout)(m, vertical, length)
  end

  return M
end

return V
