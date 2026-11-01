-- eva-displays: arrange the monitors. `--auto` applies the saved profile for
-- what is connected, with no window, and ends.
local morf = require("morf")
local ui = require("morf.ui")

if morf.operands[1] == "--auto" then
  ui.Item { width = 1, height = 1 }
  morf.surface.layer = "background"
  morf.surface.width, morf.surface.height = 1, 1
  require("lib.shell.displays").auto_apply(function(name, why)
    if why then morf.log("warn", "eva-displays: " .. tostring(why)) end
    if name then morf.log("info", "eva-displays: applied " .. name) end
    morf.quit()
  end)
  return
end

local frame = require("common.frame")
local model = require("model")
local view = require("view")

model.refresh()
model.load_profiles()

frame.open {
  id = "displays", title = "Displays", width = 1100, height = 760,
  on_close = function() if model.countdown:get() > 0 then model.revert() end end,
  build = function(w, h) return view.build(w, h) end,
}

-- Driven by the tool's own socket, for tests and scripts.
morf.ipc.state = function()
  return { outputs = model.outputs:get(), selected = model.selected:get(), message = model.message:get(),
    countdown = model.countdown:get(), dirty = model.dirty:get(), profiles = model.profiles:get() }
end
morf.ipc.refresh = function() model.refresh() return true end
morf.ipc.select = function(name) model.selected:set(name) return true end
morf.ipc.place = function(name, x, y)
  model.place(name, tonumber(x), tonumber(y))
  model.settle()
  return true
end
morf.ipc.set = function(name, field, value)
  if field == "scale" or field == "transform" then value = tonumber(value)
  elseif field == "enabled" or field == "vrr" then value = value == "true" end
  model.set(name, field, value)
  return true
end
morf.ipc.apply = function() return model.apply() end
morf.ipc.keep = function() model.keep() return true end
morf.ipc.revert = function() model.revert() return true end
morf.ipc.identify = function() model.identify() return true end
morf.ipc["save-profile"] = function(name) return model.save_profile(name) end
