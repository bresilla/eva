-- The right panel's Power page, behind the battery row's ">": everything
-- about power in one place -- the battery (charge, state, time left, draw),
-- the power profile, the battery's health and how it is charged, and the way
-- to the dashboard's Battery tab for its graphs. In the page template
-- (themes/layouts/page.lua).

local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")

local M = {}

function M.build(model, w, h)
  local first = model.battery
  local inner = P.inner(w)
  local function active()
    local value = model.profile()
    return value == "" and "balanced" or value
  end

  -- The battery: its charge large, its state and what that means in time,
  -- and the charge as the theme's fill bar, the charge limit marked on it.
  local summary = P.section { id = "power-summary", width = w, title = "Charge",
    ui.Item { width = inner, height = 96,
      kit.icon(function()
        local b = first()
        if not model.present() then return "power" end
        if b.status == "Charging" then return "battery_charging_full" end
        local pct = b.capacity or 0
        if pct > 90 then return "battery_full" end
        if pct > 50 then return "battery_5_bar" end
        if pct > 20 then return "battery_3_bar" end
        return "battery_alert"
      end, 40, kit.ink("accent"), { x = 0, y = 8, fill = true }),
      kit.text {
        id = "power-percent", x = 52, y = 0, font_size = theme.size.extra, font_weight = 700,
        text = function()
          if not model.present() then return "Mains power" end
          return ("%d%%"):format(math.floor((first().capacity or 0) + 0.5))
        end,
      },
      kit.subtitle { x = 52, y = 44, width = inner - 52, elide = "right", color = kit.ink("lo"),
        text = model.summary },
      ui.Item {
        y = 80, width = inner, height = 12, visible = model.present,
        kit.fill { width = inner, height = 12, color = kit.signal("accent"),
          value = function() return math.max(0, math.min(1, (first().capacity or 0) / 100)) end },
        kit.surface {
          width = 2, height = 12,
          x = function() return inner * (first().charge_limit or 100) / 100 - 1 end,
          visible = function() local l = first().charge_limit return l ~= nil and l < 100 end,
          color = kit.ink("hi"),
        },
      },
    },
  }

  -- The power profile: three choices, and what the chosen one is for.
  local choices = { width = inner }
  for _, p in ipairs(model.PROFILES) do
    choices[#choices + 1] = { id = "power-profile-" .. p.id, icon = p.icon, label = p.name, group = "power-profile",
      selected = function() return active() == p.id end, on_clicked = function() model.select(p.id) end,
      enabled = function() return model.supports(p.id) end }
  end
  local function hint()
    for _, p in ipairs(model.PROFILES) do if p.id == active() then return p.hint end end
    return ""
  end
  local profile = P.section { id = "power-profiles", caption_id = "power-heading-power-mode", width = w,
    title = "Power mode",
    P.buttons(choices),
    kit.subtitle { id = "power-profile-note", width = inner, wrap = true, font_size = theme.size.small,
      color = kit.ink("lo"),
      text = function()
        local note = model.profile_note and model.profile_note()
        if note and note ~= "Choose how the system balances energy and speed." then return note end
        local message = model.message and model.message:get() or ""
        if message ~= "" then return message end
        return hint()
      end },
  }

  -- What is charging it, how fast and for how long, and where it stops: a
  -- limit of the person's where the kernel lets this session set one.
  local charge = model.charge
  local function route(kind) return function() return charge.route() == kind end end
  local by_file = route("file")
  local function limit() return charge.limit(first().charge_limit) end
  local function limit_on() return charge.on(first().charge_limit) end
  local function adaptive_on() return charge.adaptive() end
  local function can_adapt() return by_file() and limit() > charge.HOLD end
  local function mark(key, spec)
    local chip = kit.chip(spec)
    chip.visible = function() return model.charging() and model.feed()[key] == true end
    return chip
  end
  local marks = ui.Row { gap = theme.space.xs, align = "center",
    mark("fast", { id = "power-mark-fast", text = "Fast", filled = true }),
    mark("wireless", { id = "power-mark-wireless", text = "Wireless" }),
    mark("slow", { id = "power-mark-slow", text = "Slow", color = kit.signal("warn") }),
  }
  local limit_slider = kit.slider { id = "power-limit", accessible_name = "Charge limit", width = inner, icon = "battery_saver",
    value = function() return (limit() - charge.LOWEST) / (100 - charge.LOWEST) end,
    set = function(value) charge.set_limit(charge.LOWEST + value * (100 - charge.LOWEST)) end,
    reading = function(value)
      local level = charge.LOWEST + value * (100 - charge.LOWEST)
      return ("%d%%"):format(math.floor(level / charge.STEP + 0.5) * charge.STEP)
    end }
  limit_slider.visible = function() return by_file() and limit_on() end
  local charging = P.section { id = "power-charging", caption_id = "power-heading-charging", width = w, title = "Charging",
    visible = model.charging_shown,
    P.row { id = "power-charger", width = inner, icon = model.charger_icon, on = model.charging,
      title = model.charge_title, subtitle = model.charge_detail, trailing = marks },
    kit.subtitle { id = "power-charger-note", width = inner, wrap = true, font_size = theme.size.small, color = kit.ink("lo"),
      visible = function() return model.charge_hint() ~= "" end, text = model.charge_hint },
    P.row { id = "power-limit-state", width = inner, icon = "battery_saver", on = limit_on, title = "Charge limit",
      visible = function() return by_file() or route("upower")() end,
      subtitle = function()
        if not limit_on() then return "Charges to full" end
        if by_file() then return ("Stops at %d%%"):format(limit()) end
        return "Held by UPower"
      end,
      trailing = P.switch { id = "power-limit-switch", name = "Charge limit", on = limit_on, on_toggled = charge.set_on } },
    limit_slider,
    P.row { id = "power-adaptive", width = inner, icon = "schedule", on = adaptive_on, title = "Adaptive charging",
      visible = can_adapt,
      subtitle = function()
        return adaptive_on() and ("Waits at %d%%, done by %s"):format(charge.HOLD, charge.ready_text()) or "Off"
      end,
      trailing = P.switch { id = "power-adaptive-switch", name = "Adaptive charging", on = adaptive_on,
        on_toggled = charge.set_adaptive } },
    P.buttons { id = "power-ready", width = inner,
      { id = "power-ready-earlier", icon = "remove", accessible_name = "Earlier", visible = function() return can_adapt() and adaptive_on() end,
        on_clicked = function() charge.step_ready(-charge.READY_STEP) end },
      { id = "power-ready-time", label = charge.ready_text, visible = function() return can_adapt() and adaptive_on() end },
      { id = "power-ready-later", icon = "add", accessible_name = "Later", visible = function() return can_adapt() and adaptive_on() end,
        on_clicked = function() charge.step_ready(charge.READY_STEP) end },
    },
    kit.subtitle { id = "power-limit-note", width = inner, wrap = true, font_size = theme.size.small, color = kit.ink("lo"),
      visible = function() return charge.note() ~= "" or charge.message:get() ~= "" end,
      text = function()
        local said = charge.message:get()
        return said ~= "" and said or charge.note()
      end },
  }

  -- The battery's health, and how it is charged -- set by the firmware
  -- (and root), shown here; its graphs are the dashboard's.
  local rows = {}
  for _, entry in ipairs(model.FACTS) do rows[#rows + 1] = { entry.name, entry.value } end
  local health = P.section { id = "power-health", caption_id = "power-heading-battery", width = w, title = "Battery",
    visible = model.present,
    P.row { id = "power-limit", width = inner, icon = "battery_saver", on = model.limit_on,
      title = "Charge limit", subtitle = model.limit_note, visible = model.limit_supported,
      trailing = P.switch { id = "power-limit-switch", name = "Charge limit", on = model.limit_on,
        on_toggled = function(now) model.set_limit(now) end } },
    kit.facts(rows, inner, 30),
    P.buttons { width = inner,
      { id = "power-open-battery", icon = "monitoring", label = "Battery graphs and details",
        on_clicked = model.open_battery } },
  }

  -- The lid and the power button: the shell's choice while it runs, what
  -- logind does otherwise.
  local function action_block(key, title, field)
    return ui.Column { width = inner, gap = P.ROW_GAP,
      F.note(inner, function()
        local logind = model.logind_action(field)
        return title .. (logind and ("  (the system: " .. logind .. ")") or "")
      end),
      F.choices { id = "power-" .. key, width = inner, items = model.ACTIONS, per_row = 2,
        now = function() return model.action_of(key) end, pick = function(value) model.set_action(key, value) end },
    }
  end
  local buttons = P.section { id = "power-actions", caption_id = "power-heading-actions", width = w, title = "Lid and power button",
    (function()
      local block = action_block("lid_battery", "Closing the lid on battery", "HandleLidSwitch")
      block.visible = model.lid_present
      return block
    end)(),
    (function()
      local block = action_block("lid_ac", "Closing the lid plugged in", "HandleLidSwitchExternalPower")
      block.visible = model.lid_present
      return block
    end)(),
    action_block("button", "Pressing the power button", "HandlePowerKey"),
    F.note(inner, "System leaves it to logind, as the system configuration says. Anything else wins over that configuration while the shell runs; at the login screen logind decides."),
  }

  local graphics = { id = "power-gpu", caption_id = "power-heading-gpu", width = w, title = "Graphics",
    visible = function() return model.gpu().tool ~= "" end }
  for slot = 1, 4 do
    local function row() return model.gpu().modes[slot] end
    graphics[#graphics + 1] = P.row { id = "power-gpu-" .. slot, width = inner, visible = function() return row() ~= nil end,
      icon = function() return (row() or {}).key == model.gpu().mode and "radio_button_checked" or "radio_button_unchecked" end,
      on = function() return (row() or {}).key == model.gpu().mode end,
      title = function() return (row() or {}).name or "" end, subtitle = function() return (row() or {}).hint or "" end,
      on_clicked = function() if row() then model.set_gpu(row()) end end }
  end

  local sleep = P.section { id = "power-sleep", width = w, title = "Sleep", visible = function() return model.open_idle ~= nil end,
    P.row { id = "power-idle", width = inner, icon = "bedtime", title = "Idle and sleep",
      subtitle = "When the screen turns off, locks and sleeps", trailing = P.chevron(),
      on_clicked = function() model.open_idle() end } }

  return P.page { id = "power-scroll", width = w, height = h, active = model.active, summary, charging, profile, sleep, health,
    buttons, P.section(graphics), F.status("power-status", w, { message = model.note, failed = model.failed }) }
end

return M
