-- The desktop's widgets. Each is built once, the first time it is shown, and
-- kept: the board says where it goes, and its place, width and presence follow
-- on springs, as the quick settings' tiles do. While arranging, a widget carries
-- the same marks as a tile: hide at the top, size at the bottom.
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

local function badge(spec) return require("themes").view("quick_tiles").badge(spec) end

-- The ground a widget stands on, through the picture where the surface has it.
local function ground(id, dark)
  return ui.Rect { id = "desktop-ground-" .. id, anchors = { fill = true }, radius = kit.round(P.RADIUS),
    visible = function() return config.get("desktop.chrome") ~= "none" end,
    color = function()
      if config.get("desktop.chrome") == "solid" then return C.surfaceContainer end
      return dark() and morf.color("#ffffff"):alpha(0.28) or morf.color("#000000"):alpha(0.28)
    end,
    glass = { blur = 24, saturation = 1.4, rim = 0.5, frost = 1 } }
end

--- The widgets, filling their surface. `model` is shell/desktop_model.lua.
function V.build(model)
  local faces = require("themes").view("desktop_faces")
  local board = model.board
  local stamp = tostring({})
  local spots = morf.signal("eva.desktop.spots." .. stamp, {})
  local shown = morf.signal("eva.desktop.shown." .. stamp, {})
  local carried = morf.signal("eva.desktop.carried." .. stamp, "")
  local TRAVEL = theme.spring.spatial
  local function editing() return board.editing:get() end

  local function tile(widget)
    local id, name = widget.id, widget.name
    local at = { x = 0, y = 0 }
    local function here() return shown:get()[id] ~= nil end
    local function small() local s = shown:get()[id] return s ~= nil and s.small == true end
    local function spot()
      local s = spots:get()[id]
      if s then at.x, at.y, at.width = s.x, s.y, s.width end
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

    local ctx = { small = small, ink = ink, soft = soft,
      w = function() return width() - 2 * INSET end, h = function() return height() - 2 * INSET end }
    local body = ui.Item { id = "desktop-widget-" .. id, anchors = { fill = true },
      scale = function()
        if carried:get() == id then return 1.04 end
        return here() and 1 or 0.9
      end,
      behavior = { scale = theme.spring.fast },
      ground(id, dark),
      ui.Item { x = INSET, y = INSET, width = ctx.w, height = ctx.h, faces[id](ctx, model, here) },
    }
    local presence = ui.claims(body, {
      here = { when = here, motion = theme.spring.effects, set = { opacity = 1 } },
      gone = { set = { opacity = 0 } },
    })
    local marks = ui.Item { anchors = { fill = true }, z = 5, visible = armed,
      badge { id = "desktop-hide-" .. id, name = "Hide " .. name, icon = "remove", edge = "top", visible = armed,
        tone = function() return C.errorContainer end, ink = function() return C.onErrorContainer end,
        on_clicked = function() board.hide(id) end },
      badge { id = "desktop-size-" .. id, name = "Change the size of " .. name, edge = "bottom", visible = armed,
        icon = function() return small() and "open_in_full" or "close_fullscreen" end,
        tone = function() return C.secondaryContainer end, ink = function() return C.onSecondaryContainer end,
        on_clicked = function() board.toggle_size(id) end },
    }
    local last, origin = { x = 0, y = 0 }, nil
    local holder, drag = widgets.sortable_grid {
      id = "desktop-tile-" .. id, carrier = true, accessible_name = "Move " .. name,
      mode = "reorder", extent = 1e6,
      x = function() return spot().x end, y = function() return spot().y end,
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
        if origin and model.free() then model.move_to(id, origin.x + last.x, origin.y + last.y) end
        origin = nil
      end,
      on_reorder = function(step)
        if model.free() then
          local s = spot()
          model.move_to(id, s.x + step * S.xxl, s.y)
          return
        end
        for index, item in ipairs(board.shown()) do
          if item.id == id then board.move(id, index + step) return end
        end
      end,
    }
    ui.reparent(body, holder)
    ui.reparent(marks, holder)
    morf.effect("eva.desktop.carry." .. id .. stamp, function()
      if not drag.active or not origin then return end
      last = { x = drag.delta_x, y = drag.delta_y }
      if not model.free() then model.reorder(id, origin.x + last.x, origin.y + last.y) end
    end, { owner = holder })
    return holder
  end

  local wanted, layer = {}, { anchors = { fill = true } }
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
  local spare = ui.Row { gap = S.s, align = "center",
    P.button { id = "desktop-done", label = "Done", icon = "check", tone = "primary", on_clicked = function() model.set_editing(false) end },
    P.button { id = "desktop-reset", label = "Reset", icon = "restart_alt", on_clicked = function() board.reset() end },
    ui.Repeater { as = "row", gap = S.s, model = spare_rows, delegate = function(row)
      return kit.action { id = "desktop-add-" .. row.id, accessible_name = "Add " .. row.name, width = P.BUTTON_H, height = P.BUTTON_H,
        cursor = "pointer", on_clicked = function() board.add(row.id) end,
        kit.icon(row.icon, 22, kit.ink("hi"), { anchors = { center_in = true } }) }
    end } }
  local tray = kit.card { id = "desktop-arrange", z = 20, width = function() return (spare.layout_width or 0) + 2 * S.s end,
    height = P.BUTTON_H + 2 * S.s, anchors = { bottom = true, bottom_margin = S.xxl * 2, horizontal_center = true },
    visible = editing, ui.Item { x = S.s, y = S.s, width = 1, height = 1, spare } }

  local press_timer
  local ground_press = ui.MouseArea { anchors = { fill = true }, z = -1,
    on_position_changed = function(x, y) require("wallpaper").origin = { x = x, y = y } end,
    on_pressed = function(x, y, _, _, button)
      if menu_at:get() then menu_at:set(false) return end
      if button == "right" then menu_at:set { x = x, y = y } return end
      if press_timer then press_timer:cancel() end
      press_timer = morf.time.timer(500, function() press_timer = nil menu_at:set { x = x, y = y } end, false)
    end,
    on_released = function() if press_timer then press_timer:cancel() press_timer = nil end end,
  }
  local drops = ui.DropArea { anchors = { fill = true }, z = -2, keys = { "files" },
    on_dropped = function(drop)
      local path = (drop.paths or {})[1]
      if path and path:lower():match("%.[%a]+$") then require("wallpaper_model").choose(path) end
    end }

  local root = ui.Item { id = "desktop", anchors = { fill = true }, ground_press, drops, ui.Item(layer), tray, menu }
  morf.effect("eva.desktop.layout." .. stamp, function()
    local out = {}
    for _, item in ipairs(board.shown()) do out[item.id] = item end
    shown:set(out)
    spots:set(model.layout())
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
