-- A real window for the sealed session: an application of its own, one colour
-- and its name, so that the compositor has something to list and capture.
--
--     morf app tools/see/window_app.lua -- TITLE APP_ID COLOUR
local morf = require("morf")
local ui = require("morf.ui")
local app = require("lib.kit.app")

local args = morf.operands or {}
local title, app_id, colour = args[1] or "Window", args[2] or "see.window", args[3] or "#2a4d69"

morf.surface.blend = "srgb"
morf.surface.namespace = "eva-see-window"
app.application {
  title = title, app_id = app_id, width = 640, height = 480,
  build = function()
    return ui.Rect { anchors = { fill = true }, color = colour,
      ui.Text { anchors = { center_in = true }, text = title, color = "#ffffff", font_size = 42 } }
  end,
}
