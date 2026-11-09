-- The Calendars settings page: what is read besides Taskwarrior, and how
-- reminders come. Files and folders by path, ICS addresses by URL, and
-- whatever vdirsyncer and khal keep, found by themselves.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local widgets = require("planner_widgets")
local V = {}

local KINDS = { file = "A file", folder = "A folder", found = "Found on this machine", url = "An address" }
local LEADS = { 5, 10, 15, 30 }

--- The page; `model` is shell/calendar_sources.lua.
function V.page(model, w, h)
  local inner = P.inner(w)
  local config = require("config")
  local keeper = ui.Item { width = 1, height = 1 }
  local rows = ui.Repeater { as = "column", gap = P.ROW_GAP, width = inner,
    model = require("themes.layouts.mirror").new(model.sources, "id", keeper),
    delegate = function(row)
      local detail = ("%s · %d events"):format(KINDS[row.kind] or "", row.events or 0)
      if (row.state or "") ~= "" then detail = row.state end
      if (row.locked or "") ~= "" then detail = "Read-only · " .. detail end
      return P.row { id = "calendar-source-" .. tostring(row.id):gsub("[^%w]", "-"), width = inner, icon = "calendar_month",
        title = row.name, subtitle = detail,
        trailing = row.kind ~= "found" and kit.action { width = 32, height = 32, cursor = "pointer",
          accessible_name = "Remove " .. row.name, on_clicked = function() model.remove(row) end,
          kit.icon("close", 18, kit.ink("lo"), { anchors = { center_in = true } }) } or nil }
    end }
  local add_node, add_input
  add_node, add_input = widgets.field("calendar-add", "Add a calendar", "~/work.ics, a folder, or https://…/cal.ics", inner, nil,
    function(text)
      local url = text:match("^%a+://")
      local done = url and model.add_url(text) or (not url and model.add_path(text))
      if done then add_input.text = "" end
    end, nil)
  local leads = { id = "calendar-leads", width = inner }
  for _, minutes in ipairs(LEADS) do
    leads[#leads + 1] = { id = "calendar-lead-" .. minutes, label = minutes .. " min", group = "calendar-lead",
      selected = function() return tonumber(config.get("calendar.lead")) == minutes end,
      on_clicked = function() config.set("calendar.lead", minutes) end }
  end
  local reminders = function() return config.get("calendar.reminders") ~= false end
  local discover = function() return config.get("calendar.discover") ~= false end
  local node = P.page { id = "settings-calendars-scroll", width = w, height = h,
    P.section { id = "calendar-sources", width = w, title = "Your calendars", note = function() return model.summary() end,
      rows,
      kit.text { id = "calendar-none", width = inner, wrap = true, font_size = P.SUB, color = kit.ink("lo"),
        text = "Add a file or an address below; vdirsyncer's and khal's folders appear by themselves",
        visible = function() return model.sources:len() == 0 end },
      add_node,
      kit.text { id = "calendar-said", width = inner, wrap = true, font_size = P.SUB, color = kit.ink("lo"),
        text = function() return model.said:get() end, visible = function() return model.said:get() ~= "" end },
      P.row { id = "calendar-discover", width = inner, icon = "search", title = "Find synced calendars", on = discover,
        subtitle = "vdirsyncer and khal",
        trailing = P.switch { id = "calendar-discover-switch", name = "Find synced calendars", on = discover,
          on_toggled = function(on) config.set("calendar.discover", on) model.watch(true) end } },
    },
    P.section { id = "calendar-reminders", width = w, title = "Reminders",
      P.row { id = "calendar-reminders-row", width = inner, icon = "notifications", title = "Remind me of events", on = reminders,
        subtitle = "At its alarm, or this long before",
        trailing = P.switch { id = "calendar-reminders-switch", name = "Remind me of events", on = reminders,
          on_toggled = function(on) config.set("calendar.reminders", on) end } },
      P.buttons(leads),
    },
    keeper,
  }
  morf.effect("calendars.shown", function()
    local on = require("presentation").active("settings.calendars")()
    if on then morf.time.timer(1, function() model.watch(true) end, false) end
  end, { owner = node })
  return node
end

return V
