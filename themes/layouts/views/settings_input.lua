-- The Keyboard, Mouse and touchpad, and Input devices pages. Readings and
-- actions come from shell/input_model.lua.
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")

local M = {}
local NO_HYPRLAND = "These settings are Hyprland's, and it is not running here. Nothing on this page reaches the compositor."

local function absent(model, w)
  return P.section { id = "input-absent", width = w, visible = function() return not model.available() end,
    F.note(P.inner(w), NO_HYPRLAND) }
end

local function keyboard_page(model, w, h)
  local inner = P.inner(w)
  local function count() return #model.layouts() end
  local layouts = F.list(inner, "input-layout-", count, function(index, width)
    local function row() return model.layouts()[index] or {} end
    return P.row { id = "input-layout-row-" .. index, width = width, icon = "keyboard",
      title = function() return row().layout and model.layout_name(row()) or "" end,
      subtitle = function() return index == 1 and "First" or ("Number %d"):format(index) end,
      trailing = ui.Row { gap = theme.space.xs, align = "center",
        P.button { id = "input-layout-up-" .. index, label = "Up", accessible_name = "Move this layout up",
          visible = function() return index > 1 end, on_clicked = function() model.move_layout(index, -1) end },
        P.button { id = "input-layout-remove-" .. index, label = "Remove", accessible_name = "Remove this layout",
          visible = function() return count() > 1 end, on_clicked = function() model.remove_layout(index) end } } }
  end, "Using the compositor's layout", 6)
  local picker = F.picker { id = "input-add", width = inner, placeholder = "Add a layout", max = 6, searched = true,
    items = model.catalogue,
    row = function(item)
      return { icon = "add", title = item.name, subtitle = item.variant ~= "" and item.layout or item.key,
        pick = function() model.add_layout(item) end }
    end }
  return P.page { id = "input-scroll", width = w, height = h, active = model.active,
    absent(model, w),
    P.section { id = "input-layouts", width = w, title = "Layouts",
      F.fact { id = "input-current", width = inner, icon = "language", title = "Typing in",
        subtitle = function() return model.current() ~= "" and model.current() or "The compositor's layout" end,
        trailing = P.button { id = "input-next", label = "Next", icon = "swap_horiz", on_clicked = model.next_layout,
          enabled = function() return count() > 1 end } },
      layouts, picker,
      F.note(inner, "Switch with", { id = "input-switch-title" }),
      F.choices { id = "input-switch", width = inner, items = model.SWITCHES, now = model.switch, pick = model.set_switch,
        per_row = 2 },
    },
    P.section { id = "input-typing", width = w, title = "Typing",
      F.slider { id = "input-repeat-rate", width = inner, icon = "speed", name = "Repeat rate", from = 10, to = 60, step = 1,
        value = function() return model.value("repeat_rate", 25) end, set = function(v) model.set("repeat_rate", v) end,
        format = function(v) return ("%d/s"):format(v) end },
      F.slider { id = "input-repeat-delay", width = inner, icon = "hourglass_top", name = "Repeat delay", from = 150,
        to = 1000, step = 50, value = function() return model.value("repeat_delay", 600) end,
        set = function(v) model.set("repeat_delay", v) end, format = function(v) return ("%d ms"):format(v) end },
      F.toggle { id = "input-numlock", width = inner, icon = "pin", title = "Num Lock at start",
        on = function() return model.value("numlock", false) == true end, set = function(on) model.set("numlock", on) end },
    },
    P.section { id = "input-keys", width = w, title = "Special keys",
      F.note(inner, "Caps Lock acts as"),
      F.choices { id = "input-caps", width = inner, items = model.CAPS, per_row = 2, now = function() return model.value("caps", "") end,
        pick = function(word) model.set("caps", word) end },
      F.note(inner, "Compose key"),
      F.choices { id = "input-compose", width = inner, items = model.COMPOSE, per_row = 2,
        now = function() return model.value("compose", "") end, pick = function(word) model.set("compose", word) end },
      F.link { id = "input-keys-tool", width = inner, icon = "keyboard_command_key", title = "Keyboard shortcuts",
        subtitle = "Every key bound, and a new chord for any", go = model.open_keys, visible = model.can_keys },
    },
    P.section { id = "input-more", width = w, title = "More",
      F.link { id = "input-open-pointer", width = inner, icon = "mouse", title = "Mouse and touchpad",
        subtitle = "Speed, tap to click, cursor", go = function() model.request("input/pointer") end },
      F.link { id = "input-open-devices", width = inner, icon = "devices", title = "Input devices",
        subtitle = "Settings for one device alone", go = function() model.request("input/devices") end },
      F.link { id = "input-open-remap", width = inner, icon = "keyboard_command_key", title = "Key remapping",
        subtitle = "Hyper, tap or hold, for every program", go = function() model.request("input/remap") end,
        visible = function() return not require("responsive").phone() end },
      F.link { id = "input-open-osk", width = inner, icon = "keyboard_alt", title = "On-screen keyboard",
        subtitle = "When it comes up", go = function() model.request("keyboard") end },
    },
    F.status("input-status", w, model),
  }
end

local function pointer_page(model, w, h)
  local inner = P.inner(w)
  local function flag(id, icon, title, option, visible)
    return F.toggle { id = id, width = inner, icon = icon, title = title, visible = visible,
      on = function() return model.value(option, false) == true end, set = function(on) model.set(option, on) end }
  end
  local themes = F.picker { id = "pointer-theme", width = inner, placeholder = "Cursor theme", max = 5,
    items = model.cursor_themes,
    row = function(item)
      return { icon = "mouse", title = item.name, on = model.cursor().theme == item.name,
        pick = function() model.set_cursor(item.name) end }
    end }
  return P.page { id = "pointer-scroll", width = w, height = h, active = model.active,
    absent(model, w),
    P.section { id = "pointer-mouse", width = w, title = "Pointer",
      F.slider { id = "pointer-speed", width = inner, icon = "speed", name = "Pointer speed", from = -1, to = 1, step = 0.05,
        value = function() return model.value("sensitivity", 0) end, set = function(v) model.set("sensitivity", v) end,
        format = function(v) return ("%+.2f"):format(v) end },
      F.note(inner, "Acceleration"),
      F.choices { id = "pointer-accel", width = inner, items = model.ACCEL,
        now = function() return model.value("accel_profile", "") end,
        pick = function(word) model.set("accel_profile", word) end },
      F.slider { id = "pointer-scroll-speed", width = inner, icon = "swap_vert", name = "Scroll speed", from = 0.25, to = 3,
        step = 0.25, value = function() return model.value("scroll_factor", 1) end,
        set = function(v) model.set("scroll_factor", v) end, format = function(v) return ("%.2f×"):format(v) end },
      flag("pointer-natural", "swipe_vertical", "Natural scrolling", "natural_scroll"),
      flag("pointer-left", "back_hand", "Left-handed", "left_handed"),
    },
    P.section { id = "pointer-touchpad", width = w, title = "Touchpad", visible = model.touchpad,
      flag("pointer-tap", "touch_app", "Tap to click", "tap_to_click"),
      flag("pointer-pad-natural", "swipe_vertical", "Natural scrolling", "touchpad_natural"),
      flag("pointer-dwt", "keyboard", "Off while typing", "disable_while_typing"),
      flag("pointer-clickfinger", "ads_click", "Two-finger right click", "clickfinger"),
      flag("pointer-drag-lock", "drag_pan", "Drag lock", "drag_lock"),
      F.slider { id = "pointer-pad-scroll", width = inner, icon = "swap_vert", name = "Scroll speed", from = 0.25, to = 3,
        step = 0.25, value = function() return model.value("touchpad_scroll", 1) end,
        set = function(v) model.set("touchpad_scroll", v) end, format = function(v) return ("%.2f×"):format(v) end },
    },
    P.section { id = "pointer-cursor", width = w, title = "Cursor",
      F.slider { id = "pointer-size", width = inner, icon = "arrow_selector_tool", name = "Cursor size", from = 16, to = 64,
        step = 4, value = function() return model.cursor().size end, set = function(v) model.set_cursor(nil, v) end,
        format = function(v) return ("%d px"):format(v) end },
      F.slider { id = "pointer-hide", width = inner, icon = "visibility_off", name = "Hide after", from = 0, to = 30, step = 1,
        value = function() return model.value("cursor_timeout", 0) end, set = function(v) model.set("cursor_timeout", v) end,
        format = function(v) return v == 0 and "Never" or ("%d s"):format(v) end },
      themes,
    },
    F.status("pointer-status", w, model),
  }
end

local function devices_page(model, w, h)
  local inner = P.inner(w)
  local function chosen() return model.selected:get() end
  local function picked() return chosen() ~= "" end
  local list = F.list(inner, "device-row-", function() return #model.devices() end, function(index, width)
    local function row() return model.devices()[index] or {} end
    return P.row { id = "device-" .. index, width = width, icon = function() return row().icon or "devices" end,
      title = function() return row().name or "" end, subtitle = function() return row().kind or "" end,
      on = function() return row().key == chosen() end,
      on_clicked = function() model.selected:set(row().key or "") end }
  end, "No input devices reported", 16)
  local function value(field, otherwise) return function() return model.device_value(chosen(), field, otherwise) end end
  local function store(field) return function(v) model.set_device(chosen(), field, v) end end
  return P.page { id = "devices-scroll", width = w, height = h, active = model.active,
    absent(model, w),
    P.section { id = "devices-list", width = w, title = "Devices", list },
    P.section { id = "devices-one", width = w, title = "This device", visible = picked,
      F.fact { id = "devices-name", width = inner, icon = "tune", title = chosen, subtitle = "Overrides the general settings" },
      F.toggle { id = "devices-enabled", width = inner, icon = "power_settings_new", title = "Use this device",
        on = value("enabled", true), set = store("enabled") },
      F.slider { id = "devices-speed", width = inner, icon = "speed", name = "Speed", from = -1, to = 1, step = 0.05,
        value = value("sensitivity", 0), set = store("sensitivity"), format = function(v) return ("%+.2f"):format(v) end },
      F.toggle { id = "devices-natural", width = inner, icon = "swipe_vertical", title = "Natural scrolling",
        on = value("natural_scroll", false), set = store("natural_scroll") },
      F.toggle { id = "devices-left", width = inner, icon = "back_hand", title = "Left-handed",
        on = value("left_handed", false), set = store("left_handed") },
      P.button { id = "devices-reset", label = "Back to general settings",
        on_clicked = function() model.forget_device(chosen()) end },
    },
    F.status("devices-status", w, model),
  }
end

function M.build(model, w, h)
  if model.key == "input/pointer" then return pointer_page(model, w, h) end
  if model.key == "input/devices" then return devices_page(model, w, h) end
  return keyboard_page(model, w, h)
end

return M
