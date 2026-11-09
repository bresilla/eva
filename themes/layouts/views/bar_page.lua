-- The right panel's Bar page, behind the Bar tile's ">": whether the bar is up
-- (on, off, or up only on a narrow screen), which edge it is on, how it shows
-- windows, its clock, the board of its modules, and what each screen does. In the
-- page template (themes/layouts/page.lua): each a section of choices that share
-- its width.

local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local L = require("themes.layouts.parts")
local P = require("themes.layouts.page")
local S = theme.space

local M = {}

--- A section of choices: `id`, `title`, `group`, the choices
--- ({ key, icon, name }), what is chosen now, how to choose, and a `note`.
local function choices(w, spec)
  local row = { width = P.inner(w) }
  for _, c in ipairs(spec.items) do
    row[#row + 1] = { id = spec.group .. "-" .. c[1], icon = c[2], label = c[3], group = spec.group,
      selected = function() return spec.now() == c[1] end, on_clicked = function() spec.pick(c[1]) end }
  end
  return P.section { id = spec.group, caption_id = spec.caption_id, width = w, title = spec.title, P.buttons(row),
    spec.note and require("themes.layouts.form").note(P.inner(w), spec.note) or nil }
end

--- A row with a switch: `id`, `icon`, `name`, what it says, how to set it.
local function toggle(w, id, icon, name, on, set)
  return P.row { id = id, width = P.inner(w), icon = icon, title = name, on = on,
    trailing = P.switch { id = id .. "-switch", name = name, on = on, on_toggled = set } }
end

--- What one screen does: the bar up, as set or its own way, and its own modules.
local function screen(w, model, name)
  local tag = name:gsub("%W", "-")
  return choices(w, { group = "bar-screen-" .. tag, caption_id = "bar-heading-screen-" .. tag, title = name,
    items = model.screen_shows, now = function() return model.output_on(name) end,
    pick = function(value) model.set_output_on(name, value) end }),
    toggle(w, "bar-screen-own-" .. tag, "view_module", "Its own modules on " .. name,
      function() return model.output_own(name) end, function(on) model.set_output_own(name, on) end)
end

--- The tray's page: each item's place and order, and how many stand on the bar.
function M.build_tray(model, w, h)
  local F = require("themes.layouts.form")
  local inner = P.inner(w)
  local function row(index, width)
    local function item() return model.tray_items()[index] or {} end
    local function arrow(key, icon, name, by)
      return kit.action { id = "tray-row-" .. index .. "-" .. key, width = S.xxl, height = S.TARGET, cursor = "pointer",
        accessible_name = name, on_clicked = function() model.tray_move(item().id, by) end,
        kit.icon(icon, 20, kit.ink("lo"), { anchors = { center_in = true } }) }
    end
    return P.row { id = "tray-row-" .. index, width = width, icon = "apps", title = function() return item().title or "" end,
      subtitle = function() return item().here and "Running now" or "Not running" end,
      on = function() return item().here == true end,
      trailing = ui.Row { gap = S.xs, align = "center",
        P.button { id = "tray-row-" .. index .. "-place", width = 120, label = function() return model.tray_place_name(item().place) end,
          on_clicked = function() model.tray_next_place(item().id) end },
        arrow("up", "arrow_upward", "Earlier", -1), arrow("down", "arrow_downward", "Later", 1) } }
  end
  return P.page { id = "bar-tray-scroll", width = w, height = h, active = model.active,
    P.section { id = "bar-tray-items", width = w,
      F.list(inner, "tray-item-", function() return #model.tray_items() end, row, "Nothing is in the tray", 24),
      F.note(inner, "Tucked away keeps an item behind the arrow, hidden keeps it off the bar altogether. What does not fit on the bar goes behind the arrow too.") },
    P.section { id = "bar-tray-limit", caption_id = "bar-tray-limit-caption", width = w, title = "On the bar",
      F.slider { id = "bar-tray-limit-slider", width = inner, icon = "more_horiz", name = "Icons at most", from = 1, to = 16, step = 1,
        value = model.tray_limit, set = model.set_tray_limit, format = function(value) return ("%d"):format(value) end } } }
end

function M.build(model, w, h)
  local sections = { id = "bar-scroll", width = w, height = h, active = model.active,
    choices(w, { group = "bar-show", caption_id = "bar-heading-show-the-bar", title = "Show the bar",
      items = model.shows, now = model.mode, pick = model.set_mode,
      note = "Auto puts the bar up on a phone or a narrow screen, and keeps it down on a desk." }),
    choices(w, { group = "bar-side", caption_id = "bar-heading-position", title = "Position",
      items = model.sides, now = model.side, pick = model.set_side }),
    P.section { id = "bar-more", width = w,
      P.row { id = "bar-more-open", width = P.inner(w), icon = "rounded_corner", title = "Screen shape",
        subtitle = "Rounded corners and a cutout",
        trailing = P.chevron(), on_clicked = function() require("utilities").request("bar/more") end } },
    choices(w, { group = "bar-titles", caption_id = "bar-heading-window-titles", title = "Window titles",
      items = { { "on", "title", "Shown" }, { "off", "apps", "Icons only" } },
      now = model.titles, pick = model.set_titles }),
    P.section { id = "bar-fold", width = w,
      P.row { id = "bar-fold-open", width = P.inner(w), icon = "more_horiz", title = "When the bar is full",
        subtitle = "What folds first, and what never shows",
        trailing = P.chevron(), on_clicked = function() require("utilities").request("bar/fold") end } },
    P.section { id = "bar-clock-settings", caption_id = "bar-heading-clock", width = w, title = "Clock",
      toggle(w, "bar-clock-seconds", "timer", "Seconds", model.seconds, model.set_seconds),
    },
    P.section { id = "bar-date", caption_id = "bar-heading-date", width = w, title = "Date beside the clock",
      require("themes.layouts.form").choices { id = "bar-date", width = P.inner(w), items = model.dates, per_row = 3,
        now = model.date, pick = model.set_date } },
    choices(w, { group = "bar-height", caption_id = "bar-heading-height", title = "Height",
      items = model.heights, now = model.height, pick = model.set_height }),
    P.section { id = "bar-status-settings", caption_id = "bar-heading-status", width = w, title = "Status",
      toggle(w, "bar-percent", "percent", "Battery percentage", model.percent, model.set_percent) },
  }
  local bar = model.bar_model()
  if bar then
    local board = require("themes").view("bar_board").build({ board = bar.board, items = bar.modules }, w)
    sections[#sections + 1] = ui.Column { id = "bar-arrange", width = w, gap = P.GAP / 2,
      L.caption { id = "bar-heading-modules", width = w, text = "Modules" }, board.node }
  end
  if model.desk then
    sections[#sections + 1] = P.section { id = "bar-desk", caption_id = "bar-heading-desk", width = w, title = "On a desk",
      toggle(w, "bar-tray", "apps", "System tray", model.tray, model.set_tray),
      P.row { id = "bar-tray-open", width = P.inner(w), icon = "tune", title = "Tray items", subtitle = "Hide, order, tuck away",
        trailing = P.chevron(), on_clicked = function() require("utilities").request("bar/tray") end },
      toggle(w, "bar-wheel-volume-row", "volume_up", "Wheel sets volume", model.wheel_volume, model.set_wheel_volume),
      toggle(w, "bar-wheel-workspace-row", "swap_horiz", "Wheel on clock: workspace", model.wheel_workspace, model.set_wheel_workspace),
    }
  end
  local details = { id = "bar-details", caption_id = "bar-heading-details", width = w, title = "Module details" }
  for _, row in ipairs(model.details) do
    local inner = P.inner(w)
    local tag = row.key:gsub("%W", "-")
    local box, handle = require("themes").view("quick_pages").field("bar-detail-" .. tag, inner, row.hint, "entry",
      function(value) model.set_detail(row.key, value) end, function() end)
    handle.text = model.detail(row.key)
    details[#details + 1] = ui.Column { width = inner, gap = S.xxs,
      kit.subtitle { width = inner, font_size = P.SUB, color = kit.ink("lo"), text = row.title }, box }
  end
  sections[#sections + 1] = P.section(details)
  for _, name in ipairs(model.outputs()) do
    local choose, own = screen(w, model, name)
    sections[#sections + 1] = choose
    sections[#sections + 1] = P.section { id = "bar-screen-" .. name:gsub("%W", "-") .. "-own", width = w, own }
  end
  return P.page(sections)
end

return M
