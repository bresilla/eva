-- What lies over a window in a mode of its own (shell/window_modes.lua): the
-- handle on a split's divider, and the surface a picture in picture is moved,
-- resized and thrown away with.
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local S, C = theme.space, theme.color
local V = {}

local GRIP = S.xl
local THROW = 900

function V.build(model)
  local fade = theme.spring.effects

  -- ----------------------------------------------------------- the divider --
  local function divider() return model.divider() end
  local drag_from
  local function touch_only() return require("responsive").sheets() end
  local grip_shape = ui.Item { id = "split-grip-shape", anchors = { center_in = true },
    width = function() local d = divider() return d and d.vertical and S.xs or S.xxl end,
    height = function() local d = divider() return d and d.vertical and S.xxl or S.xs end,
    kit.surface { anchors = { fill = true }, radius = S.xxs, color = function() return C.onSurface end } }
  local grip = ui.MouseArea { id = "split-divider", cursor = "ew_resize",
    accessible_role = "slider", accessible_name = "Split divider",
    x = function() local d = divider() if not d then return 0 end return d.vertical and d.x - GRIP / 2 or d.x end,
    y = function() local d = divider() if not d then return 0 end return d.vertical and d.y or d.y - GRIP / 2 end,
    width = function() local d = divider() if not d then return 0 end return d.vertical and GRIP or d.length end,
    height = function() local d = divider() if not d then return 0 end return d.vertical and d.length or GRIP end,
    visible = function() return touch_only() and divider() ~= nil end,
    on_pressed = function(x, y) drag_from = { x = x, y = y } end,
    on_dragged = function(x, y)
      if not drag_from then return end
      grip_shape.translate_x, grip_shape.translate_y = x - drag_from.x, y - drag_from.y
    end,
    on_released = function(x, y)
      local d = divider()
      grip_shape.translate_x, grip_shape.translate_y = 0, 0
      if not drag_from or not d then return end
      local moved = d.vertical and x - drag_from.x or y - drag_from.y
      drag_from = nil
      if math.abs(moved) > S.s then
        local total = math.max(1, d.total)
        model.settle_divider(d.first / total + moved / total, d.first / total)
      end
    end,
    grip_shape }

  -- --------------------------------------------------- picture in picture --
  local function pip() return model.pip_rect() end
  local function play_icon() return "play_pause" end
  local grab
  local panel = ui.Item { id = "pip-controls", anchors = { center_in = true }, width = 3 * S.TARGET, height = S.TARGET, z = 2,
    visible = function() return model.controls:get() end,
    opacity = function() return model.controls:get() and 1 or 0 end, behavior = { opacity = fade },
    ui.Row { anchors = { fill = true }, gap = 0,
      kit.action { id = "pip-play", width = S.TARGET, height = S.TARGET, accessible_name = "Play or pause", cursor = "pointer",
        on_clicked = function() model.play_pause() end,
        kit.icon(play_icon, 22, kit.ink("hi"), { anchors = { center_in = true } }) },
      kit.action { id = "pip-expand", width = S.TARGET, height = S.TARGET, accessible_name = "Back to the window", cursor = "pointer",
        on_clicked = function() model.toggle_pip() end,
        kit.icon("open_in_full", 22, kit.ink("hi"), { anchors = { center_in = true } }) },
      kit.action { id = "pip-close", width = S.TARGET, height = S.TARGET, accessible_name = "Close", cursor = "pointer",
        on_clicked = function() model.close_pip() end,
        kit.icon("close", 22, kit.ink("hi"), { anchors = { center_in = true } }) } } }
  local shade = kit.surface { anchors = { fill = true }, z = 1, radius = S.s, color = function() return C.surface:alpha(.55) end,
    visible = function() return model.controls:get() end }
  local tab = kit.action { id = "pip-tab", anchors = { fill = true }, z = 3, accessible_name = "Bring it back", cursor = "pointer",
    visible = function() return model.stashed:get() ~= "" end,
    on_clicked = function() model.unstash() end,
    kit.icon(function() return model.stashed:get() == "left" and "chevron_right" or "chevron_left" end, 20, kit.ink("hi"),
      { anchors = { center_in = true } }) }
  local area = ui.MouseArea { id = "pip-area", anchors = { fill = true }, cursor = "move",
    accessible_role = "button", accessible_name = "Picture in picture",
    on_pressed = function(x, y)
      local r = pip()
      if r then grab = { x = x - r.x, y = y - r.y, sx = x, sy = y, moved = false } end
    end,
    on_dragged = function(x, y)
      if not grab then return end
      grab.moved = true
      model.move_to(x - grab.x, y - grab.y)
    end,
    on_released = function(x, y)
      if grab and grab.moved then model.drop_at(x - grab.x, y - grab.y) end
      grab = nil
    end,
    on_clicked = function() model.toggle_controls() end,
    on_double_clicked = function() model.resize_pip() end,
    on_pinched = function(scale, phase)
      if phase == "end" and (scale > 1.1) ~= model.pip_large:get() and (scale > 1.1 or scale < .9) then
        model.resize_pip()
      end
    end,
    on_swiped = function(direction, _, vy)
      if direction == "down" and (vy or 0) >= THROW then model.close_pip() end
    end }
  local cover = ui.Item { id = "pip",
    x = function() local r = pip() return r and r.x or 0 end, y = function() local r = pip() return r and r.y or 0 end,
    width = function() local r = pip() return r and r.width or 1 end,
    height = function() local r = pip() return r and r.height or 1 end,
    visible = function() return pip() ~= nil end,
    area, shade, panel, tab }

  local root = ui.Item { id = "window-modes", anchors = { fill = true }, grip, cover }
  return { node = root }
end

return V
