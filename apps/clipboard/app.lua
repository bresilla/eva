-- eva-clipboard: the window over the history, or with `--watch` the history
-- kept with no window, for the session to run.
local morf = require("morf")
local model = require("model")

model.load()
model.watch()

morf.ipc.state = function()
  return { items = model.items:get(), found = #model.found(), message = model.message:get() }
end
morf.ipc.text = function(text) model.text(text) return true end
morf.ipc.pin = function(id) model.toggle_pin(id) return true end
morf.ipc.clear = function() model.clear() return true end

if morf.options.watch then
  require("lib.util.job").quiet()
  return
end

local frame = require("common.frame")
local view = require("view")

frame.open {
  id = "clipboard", title = "Clipboard", width = 640, height = 620,
  build = function(w, h) return view.build(w, h) end,
}
