-- eva-find's overlay. The spotlight is one distance field: a box over the screen
-- with a circle taken out of it on a soft seam, the circle springing in tight
-- from wide. The crosshairs are two lines of a field with a gap at the pointer.
-- A press's rings each draw themselves out on the theme's spring.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local frame = require("common.frame")
local L = require("themes.layouts.parts")
local pill = require("themes.layouts.tool_pill")
local responsive = require("responsive")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

M.CIRCLE = 220
M.RIM = S.xs
M.DOT = S.s
M.DIM = 0.72
M.LINE = S.xs
M.GAP = S.xxl * 2
M.RING = S.xxl * 6

local function at() return model.at:get() end
local function leaving() return model.leaving:get() end

-- How many times over the circle grows to clear the whole screen.
local function wide()
  local screen = (morf.screens or {})[1] or {}
  local w, h = screen.width or 1920, screen.height or 1080
  return 2.4 * math.sqrt(w * w + h * h) / M.CIRCLE
end

-- A box that stands on the pointer, for a field's layer to track.
local function on_pointer(spec)
  spec.x = function() return at().x - spec.width / 2 end
  spec.y = function() return at().y - spec.height / 2 end
  spec.behavior = spec.behavior or {}
  spec.behavior.x, spec.behavior.y = theme.spring.fast, theme.spring.fast
  return ui.Item(spec)
end

local function spotlight()
  local hole = on_pointer {
    id = "find-hole", width = M.CIRCLE, height = M.CIRCLE,
    scale = function() return leaving() and wide() or 1 end,
    enter = { scale = wide() },
    behavior = { scale = theme.spring.spatial },
    kit.decor("corners", { length = S.l }),
  }
  local dim = ui.Sdf {
    id = "find-field", anchors = { fill = true },
    fill_color = function() return C.scrim:alpha(M.DIM) end,
    blend = S.xl, blend_profile = "circular",
    opacity = function() return leaving() and 0 or 1 end,
    enter = { opacity = 0 },
    behavior = { opacity = theme.spring.effects },
    ui.SdfShape { id = "find-screen", shape = "box", anchors = { fill = true } },
    ui.SdfShape { id = "find-circle", shape = "circle", operation = "smooth_subtract", track = hole },
  }
  local rim = ui.Sdf {
    id = "find-rim", anchors = { fill = true },
    fill_color = kit.stroke("hot"),
    opacity = function() return leaving() and 0 or 1 end,
    behavior = { opacity = theme.spring.effects },
    ui.SdfShape { shape = "ring", thickness = M.RIM, track = hole },
  }
  local dot = on_pointer {
    id = "find-dot", width = M.DOT, height = M.DOT,
    scale = function() return leaving() and 0 or 1 end,
    enter = { scale = 0 },
    behavior = { scale = theme.spring.fast },
  }
  local centre = ui.Sdf {
    id = "find-centre", anchors = { fill = true }, fill_color = kit.stroke("hot"),
    ui.SdfShape { shape = "circle", track = dot },
  }
  return ui.Item { id = "find-spotlight", anchors = { fill = true }, dim, rim, centre, hole, dot }
end

local function crosshairs(w, h)
  local long_w, long_h = 2 * w, 2 * h
  local across = on_pointer {
    id = "find-across", width = long_w, height = M.LINE, scale = 1, enter = { scale = 0 },
    behavior = { scale = theme.spring.spatial },
  }
  local down = on_pointer {
    id = "find-down", width = M.LINE, height = long_h, scale = 1, enter = { scale = 0 },
    behavior = { scale = theme.spring.spatial },
  }
  local gap = on_pointer { id = "find-gap", width = M.GAP, height = M.GAP }
  local field = ui.Sdf {
    id = "find-lines", anchors = { fill = true },
    fill_color = kit.stroke("hot"), blend = S.s, blend_profile = "circular",
    shadow_color = function() return C.surface:alpha(0.7) end, shadow_blur = S.s,
    opacity = function() return leaving() and 0 or 1 end,
    behavior = { opacity = theme.spring.effects },
    ui.SdfShape { id = "find-line-across", shape = "box", track = across },
    ui.SdfShape { id = "find-line-down", shape = "box", operation = "smooth_union", track = down },
    ui.SdfShape { id = "find-line-gap", shape = "circle", operation = "smooth_subtract", track = gap },
  }
  return ui.Item { id = "find-crosshairs", anchors = { fill = true }, field, across, down, gap }
end

-- One press's ring: it leaves the press small, goes out on the spring, and
-- fades as its row goes.
local function ring(row)
  local fade = theme.bounce.effects
  return ui.Sdf {
    id = "find-ring-" .. row.key, width = M.RING, height = M.RING,
    x = row.x - M.RING / 2, y = row.y - M.RING / 2,
    fill_color = kit.stroke("hot"),
    scale = 1, enter = { scale = 0.1 },
    exit = { opacity = 0, scale = 1.3, duration = fade.duration, easing = fade.easing },
    behavior = { scale = theme.spring.spatial },
    ui.SdfShape { shape = "ring", thickness = M.RIM, anchors = { fill = true } },
  }
end

local function ripple()
  return ui.Item {
    id = "find-ripple", anchors = { fill = true },
    ui.Repeater { model = model.rings, delegate = ring },
    kit.card {
      id = "find-hint", width = S.TARGET * 8, height = S.TARGET, radius = kit.round(S.s),
      anchors = { horizontal_center = true, top = true, top_margin = S.l },
      kit.text {
        anchors = { center_in = true }, color = kit.ink("hi"), font_size = theme.size.normal,
        text = responsive.sheets() and "Tap for rings" or "Press for rings · Esc to end",
      },
    },
  }
end

-- Over the press area: what ends the rings for a finger.
local function finger_end()
  return ui.Item {
    id = "find-end-box", anchors = { fill = true }, visible = responsive.sheets(),
    pill.new {
      id = "find-controls", cells = {
        L.icon_button {
          id = "find-end", name = "End", icon = "close", width = pill.CELL, height = pill.CELL,
          on_clicked = function() model.finish() end,
        },
      },
    },
  }
end

--- Builds the overlay for the chosen mode.
function M.overlay()
  local screen = (morf.screens or {})[1] or {}
  local mode = model.mode:get()
  local show
  if mode == "crosshairs" then show = crosshairs(screen.width or 1920, screen.height or 1080)
  elseif mode == "ripple" then show = ripple()
  else show = spotlight() end
  local root = ui.Item {
    anchors = { fill = true },
    show,
    ui.MouseArea {
      id = "find-area", anchors = { fill = true }, cursor = mode == "spotlight" and "default" or "crosshair",
      focus = true, accepted_buttons = { "left", "right", "middle", "back", "forward" },
      on_position_changed = function(x, y) model.point(x, y) end,
      on_pressed = function(x, y)
        if mode == "ripple" then model.ripple(x, y) else model.finish() end
      end,
      on_wheel = function() if mode ~= "ripple" then model.finish() end end,
      on_key_pressed = function(_, _, _, _, name)
        if name == "Escape" or mode ~= "ripple" then model.finish() end
        return true
      end,
    },
    mode == "ripple" and finger_end() or nil,
  }
  morf.effect("find.shown", function()
    if (root.layout_width or 0) > 0 then model.shown() end
  end, { owner = root })
  return frame.overlay { id = "find", root = root }
end

return M
