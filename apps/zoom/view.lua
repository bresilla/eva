-- eva-zoom: the small window with its slider, and the lens: the frozen screen
-- magnified inside a circle of a distance field, a rim and the factor's tab
-- joined on the theme's seam, the factor springing as the wheel turns it.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local pill = require("themes.layouts.tool_pill")
local frame = require("common.frame")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

M.RIM = S.s
M.TAB_W, M.TAB_H = S.xxl * 2, S.xxl

local function picture() return model.picture:get() end
local function radius() return model.radius:get() end
local function words(value) return ("%.1f×"):format(value) end

local function screen()
  local s = (morf.screens or {})[1] or {}
  return s.width or 1920, s.height or 1080
end

-- Where the lens stands: on the pointer, or above a finger, held to the screen.
local function centre()
  local at, r = model.at:get(), radius()
  local w, h = screen()
  local x, y = at.x, at.y
  if model.touched:get() then y = y - r - S.xl end
  x = math.max(0, math.min(w, x))
  y = math.max(r, math.min(h, y))
  return x, y
end

local function glass()
  local function d() return 2 * radius() end
  local node = ui.Item {
    id = "zoom-glass", z = 2, width = d, height = d,
    x = function() return (centre()) - radius() end,
    y = function() local _, y = centre() return y - radius() end,
    scale = 1, enter = { scale = 0.2 },
    behavior = { x = theme.spring.fast, y = theme.spring.fast, width = theme.spring.spatial,
      height = theme.spring.spatial, scale = theme.spring.spatial },
    mask = ui.Sdf { ui.SdfShape { shape = "circle", anchors = { fill = true } } },
    ui.Rect { anchors = { fill = true }, color = function() return C.surface end },
    ui.Item {
      id = "zoom-pane", x = radius, y = radius, width = 1, height = 1, transform_origin_x = 0, transform_origin_y = 0,
      scale = function() return model.factor:get() / model.scale() end,
      behavior = { scale = theme.spring.fast },
      ui.Image {
        id = "zoom-image",
        x = function() return -model.at:get().x * model.scale() end,
        y = function() return -model.at:get().y * model.scale() end,
        width = function() local p = picture() return p and p.width or 1 end,
        height = function() local p = picture() return p and p.height or 1 end,
        source = function() local p = picture() return p and p.path or "" end,
      },
    },
  }
  return node
end

local function tab(lens)
  local node = ui.Item {
    id = "zoom-tab", z = 3, width = M.TAB_W, height = M.TAB_H,
    x = function() return (centre()) - M.TAB_W / 2 end,
    y = function() local _, y = centre() return y + radius() - M.TAB_H / 2 + M.RIM end,
    behavior = { x = theme.spring.fast, y = theme.spring.fast },
    kit.text {
      id = "zoom-factor", anchors = { center_in = true }, color = kit.ink("hi"), font_size = theme.size.normal,
      font_weight = 600, text = function() return words(model.factor:get()) end,
    },
  }
  local field = ui.Sdf {
    id = "zoom-rim", z = 2, anchors = { fill = true },
    fill_color = function() return C.surfaceContainerHighest end,
    blend = theme.SEAM, blend_profile = "circular",
    ui.SdfShape { id = "zoom-ring", shape = "ring", thickness = M.RIM, track = lens },
    ui.SdfShape {
      id = "zoom-tab-shape", shape = "box", operation = "smooth_union", radius = kit.round(M.TAB_H / 2), track = node,
    },
  }
  return field, node
end

local function controls_pill(done)
  local function button(id, icon, name, press)
    return L.icon_button { id = id, name = name, icon = icon, width = pill.CELL, height = pill.CELL, on_clicked = press }
  end
  return pill.new {
    id = "zoom-controls", cells = {
      button("zoom-out", "remove", "Less", function() model.step(-1) end),
      button("zoom-in", "add", "More", function() model.step(1) end),
      button("zoom-end", "close", "End", done),
    },
  }
end

local function frozen_screen(done)
  local start
  local lens = glass()
  local field, label = tab(lens)
  local root = ui.Item {
    anchors = { fill = true },
    ui.Image {
      id = "zoom-frozen", anchors = { fill = true },
      source = function() local p = picture() return p and p.path or "" end,
    },
    ui.MouseArea {
      id = "zoom-area", anchors = { fill = true }, cursor = "crosshair", focus = true,
      on_position_changed = function(x, y) model.point(x, y) end,
      on_dragged = function(x, y) model.point(x, y, true) end,
      on_touch_pressed = function(_, x, y) model.point(x, y, true) end,
      on_touch_moved = function(_, x, y) model.point(x, y, true) end,
      on_wheel = function(_, _, _, _, _, step_y, _, _, modifiers)
        local by = step_y > 0 and -1 or 1
        if modifiers and modifiers ~= "" then model.resize(by) else model.step(by) end
      end,
      on_pinched = function(scale, phase)
        if phase == "update" then
          start = start or model.factor:get()
          model.set_factor(start * scale)
        else
          start = nil
        end
      end,
      on_key_pressed = function(_, text, _, _, name)
        if name == "Escape" then done() return true end
        if text == "+" or text == "=" then model.step(1) return true end
        if text == "-" then model.step(-1) return true end
        if text == "]" then model.resize(1) return true end
        if text == "[" then model.resize(-1) return true end
        if text == "0" then model.set_factor(model.MIN) return true end
      end,
    },
    lens, field, label, controls_pill(done),
  }
  return frame.overlay { id = "zoom", root = root }
end

--- The lens for as long as the screen is held; `done()` when it is let go by
--- a press of its own.
function M.overlay(done)
  model.overlay(function() return frozen_screen(done) end)
end

--- The window's content, `w` by `h` (fns); `lens()` opens the lens.
function M.build(w, h, lens)
  local inner = function() return P.inner(w) end
  local span = model.MAX - model.MIN
  local function position() return (model.current() - model.MIN) / span end
  return P.page {
    id = "zoom-page", width = w, height = h,
    P.section {
      id = "zoom-section", width = w, title = model.native() and "Cursor zoom" or "Lens",
      kit.slider {
        id = "zoom-slider", accessible_name = "Zoom factor", width = inner, icon = "zoom_in", value = position,
        set = function(value) model.set(model.MIN + value * span) end,
        reading = function(value) return words(model.MIN + value * span) end,
      },
      P.buttons {
        width = inner,
        { id = "zoom-window-out", label = "Out", icon = "remove",
          on_clicked = function() model.set(model.current() - model.STEP) end },
        { id = "zoom-window-in", label = "In", icon = "add",
          on_clicked = function() model.set(model.current() + model.STEP) end },
        { id = "zoom-window-reset", label = "Reset", on_clicked = function() model.set(model.MIN) end },
      },
    },
    P.buttons {
      width = w,
      { id = "zoom-lens", label = "Lens", icon = "search", tone = "primary", on_clicked = lens },
    },
    kit.text {
      id = "zoom-note", width = w, wrap = true, font_size = P.SUB, color = kit.ink("lo"),
      text = function()
        local words_now = model.message:get()
        if words_now ~= "" then return words_now end
        return model.native() and "The compositor magnifies live, following the pointer."
          or "A lens over the frozen screen: the wheel or a pinch sets it."
      end,
    },
  }
end

return M
