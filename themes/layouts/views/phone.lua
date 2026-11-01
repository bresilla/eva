-- The Phone page, in the page template (themes/layouts/page.lua): the phones
-- KDE Connect knows, the one on show with its battery, what can be done with
-- it, and its notifications. A file dropped on the page goes to the phone.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local C = theme.color
local M = {}

function M.build(model, active, w, h)
  local inner = P.inner(w)
  local hovering = morf.signal("eva.phone.hovering." .. tostring({}), false)
  local function has() return model.devices:len() > 0 end
  local function shown() return model.device() end
  local function reachable() local device = shown() return device ~= nil and device.reachable end

  local function battery_words()
    local reading = model.battery:get()
    if reading.id ~= model.selected:get() or not reading.percent then return "Battery not reported" end
    return ("Battery %d%%%s"):format(reading.percent, reading.charging and ", charging" or "")
  end

  local list = ui.Repeater { as = "column", gap = P.ROW_GAP, width = inner, model = model.devices,
    delegate = function(row)
      return P.row { id = "phone-device-" .. row.id, width = inner, icon = "smartphone", title = row.name,
        on = function() return model.selected:get() == row.id end,
        subtitle = row.reachable and "Reachable" or "Out of reach",
        on_clicked = function() model.select(row.id) end }
    end }
  local notes = ui.Repeater { as = "column", gap = theme.space.xs, width = inner, model = model.notifications,
    delegate = function(row)
      return kit.text { id = "phone-notification-" .. row.id, text = row.text, width = inner, wrap = true,
        font_size = P.SUB, color = kit.ink("hi") }
    end }

  local page = P.page { id = "phone-page-scroll", width = w, height = h,
    P.empty { id = "phone-missing", width = w, icon = "smartphone", title = "KDE Connect is not installed",
      text = "Install it, pair your phone from its app, and it will show here.",
      visible = function() return not model.present() end },
    P.empty { id = "phone-none", width = w, icon = "smartphone", title = "No phone paired",
      text = function()
        local failed = model.failed:get()
        return failed ~= "" and failed or "Pair one from the KDE Connect app on the phone."
      end,
      visible = function() return model.present() and model.loaded:get() and not has() end },
    P.section { id = "phone-devices", width = w, title = "Phones", visible = has, list },
    P.section { id = "phone-actions", width = w, title = function() local d = shown() return d and d.name or "Phone" end,
      visible = function() return shown() ~= nil end,
      P.row { id = "phone-battery", width = inner, icon = "battery_horiz_075", title = battery_words,
        on = reachable, subtitle = function() return reachable() and "Connected" or "Out of reach" end },
      P.buttons { id = "phone-buttons", width = inner,
        { id = "phone-ring", label = "Find", icon = "ring_volume", enabled = reachable, on_clicked = model.ring },
        { id = "phone-ping", label = "Ping", icon = "notifications_active", enabled = reachable, on_clicked = model.ping },
        { id = "phone-clipboard", label = "Clipboard", icon = "content_paste_go", enabled = reachable, on_clicked = model.send_clipboard },
      },
      kit.text { id = "phone-said", width = inner, font_size = P.SUB, color = kit.ink("lo"), elide = "right",
        text = function() return model.said:get() end, visible = function() return model.said:get() ~= "" end },
    },
    P.section { id = "phone-send", width = w, title = "Send a file",
      visible = function() return shown() ~= nil end,
      P.row { id = "phone-drop-target", width = inner, icon = "upload_file", title = "Drop a file on this page",
        on = function() return hovering:get() end, subtitle = "It goes straight to the phone" },
    },
    P.section { id = "phone-notifications", width = w, title = "Notifications on the phone",
      visible = function() return shown() ~= nil and model.notifications:len() > 0 end, notes },
  }
  local target = ui.DropArea { id = "phone-drop", anchors = { fill = true }, keys = { "files" },
    on_entered = function() hovering:set(true) end, on_exited = function() hovering:set(false) end,
    on_dropped = function(drop) model.share_all(drop.paths) end }
  return ui.Item { id = "phone-page", width = w, height = h, page, target }
end
return M
