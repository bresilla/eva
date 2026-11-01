-- The Desktop page: which widgets stand on the desktop, what they stand on, and
-- what the ones that take words say. Arranging itself happens on the desktop.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local config = require("config")
local P = require("themes.layouts.page")
local C, S = theme.color, theme.space

local V = {}

local function entry(id, key, placeholder, width, tall)
  local height = tall and P.BUTTON_H * 2 or P.BUTTON_H
  local node, handle = kit.text_field("entry", { id = id, x = S.s, y = S.xs, width = width - 2 * S.s, height = height - 2 * S.xs,
    font_family = theme.font, font_size = theme.size.small, placeholder = placeholder,
    color = function() return C.onSurface end, placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end, selection_color = function() return C.primary:alpha(0.25) end,
    on_text_changed = function(value)
      if tonumber(config.get(key)) and tonumber(value) then config.set(key, tonumber(value))
      elseif type(config.get(key)) == "string" then config.set(key, value) end
    end })
  local box = kit.surface { width = width, height = height, radius = kit.round(S.m),
    color = function() return C.surfaceContainerHighest end, node }
  morf.effect("eva.desktop.field." .. id, function() handle.text = tostring(config.get(key)) end, { owner = box })
  return box
end

local function label(text, width)
  return kit.subtitle { font_size = theme.size.small, color = kit.ink("lo"), text = text, height = S.l, width = width }
end

--- The page at `w` x `h`; `desktop` is shell/desktop_model.lua.
function V.build(desktop, w, h)
  local inner = P.inner(w)
  local board = desktop.board
  local function shown(id) return board.zone_of(id) ~= nil end
  local rows = { id = "desktop-widgets", width = w, title = "Widgets",
    P.buttons { id = "desktop-actions", width = inner,
      { id = "desktop-arrange-button", label = "Arrange", icon = "dashboard_customize",
        on_clicked = function() desktop.set_editing(not desktop.editing()) end },
      { id = "desktop-reset-button", label = "Reset", icon = "restart_alt", on_clicked = function() board.reset() end },
    },
  }
  for _, widget in ipairs(desktop.CATALOGUE) do
    local id = widget.id
    local function on() return shown(id) end
    rows[#rows + 1] = P.row { id = "desktop-row-" .. id, width = inner, icon = widget.icon, title = widget.name, on = on,
      subtitle = function()
        if not on() then return "Not on the desktop" end
        return board.small(id) and "Small" or "Large"
      end,
      trailing = P.switch { id = "desktop-switch-" .. id, name = widget.name, on = on,
        on_toggled = function(now) if now then board.add(id) else board.hide(id) end end } }
  end
  local chrome = { id = "desktop-chrome", width = inner }
  for _, choice in ipairs(desktop.CHROMES) do
    chrome[#chrome + 1] = { id = "desktop-chrome-" .. choice[1], label = choice[2], group = "desktop-chrome",
      selected = function() return config.get("desktop.chrome") == choice[1] end,
      on_clicked = function() config.set("desktop.chrome", choice[1]) end }
  end
  local quiet = function() return config.get("desktop.quiet_clock") end
  local standby = function() return config.get("desktop.standby") end
  local function home_switch(key, icon, title, subtitle)
    local function on() return config.get("desktop.home." .. key) == true end
    return P.row { id = "desktop-home-" .. key, width = inner, icon = icon, title = title, subtitle = subtitle, on = on,
      trailing = P.switch { id = "desktop-home-switch-" .. key, name = title, on = on,
        on_toggled = function(now) config.set("desktop.home." .. key, now == true) end } }
  end
  local columns = { id = "desktop-home-columns", width = inner }
  for _, count in ipairs { { 0, "Auto" }, { 3, "3" }, { 4, "4" }, { 5, "5" }, { 6, "6" } } do
    columns[#columns + 1] = { id = "desktop-home-columns-" .. count[1], label = count[2], group = "desktop-home-columns",
      selected = function() return config.get("desktop.home.columns") == count[1] end,
      on_clicked = function() config.set("desktop.home.columns", count[1]) end }
  end
  return P.page { id = "desktop-page", width = w, height = h,
    P.section { id = "desktop-home", width = w, title = "Home screen",
      home_switch("enabled", "home", "Pages of apps and widgets", "Phone and tablet. Hold the wallpaper to edit"),
      home_switch("dock", "dock_to_bottom", "Dock on a phone", "A row of pinned apps on the home screen"),
      home_switch("labels", "label", "Names under icons"),
      home_switch("locked", "lock", "Lock the layout", "A hold no longer starts arranging"),
      label("Icons across a phone's page", inner),
      P.buttons(columns),
    },
    P.section { id = "desktop-look", width = w, title = "Look",
      label("What widgets stand on", inner),
      P.buttons(chrome),
      P.row { id = "desktop-quiet", width = inner, icon = "center_focus_weak", title = "Clock in the quiet part",
        subtitle = "It moves to the calmest part of the picture", on = quiet,
        trailing = P.switch { id = "desktop-quiet-switch", name = "Clock in the quiet part", on = quiet,
          on_toggled = function(now) config.set("desktop.quiet_clock", now == true) end } },
      P.row { id = "desktop-standby", width = inner, icon = "bedtime", title = "StandBy",
        subtitle = "A phone or tablet on charge, turned sideways, becomes a clock", on = standby,
        trailing = P.switch { id = "desktop-standby-switch", name = "StandBy", on = standby,
          on_toggled = function(now) config.set("desktop.standby", now == true) end } },
    },
    P.section(rows),
    P.section { id = "desktop-words", width = w, title = "Words",
      label("Custom command, run with sh -c", inner),
      entry("desktop-command-run", "desktop.command.run", "uptime -p", inner),
      label("Its title", inner),
      entry("desktop-command-title", "desktop.command.title", "Command", inner),
      label("Every so many seconds", inner),
      entry("desktop-command-interval", "desktop.command.interval", "60", inner),
      label("Note", inner),
      entry("desktop-note-text", "desktop.note", "A note to yourself", inner, true),
      label("Countdown date, YYYY-MM-DD, and what for", inner),
      entry("desktop-countdown-date", "desktop.countdown.date", "2027-01-01", inner),
      entry("desktop-countdown-title", "desktop.countdown.title", "New year", inner),
      label("Quotes file, one to a line", inner),
      entry("desktop-quotes", "desktop.quotes", "~/quotes.txt", inner),
      label("Photo", inner),
      entry("desktop-photo-path", "desktop.photo", "~/Pictures/photo.jpg", inner),
    },
  }
end

return V
