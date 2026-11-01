-- A tool's window: the shell's theme, kit and palette in a real window, the
-- colours following lule and the appearance following the shell's file.
--
--     local frame = require("common.frame")
--     frame.open { id = "keys", title = "Keys", width = 900, height = 640,
--       build = function(w, h) return node end }
--
-- `w` and `h` are fns following the window, as the page template takes them.
local morf = require("morf")
local ui = require("morf.ui")
local app = require("lib.kit.app")
local config = require("config")
local theme = require("theme")
local kit = require("kit")
local themes = require("themes")
local color_mode = require("themes.color_mode")
local terminal_colors = require("terminal_colors")
local L = require("themes.layouts.parts")
local C, S = theme.color, theme.space

local M = {}

M.HEADER_H = S.TARGET + S.m
M.CLOSE = S.TARGET
M.PAD = S.l

--- The Material scheme and lule's own colours, from what the colour tool made.
function M.follow_scheme()
  morf.effect("eva.app.lule", function() theme.apply_lule(terminal_colors.current:get()) end)
  morf.effect("eva.app.scheme", function()
    local source = config.get("theme.source")
    local tool = terminal_colors.current:get()
    local mode = color_mode.resolve(tool and tool.mode)
    if (source == "auto" or source == "lule") and tool then
      theme.follow(tool.accent, nil, mode)
    else
      local picture = config.get("wallpaper.path")
      theme.follow(source == "auto" and "wallpaper" or source, picture, mode)
    end
    config.get("theme.variant")
  end)
end

-- A theme or font chosen elsewhere builds the window again in place.
local function follow_appearance()
  local style, font = themes.preferences.get("theme"), themes.preferences.get("font")
  morf.effect("eva.app.appearance", function()
    local now, face = themes.preferences.get("theme"), themes.preferences.get("font")
    if now ~= style or face ~= font then morf.reload() end
  end)
end

local function header(win, spec, w)
  local close = kit.action {
    id = spec.id .. "-close", accessible_name = "Close", width = M.CLOSE, height = M.CLOSE,
    cursor = "pointer", anchors = { right = true, right_margin = S.s, vertical_center = true },
    on_clicked = function() if spec.on_close then spec.on_close() end win:close() end,
    kit.icon("close", 20, kit.ink("hi"), { anchors = { center_in = true } }),
  }
  kit.hover(close, function(hovered) return hovered and C.onSurface:alpha(0.08) or C.onSurface:alpha(0) end, 20)
  local actions = spec.actions and spec.actions(w) or nil
  if actions then
    actions.anchors = { right = true, right_margin = S.s + M.CLOSE + S.s, vertical_center = true }
  end
  return L.item {
    id = spec.id .. "-header", width = w, height = M.HEADER_H,
    ui.MouseArea {
      anchors = { fill = true },
      on_pressed = function() win:start_system_move() end,
    },
    kit.text {
      id = spec.id .. "-title", x = S.l, anchors = { vertical_center = true }, text = spec.title,
      font_size = L.SIZE.title, color = kit.ink("hi"),
    },
    actions, close,
  }
end

--- Opens the tool's window: `id`, `title`, `width`, `height`, `minimum_width`,
--- `minimum_height`, `actions(w)` (a node at the header's right), `on_close`,
--- `build(w, h)` (the content under the header, `w` and `h` fns). Returns the
--- window.
function M.open(spec)
  morf.surface.blend = "srgb"
  morf.surface.namespace = "eva-" .. spec.id
  require("themes.ui_scale").apply()
  M.follow_scheme()
  follow_appearance()
  -- A window that lives through a reload gets no configure: its size is kept.
  local kept = morf.reloadable("eva.app.size", {})
  local size = kept:get()
  return app.application {
    title = spec.title, app_id = "eva." .. spec.id,
    width = size.width or spec.width, height = size.height or spec.height,
    minimum_width = spec.minimum_width or 340, minimum_height = spec.minimum_height or 400,
    on_closed = spec.on_close,
    build = function(win)
      morf.effect("eva.app.size", function() kept:set { width = win.width, height = win.height } end)
      local function w() return win.width end
      local function h() return math.max(0, win.height - M.HEADER_H) end
      local inner = M.PAD
      local function body_w() return math.max(1, w() - 2 * inner) end
      return ui.Rect {
        id = spec.id .. "-root", anchors = { fill = true }, color = C.surface,
        header(win, spec, w),
        ui.Item { x = inner, y = M.HEADER_H, width = body_w, height = h, spec.build(body_w, h) },
      }
    end,
  }
end

return M
