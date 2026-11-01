-- The Accessibility page.
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")

local M = {}

function M.build(model, w, h)
  local inner = P.inner(w)
  return P.page { id = "access-scroll", width = w, height = h, active = model.active,
    P.section { id = "access-vision", width = w, title = "Seeing",
      F.note(inner, "Text size"),
      F.choices { id = "access-text", width = inner, items = model.TEXT, now = model.text_scale, pick = model.set_text_scale,
        per_row = 2 },
      F.toggle { id = "access-contrast", width = inner, icon = "contrast", title = "High contrast",
        subtitle = "Text at full strength, plainer surfaces", on = model.contrast, set = model.set_contrast },
      F.toggle { id = "access-reduce", width = inner, icon = "animation", title = "Reduce motion",
        subtitle = "Everything lands at once", on = model.reduce_motion, set = model.set_reduce_motion },
    },
    P.section { id = "access-screen", width = w, title = "The whole screen", visible = model.compositor,
      F.note(inner, "Colour filter"),
      F.choices { id = "access-filter", width = inner, items = model.FILTERS, now = model.filter, pick = model.set_filter,
        per_row = 2 },
      F.slider { id = "access-zoom", width = inner, icon = "zoom_in", name = "Screen magnifier", from = 1, to = 6, step = 0.25,
        value = model.zoom, set = model.set_zoom,
        format = function(v) return v == 1 and "Off" or ("%.2f×"):format(v) end },
      F.note(inner, "The magnifier follows the pointer."),
    },
    P.section { id = "access-keys", width = w, title = "Keys and pointer",
      F.toggle { id = "access-sticky", width = inner, icon = "keyboard_command_key", title = "Sticky keys",
        subtitle = "Press modifiers one after another. Twice locks one.", on = model.sticky, set = model.set_sticky,
        visible = model.can_stick },
      F.note(inner, "Sticky keys need xkbcli, from libxkbcommon.", { id = "access-sticky-missing",
        visible = function() return not model.can_stick() end }),
      F.toggle { id = "access-mouse-keys", width = inner, icon = "mouse", title = "Mouse keys",
        subtitle = "The number pad moves the pointer", on = model.mouse_keys, set = model.set_mouse_keys,
        visible = model.can_mouse_keys },
      F.link { id = "access-repeat", width = inner, icon = "speed", title = "Key repeat", subtitle = "Rate and delay",
        go = function() model.request("input", "accessibility") end },
      F.link { id = "access-cursor", width = inner, icon = "arrow_selector_tool", title = "Cursor size",
        subtitle = "And how fast it moves", go = function() model.request("input/pointer") end },
      F.link { id = "access-osk", width = inner, icon = "keyboard_alt", title = "On-screen keyboard",
        subtitle = "When it comes up", go = function() model.request("osk") end },
    },
    F.status("access-status", w, model),
  }
end

return M
