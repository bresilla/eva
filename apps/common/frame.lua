-- A tool's window: the shell's theme, kit and palette in a real window, the
-- colours following lule and the appearance following the shell's file. Its
-- frame is the shell's: one distance field, a band round an opening, the title
-- and the close button tabs of that band on the theme's seams and springs.
--
--     local frame = require("common.frame")
--     frame.open { id = "keys", title = "Keys", width = 900, height = 640,
--       build = function(w, h) return node end }
--
-- `w` and `h` are fns following the window, as the page template takes them.
-- A tool that draws on the screen takes `frame.overlay`; a tool with no window
-- at all takes `frame.quiet`.
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

local second

-- A tab's depth from the window's edge, and where the content starts below it.
M.TAB_H = S.TARGET + S.s
M.HEADER_H = M.TAB_H + S.s
M.CLOSE = S.TARGET
M.PAD = S.l
M.EDGE = S.s
-- How far a tab reaches past the window's edge, under the band.
M.REACH = S.xl
-- The title tab's reach: what the close tab always leaves it.
M.TITLE_ROOM = S.TARGET + S.xl

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

-- A box of the band reaching into the opening: it drops in on the theme's
-- spring and bends as it lands.
local function tab(id, props)
  props.id = id
  props.y = -M.REACH
  props.height = M.TAB_H + M.REACH
  props.translate_y = 0
  props.enter = { translate_y = -M.TAB_H }
  props.behavior = { width = theme.spring.spatial, x = theme.spring.spatial, translate_y = theme.spring.spatial }
  props.stretch = kit.STRETCH
  return ui.Item(props)
end

local function header(win, spec, w)
  local close = kit.action {
    id = spec.id .. "-close", accessible_name = "Close", width = M.CLOSE, height = M.CLOSE,
    cursor = "pointer", anchors = { right = true, right_margin = M.EDGE, vertical_center = true },
    on_clicked = function() if spec.on_close then spec.on_close() end win:close() end,
    kit.icon("close", 20, kit.ink("hi"), { anchors = { center_in = true } }),
  }
  kit.hover(close, function(hovered) return hovered and C.onSurface:alpha(0.08) or C.onSurface:alpha(0) end, 20)
  local actions = spec.actions and spec.actions(w) or nil
  if actions then
    actions.anchors = { right = true, right_margin = M.EDGE + M.CLOSE + S.s, vertical_center = true }
  end
  local function actions_w() return actions and (actions.layout_width or 0) + S.s or 0 end
  local function right_w() return M.EDGE * 2 + M.CLOSE + actions_w() end
  local measure = kit.text { text = spec.title, font_size = L.SIZE.title, opacity = 0 }
  local function title_w()
    local most = math.max(S.TARGET, w() - right_w() - M.TITLE_ROOM)
    return math.min(most, math.ceil(measure.layout_width or 0) + 2 * M.PAD)
  end
  local left = tab(spec.id .. "-title-tab", {
    x = 0, width = title_w,
    ui.Item { width = 1, height = 1, clip = true, measure },
    ui.Item {
      y = M.REACH, width = title_w, height = M.TAB_H,
      kit.text {
        id = spec.id .. "-title", x = M.PAD, anchors = { vertical_center = true }, text = spec.title,
        width = function() return math.max(1, title_w() - 2 * M.PAD) end, elide = "right",
        font_size = L.SIZE.title, color = kit.ink("hi"),
      },
    },
  })
  local right = tab(spec.id .. "-close-tab", {
    x = function() return w() - right_w() end, width = right_w,
    ui.Item { y = M.REACH, width = right_w, height = M.TAB_H, actions, close },
  })
  local area = ui.MouseArea {
    id = spec.id .. "-header", width = w, height = M.TAB_H,
    on_pressed = function() win:start_system_move() end,
  }
  return area, left, right
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
  morf.ipc["eva-app"] = function()
    return { theme = themes.current.id, primary = C.primary:hex(), settings = config.path }
  end
  -- The window's size, kept across a reload.
  local kept = morf.reloadable("eva.app.size", {})
  local size = kept:get()
  -- A second launch asks this: the window comes forward, by its app id.
  local app_id = "eva." .. spec.id
  morf.ipc["eva-raise"] = function()
    if second then return second() end
    local list = morf.toplevels and morf.toplevels.list and morf.toplevels.list() or {}
    for _, row in ipairs(list) do
      if row.app_id == app_id then
        morf.toplevels.activate(row.identifier)
        return true
      end
    end
    return false
  end
  return app.application {
    title = spec.title, app_id = app_id,
    width = size.width or spec.width, height = size.height or spec.height,
    minimum_width = spec.minimum_width or 340, minimum_height = spec.minimum_height or 400,
    on_closed = spec.on_close,
    build = function(win)
      morf.effect("eva.app.size", function() kept:set { width = win.width, height = win.height } end)
      local function w() return win.width end
      local function h() return math.max(0, win.height - M.HEADER_H - M.PAD) end
      local function body_w() return math.max(1, w() - 2 * M.PAD) end
      local area, left, right = header(win, spec, w)
      local opening = M.EDGE
      local body = ui.ClipRect {
        id = spec.id .. "-opening-clip", anchors = { fill = true, margins = opening }, radius = theme.ROUNDING,
        color = "transparent",
        ui.Item {
          x = M.PAD - opening, y = M.HEADER_H - opening, width = body_w, height = h,
          opacity = 1, translate_y = 0,
          enter = { opacity = 0, translate_y = S.m },
          behavior = { opacity = theme.spring.effects, translate_y = theme.spring.spatial },
          spec.build(body_w, h),
        },
      }
      local field = themes.view("app_frame").build {
        id = spec.id, edge = opening,
        tabs = { { node = left }, { node = right, right = true } },
      }
      return ui.Rect {
        id = spec.id .. "-root", anchors = { fill = true }, color = function() return C.surface end,
        body, area, field, left, right,
      }
    end,
  }
end

--- A surface over everything: `id`, `root` (fills it), `keyboard` ("exclusive"
--- by default), `visible` (true by default). Returns the surface.
function M.overlay(spec)
  return morf.window.layer {
    blend = "srgb", namespace = "eva-" .. spec.id, layer = "overlay",
    anchors = { top = true, bottom = true, left = true, right = true },
    width = 0, height = 0, exclusive_zone = -1, keyboard_focus = spec.keyboard or "exclusive",
    visible = spec.visible ~= false, root = spec.root,
  }
end

--- Ends an overlay from anywhere, its own event handlers among them: the
--- surface goes at once and is taken apart on the next turn.
function M.dismiss(layer)
  layer:close()
  morf.time.timer(1, function() layer:destroy() end, false)
end

--- The configuration's own surface out of the way, for a tool that draws
--- nothing there; `follow` keeps the theme's colours for an overlay of its.
function M.quiet(follow)
  require("lib.util.job").quiet()
  if follow then M.follow_scheme() end
end

--- Sets what a second launch does to this tool, in the place of raising a
--- window: an overlay shuts, as a key pressed twice would.
function M.on_second(action)
  second = action
  morf.ipc["eva-raise"] = action
end

return M
