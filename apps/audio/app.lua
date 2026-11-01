-- eva-audio: the full mixer, on the shell's own sound model and pages. With
-- ARGS it is a job with no window (`eva-audio next`). EVA_FAKE_AUDIO=1 puts a
-- stand-in where the sound server would be.
local morf = require("morf")

if morf.env("EVA_FAKE_AUDIO") == "1" then require("fake").install() end

if morf.args[1] then
  local job = require("lib.util.job")
  job.quiet()
  require("model").job(morf.args, job.finish)
  return
end

local frame = require("common.frame")
local model = require("model")
local view = require("view")

model.start()

frame.open {
  id = "audio", title = "Audio", width = 620, height = 760,
  actions = function() return view.actions() end,
  build = function(w, h) return view.build(w, h) end,
}

local function stream(page, id)
  return page.stream(tonumber(id))
end

local function page(direction) return direction == "input" and model.input or model.output end

morf.ipc.state = function()
  local function rows(list)
    local out = {}
    for index = 1, list:len() do out[index] = list:get(index) end
    return out
  end
  local shown = page(model.TABS[model.tab:get()])
  return { tab = model.TABS[model.tab:get()], available = shown.available(), devices = rows(shown.devices),
    streams = rows(shown.streams), default = shown.default(), editing = model.editing:get(),
    shell = model.shell_up:get() }
end
morf.ipc.tab = function(name) return model.select(name) end
morf.ipc.mute = function(direction, id)
  local shown = page(direction)
  return shown.toggle_stream(stream(shown, id))
end
morf.ipc.route = function(direction, id, device)
  local shown = page(direction)
  return shown.route(stream(shown, id), shown.device(tonumber(device)))
end
morf.ipc.channel = function(direction, index, value)
  return page(direction).set_channel(tonumber(index), tonumber(value))
end
morf.ipc.editor = function(how)
  if how == "open" then model.equalizer.open_editor() else model.equalizer.leave_editor() end
  return true
end
morf.ipc.band = function(index, value) return model.equalizer.set_band(tonumber(index), tonumber(value)) end
morf.ipc.equalizer = function(how) return model.equalizer.set("enabled", how == "on") end
morf.ipc.restart = function() model.restart() return true end
