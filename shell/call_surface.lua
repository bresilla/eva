-- The phone's own surface: the compositor's overlay layer, there while a call
-- is, or the SIM asks, or a warning stands. A phone gets the whole screen, a
-- desk a card along the top, and a call left running a small chip.
local morf = require("morf")
local ui = require("morf.ui")
local M = {}

-- The card's surface, taller than the card: what the card leaves bare is
-- clear and takes no input. Its keypad needs the room.
local CARD_W, CARD_H = 440, 800

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
  local keys = require("hardware_keys")
  local function calling() return model.stage:get() ~= "idle" end
  local function alerting() return alerts ~= nil and alerts.active() end
  local function counting() return keys.sos:get() > 0 end
  local function asking() return sim.asking() or alerting() or counting() end

  local function surface(root, spec)
    spec.blend, spec.namespace, spec.layer = "srgb", "eva-call", "overlay"
    spec.exclusive_zone, spec.keyboard_focus, spec.visible, spec.root = -1, "none", true, root
    return morf.window.layer(spec)
  end

  local function open_chip()
    local screen = require("themes.call_screen")
    local space = require("theme").space
    return surface(ui.Item { id = "call-root", anchors = { fill = true },
      screen.chip { phone = model, look = look() } },
      { anchors = { top = true }, width = screen.CHIP_W, height = screen.CHIP_H, margin_top = space.xxl + space.s })
  end

  local function open_full()
    local compact = not require("responsive").sheets() and not asking()
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
    return surface(root, compact
      and { anchors = { top = true }, width = CARD_W, height = CARD_H, margin_top = require("theme").space.xl }
      or { anchors = { top = true, bottom = true, left = true, right = true }, width = 0, height = 0 })
  end

  local shown = ""
  morf.effect("eva.phone.surface", function()
    local mode = ""
    if asking() or (calling() and not model.minimised:get()) then mode = "full"
    elseif calling() then mode = "chip" end
    if not morf.window.primary or morf.window.primary() then
      if mode ~= shown then
        if layer then layer:destroy() end
        layer = nil
        if mode == "full" then layer = open_full() elseif mode == "chip" then layer = open_chip() end
        shown = mode
        M.layer = layer
      end
    end
  end)
end

return M
