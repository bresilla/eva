-- eva-phone: the dialler. `eva-phone tel:+31...` opens with a number typed.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

local given = morf.operands[1]
if given then model.number:set((given:gsub("^tel:", ""))) end

frame.open {
  id = "phone", title = "Phone", width = 420, height = 800,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  return { number = model.number:get(), message = model.message:get(), recents = #model.recents(),
    people = #model.people(), matches = #model.matches(), tab = model.tab:get(), can_call = model.can_call() }
end
morf.ipc.tab = function(index) model.tab:set(tonumber(index)) return true end
morf.ipc.press = function(keys)
  for key in tostring(keys):gmatch(".") do model.press(key) end
  return model.number:get()
end
morf.ipc.call = function(number) return model.call(number) end
