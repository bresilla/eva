-- StandBy on screen: a layer over everything while the model says so.
local morf = require("morf")
local ui = require("morf.ui")
local model = require("standby_model")
local M = { model = model }

local window

function M.start()
  morf.effect("eva.standby.layer", function()
    local showing = model.showing()
    if showing and not window then
      window = morf.window.layer {
        blend = "srgb", namespace = "eva-standby", layer = "overlay", opaque = true,
        anchors = { top = true, bottom = true, left = true, right = true },
        width = 0, height = 0, exclusive_zone = -1, keyboard_focus = "none", visible = true,
        root = ui.Item { anchors = { fill = true },
          require("themes").view("standby").build(model, require("desktop_model")) },
      }
    elseif not showing and window then
      local gone = window
      window = nil
      gone:destroy()
    end
  end)
end

return M
