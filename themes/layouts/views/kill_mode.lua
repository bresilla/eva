-- Kill mode (shell/kill_mode.lua): a sheet over the screen with a hole cut in
-- it, the hole a shape of the sheet's own field running from window to window.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local S, C = theme.space, theme.color
local V = {}

function V.build(model)
  local spatial, fade = theme.spring.spatial, theme.spring.effects
  local radius = L.control_round(2 * S.xl)
  local last = { x = 0, y = 0, width = 1, height = 1 }
  local function box()
    local r = model.rect()
    if r then last = r end
    return last
  end
  local marker = ui.Item { id = "kill-target",
    x = function() return box().x end, y = function() return box().y end,
    width = function() return box().width end, height = function() return box().height end,
    behavior = { x = spatial, y = spatial, width = spatial, height = spatial },
    kit.surface { anchors = { fill = true }, radius = radius, color = "transparent", border_width = 2,
      border_color = function() return C.error end,
      opacity = function() return model.target:get() ~= "" and 1 or 0 end, behavior = { opacity = fade } } }
  local sheet = ui.Sdf { id = "kill-sheet", anchors = { fill = true }, blend = 12,
    fill_color = function() return C.error:alpha(.28) end,
    ui.SdfShape { shape = "box", anchors = { fill = true } },
    ui.SdfShape { id = "kill-hole", shape = "box", radius = radius, operation = "smooth_subtract", track = marker,
      opacity = function() return model.target:get() ~= "" and 1 or 0 end, behavior = { opacity = fade } } }
  local hint = kit.card { id = "kill-hint", height = 44, width = 420,
    anchors = { top = true, horizontal_center = true, top_margin = S.xxl },
    kit.text { anchors = { center_in = true }, text = "Press a window to force quit it. Escape leaves.",
      font_size = L.SIZE.body, color = kit.ink("hi") } }
  local keys = ui.Item { id = "kill-keys", width = 1, height = 1, tab_navigation = false, on_key_pressed = model.key }
  local area = ui.MouseArea { id = "kill-area", anchors = { fill = true }, cursor = "crosshair",
    accepted_buttons = { "left", "right" },
    accessible_role = "dialog", accessible_name = "Kill mode",
    on_position_changed = function(x, y) model.aim(x, y) end,
    on_pressed = function(x, y) model.aim(x, y) end,
    on_clicked = function(x, y, _, _, button)
      if button == "right" then model.stop() else model.fire(x, y) end
    end }
  local root = ui.Item { id = "kill-mode", anchors = { fill = true },
    visible = function() return model.active:get() end,
    sheet, marker, area, hint, keys }
  return { node = root, shown = function(open) keys.focus = open end }
end

return V
