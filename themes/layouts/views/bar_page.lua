-- The right panel's Bar page, behind the Bar tile's ">": whether the bar is
-- up (on, off, or up only on a narrow screen), which edge it is on, and how
-- it shows windows. In the page template (themes/layouts/page.lua): each a
-- section of choices that share its width.

local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")

local M = {}

--- A section of choices: `id`, `title`, `group`, the choices
--- ({ key, icon, name }), what is chosen now, and how to choose.
local function choices(w, spec)
  local row = { width = P.inner(w) }
  for _, c in ipairs(spec.items) do
    row[#row + 1] = { id = spec.group .. "-" .. c[1], icon = c[2], label = c[3], group = spec.group,
      selected = function() return spec.now() == c[1] end, on_clicked = function() spec.pick(c[1]) end }
  end
  return P.section { id = spec.group, caption_id = spec.caption_id, width = w, title = spec.title, P.buttons(row) }
end

--- A row with a switch: `id`, `icon`, `name`, what it says, how to set it.
local function toggle(w, id, icon, name, on, set)
  return P.row { id = id, width = P.inner(w), icon = icon, title = name, on = on,
    trailing = P.switch { id = id .. "-switch", name = name, on = on, on_toggled = set } }
end

function M.build(model, w, h)
  local sections = { id = "bar-scroll", width = w, height = h, active = model.active,
    choices(w, { group = "bar-show", caption_id = "bar-heading-show-the-bar", title = "Show the bar",
      items = model.shows, now = model.mode, pick = model.set_mode }),
    choices(w, { group = "bar-side", caption_id = "bar-heading-position", title = "Position",
      items = model.sides, now = model.side, pick = model.set_side }),
    P.section { id = "bar-more", width = w,
      P.row { id = "bar-more-open", width = P.inner(w), icon = "tune", title = "Clock, workspaces, screen shape",
        trailing = P.chevron(), on_clicked = function() require("utilities").request("bar/more") end } },
    choices(w, { group = "bar-titles", caption_id = "bar-heading-window-titles", title = "Window titles",
      items = { { "on", "title", "Shown" }, { "off", "apps", "Icons only" } },
      now = model.titles, pick = model.set_titles }),
  }
  if model.desk then
    sections[#sections + 1] = P.section { id = "bar-desk", caption_id = "bar-heading-desk", width = w, title = "On a desk",
      toggle(w, "bar-tray", "apps", "System tray", model.tray, model.set_tray),
      toggle(w, "bar-wheel-volume-row", "volume_up", "Wheel sets volume", model.wheel_volume, model.set_wheel_volume),
      toggle(w, "bar-wheel-workspace-row", "swap_horiz", "Wheel on clock: workspace", model.wheel_workspace, model.set_wheel_workspace),
    }
  end
  sections[#sections + 1] = kit.subtitle { width = w, wrap = true, font_size = theme.size.small, color = kit.ink("lo"),
    text = "Auto puts the bar up on a phone, a tablet or a narrow screen, and keeps it down on a desk." }
  return P.page(sections)
end

return M
