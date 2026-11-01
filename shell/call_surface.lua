-- The call screen's own surface: the compositor's overlay layer, there while a
-- call is, and on this output only when it is the primary one. A phone or
-- tablet gets the whole screen, a desk a card along the top.
local morf = require("morf")
local ui = require("morf.ui")
local M = {}

-- The card's surface, taller than the card: what the card leaves bare is
-- clear and takes no input. Its keypad needs the room.
local CARD_W, CARD_H = 440, 620

local function size()
  local s = (morf.screens or {})[1] or {}
  return s.width or 1920, s.height or 1080
end

-- While the sensor reads near the panel is dark and this takes every touch.
local function shield(owner)
  return ui.Rect {
    id = "call-shield", anchors = { fill = true }, z = 100, color = "#000000",
    visible = function() return owner.near:get() end,
    ui.MouseArea { anchors = { fill = true }, on_clicked = function() end },
  }
end

function M.start(owner)
  local layer
  local function open()
    local compact = not require("responsive").sheets()
    local function width() local w = size() return compact and CARD_W or w end
    local function height() local _, h = size() return compact and CARD_H or h end
    local screen = require("themes").view("call").build {
      phone = owner.model, width = width, height = height, compact = compact,
    }
    local root = ui.Item { id = "call-root", anchors = { fill = true }, screen, shield(owner) }
    layer = morf.window.layer {
      blend = "srgb", namespace = "eva-call", layer = "overlay", exclusive_zone = -1, keyboard_focus = "none",
      anchors = compact and { top = true } or { top = true, bottom = true, left = true, right = true },
      width = compact and CARD_W or 0, height = compact and CARD_H or 0,
      margin_top = compact and require("theme").space.xl or 0, visible = true, root = root,
    }
    M.layer = layer
  end
  morf.effect("eva.phone.surface", function()
    local up = owner.model.stage:get() ~= "idle"
    local primary = not morf.window.primary or morf.window.primary()
    if up and primary and not layer then open()
    elseif not up and layer then
      layer:destroy()
      layer, M.layer = nil, nil
    end
  end)
end

return M
