-- Each monitor's name on that monitor with no shell running: a plain
-- configuration, one runtime to an output.
local morf = require("morf")
local ui = require("morf.ui")
morf.surface.layer = "background"
morf.surface.width, morf.surface.height = 1, 1
morf.surface.exclusive_zone = 0
morf.surface.keyboard_focus = "none"
ui.Item { width = 1, height = 1 }
require("common.frame").follow_scheme()
require("themes").view("displays_identify").show(function() morf.quit() end)
