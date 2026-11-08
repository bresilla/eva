-- eva-clipboard --watch: the history kept with no window, for the session to
-- run. The history itself is a page of the Tools window (page.lua).
local morf = require("morf")
local model = require("apps.clipboard.model")

require("lib.util.job").quiet()
model.load()
model.watch()

morf.ipc.state = function()
  return { items = model.items:get(), found = #model.found(), message = model.message:get() }
end
morf.ipc.text = function(text) model.text(text) return true end
morf.ipc.pin = function(id) model.toggle_pin(id) return true end
morf.ipc.clear = function() model.clear() return true end
