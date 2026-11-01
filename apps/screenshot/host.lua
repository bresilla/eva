-- Where the panel and the editor stand: this tool's own surface over the desk.
-- The panel is an ordinary drawer. Its background joins the screen's frame in
-- a field of its own, drawn with the theme's frame paint: over the shell's
-- frame it is held inside the opening, so the bar, the rail and the rulers
-- stay the shell's; with no shell it flares into the edge of the screen.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local bar = require("bar")
local indicator = require("indicator")

local M = {}

-- How far the join's base runs under the panel's sides, past the fillets.
local OVERLAP = 2

M.framed = morf.signal("eva.capture.framed", false)

local function screen()
  morf.window.screens_revision()
  local s = morf.screens[1] or {}
  return s.width or 1920, s.height or 1080
end

--- Whether the shell is on this display: the process it named is still there.
function M.shell_up()
  local ok, text = pcall(morf.fs.read, require("capture_state").shell_path())
  local pid = ok and tostring(text or ""):match("^%d+") or nil
  return pid ~= nil and morf.fs.is_dir("/proc/" .. pid) == true
end

local function desk()
  if M.framed:get() then return bar.desk() end
  local w, h = screen()
  return 0, 0, w, h
end

--- The surface's shape for `posture`: "full", the whole output over everything;
--- "hidden", the same size under everything, transparent and taking no input,
--- so it comes back by changing layer; "strip", the top edge, for the pill.
function M.posture(name)
  M.now = name
  local surface = morf.surface
  if name == "strip" then
    surface.layer = "overlay"
    surface.anchors = { top = true, left = true, right = true }
    surface.width, surface.height, surface.exclusive_zone = 0, indicator.HEIGHT, 0
    return
  end
  surface.layer = name == "full" and "overlay" or "background"
  surface.anchors = { top = true, bottom = true, left = true, right = true }
  surface.width, surface.height, surface.exclusive_zone = 0, 0, -1
end

-- The field: a base the width of the join, its top on the frame's inner edge,
-- and the drawer's own background joining it.
local function join(drawer, width, opening)
  local frame = require("themes").view("frame")
  local function left() local x, _, w = opening() return x + (w - width) / 2 - theme.SEAM - OVERLAP end
  local function edge()
    if not M.framed:get() then local _, h = screen() return h end
    local _, y, _, h = opening()
    return y + h
  end
  local field = frame.paint { id = "capture-frame", width = function() return (screen()) end,
    height = function() local _, h = screen() return h end,
    x = function() local x = opening() return M.framed:get() and -x or 0 end,
    y = function() local _, y = opening() return M.framed:get() and -y or 0 end,
    ui.SdfShape { id = "capture-frame-edge", shape = "box", x = left, y = edge,
      width = width + 2 * (theme.SEAM + OVERLAP), height = theme.ROUNDING + theme.BORDER },
    drawer.shape,
  }
  -- Over the shell, nothing past the opening: that is the shell's frame. It
  -- stands and goes with the panel.
  return ui.Item { id = "capture-frame-clip", clip = true,
    visible = function() return drawer.panel.visible end,
    x = function() local x = opening() return M.framed:get() and x or 0 end,
    y = function() local _, y = opening() return M.framed:get() and y or 0 end,
    width = function()
      local _, _, w = opening()
      if M.framed:get() then return w end
      return (screen())
    end,
    height = function()
      local _, _, _, h = opening()
      if M.framed:get() then return h end
      local _, full = screen()
      return full
    end,
    ui.Sdf(field) }
end

--- The surface's root: the join, the panel, the pill and the editor.
function M.build(capture, shown)
  local insets = require("themes").view("frame").insets()
  local function opening()
    local x, y, w, h = desk()
    return x + insets.left, y + insets.top, w - insets.left - insets.right, h - insets.top - insets.bottom
  end
  local panels = ui.Item { id = "capture-opening", clip = true,
    x = function() local x = opening() return x end,
    y = function() local _, y = opening() return y end,
    width = function() local _, _, w = opening() return w end,
    height = function() local _, _, _, h = opening() return h end,
    capture.drawer.panel }
  return ui.Item { id = "capture-tool", anchors = { fill = true },
    join(capture.drawer, capture.WIDTH, opening),
    panels,
    indicator.build(capture, shown),
    capture.editor.node,
    ui.Loader { anchors = { fill = true }, active = function() return capture.trim_open:get() end,
      source = function() return require("themes").view("capture_trim").build(require("trim")) end },
  }
end

return M
