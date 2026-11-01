-- eva-ruler: measures what is on the screen, over a frozen picture of it. Edges
-- are found by walking the pixels from the pointer.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")
local view = require("view")

local function done()
  model.thaw()
  morf.quit()
end

frame.quiet(true)
model.choose(morf.env("EVA_RULER_MODE") or morf.operands[1] or "spacing")
view.overlay(done)
model.freeze()
frame.on_second(function() done() return true end)

morf.ipc.state = function()
  local at = model.at:get()
  return { frozen = model.picture:get() ~= nil, mode = model.mode:get(), tolerance = model.tolerance:get(),
    edges = model.edges:get(), px = at and at.px, py = at and at.py, reading = model.reading(),
    physical = model.physical_reading(), copied = model.copied:get(), message = model.message:get() }
end
morf.ipc.point = function(x, y) model.point(tonumber(x), tonumber(y)) return true end
morf.ipc.mode = function(name) return model.choose(name) end
morf.ipc.tune = function(by) model.tune(tonumber(by)) return true end
morf.ipc.copy = function() return model.copy() end
morf.ipc.box = function(x0, y0, x1, y1)
  model.box_start(tonumber(x0), tonumber(y0))
  model.box_move(tonumber(x1), tonumber(y1))
  return true
end
