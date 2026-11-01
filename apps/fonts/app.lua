-- eva-fonts: browse the installed fonts, preview them, set the shell's. With
-- words it is a job on the same code and ends.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")

if morf.operands[1] then
  frame.quiet()
  model.job(morf.operands, require("lib.shell.tool_job").finish)
  return
end

local view = require("view")

model.restore()
model.load()

frame.open {
  id = "fonts", title = "Fonts", width = 980, height = 680, minimum_width = 360, minimum_height = 560,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  return { families = #model.families:get(), shown = model.shown(), chosen = model.chosen:get(),
    weights = model.weights:get(), weight = model.weight:get(), size = model.SIZES[model.size:get()],
    sample = model.sample:get(), mono_only = model.mono_only:get(), message = model.message:get(),
    status = model.status:get() }
end
morf.ipc.choose = function(family) model.choose(family) return true end
morf.ipc.mono = function(how) model.set_mono(how == "on") return true end
morf.ipc.search = function(query) model.search(query or "") return true end
morf.ipc.size = function(index) model.size:set(tonumber(index)) return true end
morf.ipc.weight = function(weight) model.weight:set(tonumber(weight)) return true end
morf.ipc.apply = function(family) model.apply(family or model.chosen:get()) return true end
