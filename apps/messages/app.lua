-- eva-messages: text threads. `eva-messages sms:+31...` opens that thread.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

local given = morf.operands[1]
if given then model.show((given:gsub("^sms:", ""))) end

frame.open {
  id = "messages", title = "Messages", width = 480, height = 800,
  actions = function() return view.actions() end,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  return { threads = model.threads(), open = model.open:get(), thread = model.thread(),
    draft = model.draft:get(), can_send = model.can_send(), composing = model.composing:get() }
end
morf.ipc.fit = function(words, size, limit) return view.fit(words, tonumber(size), tonumber(limit)) end
morf.ipc.show = function(number) model.show(number) return true end
morf.ipc.close = function() model.close() return true end
morf.ipc.compose = function(number) model.compose(number) return true end
morf.ipc.write = function(text) model.draft:set(text) return true end
morf.ipc.send = function() return model.send() end
morf.ipc.fake = function(what, ...)
  if not model.standin then error("no stand-in") end
  return model.standin[what](...)
end
