-- The phone's own surface: the compositor's overlay layer, there while a call
-- is or while the SIM asks, on this output only when it is the primary one. A
-- phone or tablet gets the whole screen, a desk a card along the top.
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

local function look()
  local kit, theme = require("kit"), require("theme")
  local bounce = theme.bounce and theme.bounce.spatial or {}
  return { C = theme.color, text = kit.text, icon = kit.icon, action = kit.action, round = kit.round,
    bounce = { duration = bounce.duration or 300, easing = bounce.easing or "out_back" } }
end

function M.start(owner)
  local layer
  local model, sim, alerts = owner.model, owner.sim, owner.alerts
  local function calling() return model.stage:get() ~= "idle" end
  local function alerting() return alerts ~= nil and alerts.active() end
  local keys = require("hardware_keys")
  local function counting() return keys.sos:get() > 0 end
  local function open()
    local compact = not require("responsive").sheets() and not sim.asking() and not alerting() and not counting()
    local function width() local w = size() return compact and CARD_W or w end
    local function height() local _, h = size() return h end
    local call = require("themes").view("call").build {
      phone = model, width = width, height = height, compact = compact,
    }
    local root = ui.Item { id = "call-root", anchors = { fill = true },
      ui.Item { id = "phone-sim", anchors = { fill = true }, z = 10,
        visible = function() return sim.asking() and not calling() end,
        require("themes.sim_prompt").build { sim = sim, look = look(), width = width, height = height } },
      alerts and ui.Item { id = "phone-alert", anchors = { fill = true }, z = 15,
        visible = function() return alerting() and not calling() end,
        require("themes.alert_sheet").build { alerts = alerts, look = look(), width = width, height = height } } or nil,
      ui.Item { id = "phone-call", anchors = { fill = true }, z = 20, visible = calling, call },
      ui.Item { id = "phone-sos", anchors = { fill = true }, z = 30, visible = counting,
        require("themes.sos_sheet").build { left = keys.sos, cancel = keys.cancel, look = look(),
          width = width, height = height } },
      shield(owner) }
    layer = morf.window.layer {
      blend = "srgb", namespace = "eva-call", layer = "overlay", exclusive_zone = -1, keyboard_focus = "none",
      anchors = compact and { top = true } or { top = true, bottom = true, left = true, right = true },
      width = compact and CARD_W or 0, height = compact and CARD_H or 0,
      margin_top = compact and require("theme").space.xl or 0, visible = true, root = root,
    }
    M.layer = layer
  end
  morf.effect("eva.phone.surface", function()
    local up = calling() or sim.asking() or alerting() or counting()
    local primary = not morf.window.primary or morf.window.primary()
    if up and primary and not layer then open()
    elseif not up and layer then
      layer:destroy()
      layer, M.layer = nil, nil
    end
  end)
end

return M
