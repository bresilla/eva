-- eva-qr: a code from text or a Wi-Fi network. With `--png` it writes one and
-- ends; other words open the window on them.
local morf = require("morf")
local frame = require("common.frame")
local job = require("lib.util.job")
local model = require("model")

local png = model.take(morf.args, job.input())

if png then
  frame.quiet()
  model.save(png, function(ok, words)
    if ok then job.finish(png) else job.finish(nil, words) end
  end)
  return
end

local view = require("view")

view.overlay()
model.load_saved()
if morf.args[1] then model.encode() end

frame.open {
  id = "qr", title = "QR code", width = 520, height = 760, minimum_height = 640,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function() return model.state() end
morf.ipc.text = function(...)
  model.mode:set(1)
  model.text:set(table.concat({ ... }, " "))
  return true
end
morf.ipc.wifi = function(ssid)
  model.mode:set(2)
  model.ssid:set(ssid or "")
  return true
end
morf.ipc.security = function(index) model.security:set(tonumber(index)) return true end
morf.ipc.hidden = function(how) model.hidden:set(how == "on") return true end
morf.ipc.level = function(index) model.level:set(tonumber(index)) return true end
morf.ipc.focus = function() view.password_input.focus = true return true end
morf.ipc.copy = function() return model.copy() end
morf.ipc.save = function(path) model.save(path or model.default_path()) return true end
morf.ipc.show = function(how) model.full:set(how ~= "off") return true end
morf.ipc.pick = function(name) model.pick_saved(name) return true end
