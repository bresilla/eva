-- The idle warning's layer: an overlay on this output while the warning runs,
-- and nothing at all the rest of the time.
local morf = require("morf")
local ui = require("morf.ui")
local idle = require("idle_model")
local M = {}

local layer, closing, leaving
local LEAVE = 420

local function close()
  if not layer then return end
  closing:set(false)
  if leaving then leaving:cancel() end
  leaving = morf.time.timer(LEAVE, function()
    leaving = nil
    if layer then layer:destroy() layer = nil end
  end, false)
end

local function open()
  if leaving then leaving:cancel() leaving = nil end
  if layer then closing:set(true) return end
  local screen = morf.screens and morf.screens[1]
  local W, H = screen and screen.width or 1920, screen and screen.height or 1080
  closing = closing or morf.signal("eva.idle.closing", false)
  local node = require("themes").view("idle_warning").build {
    width = W, height = H, duration = idle.warning_ms:get(),
    closing = function() return closing:get() end, text = "Locking soon. Move to stay",
  }
  layer = morf.window.layer {
    blend = "srgb", namespace = "eva-idle-warning", layer = "overlay",
    anchors = { top = true, bottom = true, left = true, right = true },
    width = 0, height = 0, exclusive_zone = -1, keyboard_focus = "none", visible = true,
    root = ui.Item { anchors = { fill = true }, node },
  }
  morf.time.timer(16, function() if layer then closing:set(true) end end, false)
end

function M.attach()
  morf.effect("eva.idle.warning", function()
    if idle.phase:get() == "warning" then open() else close() end
  end)
end

return M
