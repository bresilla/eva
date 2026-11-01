-- What a window looks like in a list of windows: its latest picture, or its
-- icon and name until there is one. The overview and the switcher draw this.
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local shots = require("window_shots")
local windows = require("windows_model")
local C = theme.color
local M = {}

--- The application's icon at `size`, or the theme's window glyph.
function M.icon(class, initial, size)
  local hit = windows.icon(class, initial)
  if hit and hit.name then
    return ui.Icon { width = size, height = size, name = hit.name, source_width = size * 2, source_height = size * 2 }
  end
  if hit and hit.path then
    return ui.Image { width = size, height = size, source = hit.path, fill_mode = "preserve_aspect_fit" }
  end
  return kit.icon("select_window", size, function() return C.onSurfaceVariant end)
end

--- The picture: `address` (a function), `class`, `title` (functions),
--- `initial`, `radius`, `glyph` (the icon's size).
function M.picture(spec)
  local glyph = spec.glyph or 40
  local function has() return shots.source(spec.address()) ~= "" end
  return ui.ClipRect { id = spec.id, anchors = { fill = true }, radius = spec.radius,
    color = function() return C.surfaceContainerHigh end,
    ui.Item { anchors = { center_in = true }, width = glyph, height = glyph, visible = function() return not has() end,
      M.icon(spec.class(), spec.initial and spec.initial(), glyph) },
    ui.Image { anchors = { fill = true }, fill_mode = "stretch", visible = has,
      source = function() return shots.source(spec.address()) end },
  }
end

--- A title pill: the icon, and the window's name.
function M.caption(spec)
  local h = spec.height or 32
  local icon = 20
  local function width()
    local room = spec.room()
    return math.max(icon + 2 * theme.space.s, math.min(room, spec.width or 280))
  end
  return kit.surface { id = spec.id, height = h, width = width, radius = L.control_round(h),
    color = function() return C.surfaceContainerHighest:alpha(.92) end,
    ui.Item { x = theme.space.s, y = (h - icon) / 2, width = icon, height = icon,
      M.icon(spec.class(), spec.initial and spec.initial(), icon) },
    kit.text { x = theme.space.s * 2 + icon, y = 0, height = h, vertical_alignment = "center",
      width = function() return math.max(0, width() - icon - 3 * theme.space.s) end,
      elide = "right", text = spec.title, font_size = L.SIZE.body, color = kit.ink("hi") },
  }
end

return M
