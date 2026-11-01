-- eva-phone: the dialler. `eva-phone tel:+31...` opens with a number typed;
-- `eva-phone import FILE` and `eva-phone export FILE` carry vCards in and out.
local morf = require("morf")
local model = require("model")

local given = morf.operands[1]
if given == "import" or given == "export" then
  local count = model.book[given](morf.operands[2] or "")
  morf.log("info", ("eva: %d contacts %sed"):format(count, given))
  morf.time.timer(1, function() morf.quit() end, false)
  require("morf.ui").Item { width = 1, height = 1 }
  return
end

local frame = require("common.frame")
local view = require("view")

if given then model.number:set((given:gsub("^tel:", ""))) end

frame.open {
  id = "phone", title = "Phone", width = 420, height = 800,
  build = function(w, h) return view.build(w, h) end,
}

morf.effect("phone.seen", function()
  if model.tab:get() == 2 then model.seen() end
end)

morf.ipc.state = function()
  return { number = model.number:get(), message = model.message:get(), recents = #model.recents(),
    people = #model.people(), matches = #model.matches(), tab = model.tab:get(), can_call = model.can_call(),
    unseen = model.unseen() }
end
morf.ipc.tab = function(index) model.tab:set(tonumber(index)) return true end
morf.ipc.press = function(keys)
  for key in tostring(keys):gmatch(".") do model.press(key) end
  return model.number:get()
end
morf.ipc.call = function(number) return model.call(number) end
