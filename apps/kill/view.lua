-- eva-kill's overlay: one field dims the screen round a box that rides a spring
-- onto the window under the pointer, its edge the rim, the window's title on a
-- chip that travels with it. Pressing ends the window; Escape ends nothing.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local frame = require("common.frame")
local L = require("themes.layouts.parts")
local responsive = require("responsive")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

M.DIM = 0.62
M.RIM = S.xs
M.CHIP_MAX = S.TARGET * 10
M.OVER = S.xl

local function hover() return model.hover:get() end
local function leaving() return model.leaving:get() end
local function screen_w() return ((morf.screens or {})[1] or {}).width or 1920 end

-- Where the box stands: on the window, or shut at the middle of the screen.
local function rect()
  local at = hover()
  if at and not leaving() then return at end
  local screen = (morf.screens or {})[1] or {}
  if at then return { x = at.x + at.w / 2, y = at.y + at.h / 2, w = 0, h = 0 } end
  return { x = (screen.width or 1920) / 2, y = (screen.height or 1080) / 2, w = 0, h = 0 }
end

local function words()
  if model.armed:get() then return "Tap again to end it" end
  local at = hover()
  if not at then return "" end
  if at.title and at.title ~= "" then return at.title end
  return at.app or "Window"
end

local function field(box)
  return ui.Sdf {
    id = "kill-field", anchors = { fill = true, margins = -M.OVER },
    fill_color = function() return C.scrim:alpha(M.DIM) end,
    stroke_color = function() return kit.signal("alert")() end, stroke_width = M.RIM,
    blend = theme.SEAM, blend_profile = "circular",
    opacity = function() return leaving() and 0 or 1 end,
    enter = { opacity = 0 },
    behavior = { opacity = theme.spring.effects },
    ui.SdfShape { id = "kill-screen", shape = "box", anchors = { fill = true } },
    ui.SdfShape {
      id = "kill-window", shape = "box", operation = "smooth_subtract", track = box,
      radius = kit.round(S.m),
    },
  }
end

local function chip()
  local measure = kit.text { text = words, font_size = theme.size.normal, opacity = 0 }
  local function chip_w()
    local room = math.min(M.CHIP_MAX, screen_w() - 2 * S.s)
    return math.min(room, math.max(S.TARGET * 2, math.ceil(measure.layout_width or 0) + 2 * S.l + S.xl))
  end
  local function place()
    local at, width = rect(), chip_w()
    return math.max(S.s, math.min(screen_w() - width - S.s, at.x + S.s)), math.max(S.s, at.y + S.s)
  end
  return kit.card {
    id = "kill-chip", z = 3, width = chip_w, height = S.TARGET, radius = kit.round(S.s),
    x = function() return (place()) end,
    y = function() local _, y = place() return y end,
    opacity = function() return hover() and not leaving() and 1 or 0 end,
    behavior = { x = theme.spring.spatial, y = theme.spring.spatial, width = theme.spring.spatial,
      opacity = theme.spring.effects },
    ui.Item { width = 1, height = 1, clip = true, measure },
    kit.icon("close", 18, kit.signal("alert"), { x = S.s, anchors = { vertical_center = true } }),
    kit.text {
      id = "kill-title", x = S.xl + S.xs, anchors = { vertical_center = true }, text = words,
      width = function() return math.max(1, chip_w() - S.xl - 2 * S.s) end, elide = "right",
      font_size = theme.size.normal, color = kit.ink("hi"),
    },
  }
end

local function hint()
  return kit.card {
    id = "kill-hint", z = 3, width = function() return math.min(S.TARGET * 9, screen_w() - 2 * S.s) end,
    height = S.TARGET, radius = kit.round(S.s),
    anchors = { horizontal_center = true, bottom = true, bottom_margin = S.l },
    opacity = function() return leaving() and 0 or 1 end,
    behavior = { opacity = theme.spring.effects },
    kit.text {
      anchors = { center_in = true }, color = kit.ink("hi"), font_size = theme.size.normal,
      text = function()
        if #model.windows:get() == 0 then return "No windows · Esc to leave" end
        return responsive.sheets() and "Tap a window twice to end it" or "Press a window to end it · Esc to cancel"
      end,
    },
  }
end

--- Builds the overlay.
function M.overlay()
  local touched = false
  local box = ui.Item {
    id = "kill-box",
    x = function() return rect().x end, y = function() return rect().y end,
    width = function() return rect().w end, height = function() return rect().h end,
    behavior = { x = theme.spring.spatial, y = theme.spring.spatial, width = theme.spring.spatial,
      height = theme.spring.spatial },
    stretch = kit.STRETCH,
  }
  local close = ui.Item {
    id = "kill-cancel-box", z = 3, width = S.TARGET, height = S.TARGET, visible = responsive.sheets(),
    anchors = { horizontal_center = true, bottom = true, bottom_margin = S.l + S.TARGET + S.s },
    L.icon_button {
      id = "kill-cancel", name = "Cancel", icon = "close", width = S.TARGET, height = S.TARGET,
      on_clicked = function() model.cancel() end,
    },
  }
  local root = ui.Item {
    anchors = { fill = true },
    field(box), box,
    ui.MouseArea {
      id = "kill-area", anchors = { fill = true }, cursor = "crosshair", focus = true,
      on_position_changed = function(x, y) model.point(x, y) end,
      on_touch_pressed = function() touched = true end,
      on_clicked = function(x, y)
        model.press(x, y, touched)
        touched = false
      end,
      on_key_pressed = function(_, _, _, _, name)
        if name == "Escape" then model.cancel() return true end
      end,
    },
    chip(), hint(), close,
  }
  return frame.overlay { id = "kill", root = root }
end

return M
