-- eva-text: a developer's scratchpad. With words it is the same transforms on a
-- command line: `eva-text base64 < file`.
local morf = require("morf")
local frame = require("common.frame")
local job = require("lib.util.job")
local model = require("model")

if morf.args[1] then
  frame.quiet()
  model.job(morf.args, job.input(), job.finish)
  return
end

local view = require("view")

frame.open {
  id = "text", title = "Text", width = 680, height = 780, minimum_width = 380, minimum_height = 620,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  return { text = model.text:get(), tab = model.tab:get(), undo = model.undoing:get(), made = model.made:get(),
    message = model.message:get() }
end
morf.ipc.text = function(...) model.text:set(table.concat({ ... }, " ")) return true end
morf.ipc.apply = function(id) return model.apply(id) end
morf.ipc.undo = function() return model.undo() end
morf.ipc.tab = function(index) model.tab:set(tonumber(index)) return true end
morf.ipc.make = function(kind)
  if kind == "passphrase" then model.make_passphrase() else model.make_password() end
  return true
end
morf.ipc.uuid = function() model.uuid() return true end
morf.ipc.copy_secret = function() return model.copy_secret() end
