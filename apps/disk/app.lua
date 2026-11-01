-- eva-disk: what takes the room under a folder. `eva-disk FOLDER` starts there.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

model.start(morf.operands[1])

frame.open {
  id = "disk", title = "Disk usage", width = 980, height = 720,
  on_close = function() model.stop() end,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  local names = {}
  for index, entry in ipairs(model.entries:get()) do
    if index > 40 then break end
    names[index] = { name = entry.name, size = entry.size, dir = entry.dir }
  end
  return { path = model.path:get(), entries = names, total = model.total:get(), scanning = model.scanning:get(),
    message = model.message:get(), boxes = model.boxes:get(), crumbs = model.crumbs(model.path:get()), moving = model.moving:get(),
    tab = model.TABS[model.tab:get()], mounts = model.mounts() }
end
morf.ipc.open = function(path) return model.open(path) end
morf.ipc.up = function() return model.up() end
morf.ipc.press = function(index) return model.press(tonumber(index)) end
morf.ipc.refresh = function() return model.refresh() end
morf.ipc.reveal = function() return model.reveal() end
morf.ipc.tab = function(name) return model.select_tab(name) end
