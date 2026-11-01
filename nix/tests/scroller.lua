-- A window that scrolls under two fingers, as a browser's page does, and writes
-- how far it got to /tmp/scroller.log for touch.py to read.
local morf = require("morf")
local ui = require("morf.ui")
local app = require("lib.kit.app")

local offset = morf.signal("scroller.offset", 0)
local from = 0

morf.surface.blend = "srgb"
morf.surface.namespace = "eva-test-scroller"
app.application {
  title = "scroller", app_id = "eva.test.scroller", width = 640, height = 480,
  build = function()
    return ui.Rect { anchors = { fill = true }, color = "#26547c",
      ui.Text { anchors = { center_in = true }, color = "#ffffff", font_size = 42,
        text = function() return ("%.0f"):format(offset:get()) end },
      ui.MouseArea { anchors = { fill = true },
        on_two_finger_panned = function(phase, _, dy1, _, dy2)
          if phase == "begin" then
            from = offset:get()
            return true
          end
          offset:set(from + (dy1 + dy2) / 2)
          morf.fs.write("/tmp/scroller.log", ("%.0f\n"):format(offset:get()))
        end },
    }
  end,
}
