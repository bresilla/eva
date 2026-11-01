-- eva-screenshot's window, and the editor for when no shell runs to host it:
--
--     eva-screenshot                     the window: what to take, recent pictures
--     apps/launch screenshot file PICTURE   the editor on a picture
local morf = require("morf")
local ui = require("morf.ui")

if morf.operands[1] == "file" then
  ui.Item { width = 1, height = 1 }
  morf.surface.layer = "background"
  morf.surface.width, morf.surface.height = 1, 1
  morf.surface.keyboard_focus = "none"
  require("common.frame").follow_scheme()
  local editor = require("capture_editor")
  morf.window.layer {
    blend = "srgb", namespace = "eva-capture", layer = "overlay",
    anchors = { top = true, bottom = true, left = true, right = true },
    width = 0, height = 0, exclusive_zone = -1, keyboard_focus = "exclusive", visible = true,
    root = ui.Item { anchors = { fill = true }, editor.node },
  }
  editor.open_file(morf.operands[2], function() morf.quit() end)
  morf.ipc.editor = function(action)
    if action == "copy" or action == "save" then editor.export(action) end
    return { open = editor.active:get(), phase = editor.phase:get(), status = editor.status:get() }
  end
  return
end

local frame = require("common.frame")
local model = require("model")
local view = require("view")

model.load()

frame.open {
  id = "screenshot", title = "Screenshot", width = 760, height = 620,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  return { delay = model.delay:get(), how = model.how:get(), recent = model.recent:get() }
end
morf.ipc.take = function(target) model.take(target) return true end
