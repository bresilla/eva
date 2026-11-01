-- One calendar event, in the page template: Back and Save at the top, then
-- what it is, when, how it repeats and reminds, and which calendar holds it.
-- An event whose calendar cannot be written shows the same facts, and why.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local widgets = require("planner_widgets")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local C = theme.color
local M = {}

local TIME_W, PICK_W = 92, 40

local function get(v) if type(v) == "function" then return v() end return v end

function M.build(model, w, h)
  local inner = P.inner(w)
  local inputs = {}
  local function open() return model.mode:get() ~= "" end
  local function editing() return model.mode:get() == "new" or model.mode:get() == "edit" end
  local function reading() return model.mode:get() == "read" end
  local function timed() return not model.draft.all_day end
  local function whole() return editing() and not model.single() end

  local function field(name, label, placeholder, width)
    local node, input = widgets.field("event-" .. name, label, placeholder, width,
      function(value) model.set(name, value) end, nil, model.close)
    inputs[name] = input
    return node
  end

  -- A date is typed or picked; a time stands beside it while the event has one.
  local function moment(day_name, time_name, label)
    local pickers = require("themes.kit.composites")
    local day_w = inner - TIME_W - PICK_W - 2 * theme.space.s
    local day = field(day_name, label, "2026-11-01", day_w)
    local picker = pickers.date_picker { id = "event-" .. day_name .. "-date", compact = true, width = PICK_W, height = PICK_W,
      placement = "bottom-start", accessible_name = "Choose the " .. label:lower(),
      value = function() return (model.draft[day_name] or ""):sub(1, 10) end,
      on_changed = function(date)
        inputs[day_name].text = date
        model.set(day_name, date)
      end }
    local clock = field(time_name, "Time", "9:30", TIME_W)
    clock.visible = timed
    return ui.Row { gap = theme.space.s, align = "end", day, picker, clock }
  end
  local last_day = field("until_day", "Last day, if it has one", "2026-12-31", inner)
  last_day.visible = function() return model.draft.repeats ~= "none" and not model.custom() end

  local what = P.section { id = "event-what", caption_id = "event-title", width = w, visible = editing,
    title = function() return model.mode:get() == "new" and "New event" or "Edit event" end,
    field("summary", "Name", "What is happening?", inner),
    field("location", "Where", "A room, or a link", inner),
    field("description", "Notes", "Anything else", inner),
  }

  local when = P.section { id = "event-when", width = w, title = "When", visible = editing,
    F.choices { id = "event-scope", width = inner, items = model.SCOPES, per_row = 2,
      visible = function() return model.repeating:get() end,
      now = function() return model.draft.scope end, pick = function(key) model.set("scope", key) end },
    F.toggle { id = "event-all-day", width = inner, icon = "wb_sunny", title = "All day",
      on = function() return model.draft.all_day == true end, set = function(on) model.set("all_day", on == true) end },
    moment("from_day", "from_time", "Starts"),
    moment("to_day", "to_time", "Ends"),
  }

  local repeats = P.section { id = "event-repeat", width = w, title = "Repeat", visible = whole,
    F.choices { id = "event-repeats", width = inner, items = model.REPEATS, per_row = 3,
      now = function() return model.draft.repeats end, pick = function(key) model.set("repeats", key) end },
    F.note(inner, "This one repeats by a rule of its own. It stays as it is unless you pick another here.",
      { id = "event-custom-rule", visible = model.custom }),
    last_day,
  }

  local reminder = P.section { id = "event-reminder", width = w, title = "Reminder", visible = editing,
    F.choices { id = "event-reminders", width = inner, items = model.REMINDERS, per_row = 3,
      visible = timed, now = function() return model.draft.reminder end, pick = function(key) model.set("reminder", key) end },
    F.choices { id = "event-day-reminders", width = inner, items = model.DAY_REMINDERS, per_row = 3,
      visible = function() return not timed() end, now = function() return model.draft.reminder end,
      pick = function(key) model.set("reminder", key) end },
    F.note(inner, "Default is the time set in Settings, under Calendars.", { visible = timed }),
  }

  -- Which calendar a new event goes in. It stays there: moving is not offered.
  local MAX_CALENDARS = 6
  local calendars = { id = "event-calendar", width = w, title = "Calendar",
    visible = function() return editing() end }
  local function calendar_at(index) return model.calendars()[index] end
  for index = 1, MAX_CALENDARS do
    calendars[#calendars + 1] = P.row { id = "event-calendar-" .. index, width = inner, icon = "calendar_month",
      visible = function() return model.mode:get() == "new" and calendar_at(index) ~= nil end,
      on = function() local row = calendar_at(index) return row ~= nil and model.draft.calendar == row.id end,
      title = function() local row = calendar_at(index) return row and row.name or "" end,
      subtitle = function() local row = calendar_at(index) return row and M.sync_note(row.kind) or "" end,
      on_clicked = function() local row = calendar_at(index) if row then model.set("calendar", row.id) end end }
  end
  calendars[#calendars + 1] = F.fact { id = "event-calendar-new", width = inner, icon = "calendar_month", title = "A new calendar here",
    subtitle = "Nothing here can be written yet, so this makes one on this machine",
    visible = function() return model.mode:get() == "new" and calendar_at(1) == nil end }
  calendars[#calendars + 1] = F.fact { id = "event-calendar-held", width = inner, icon = "calendar_month",
    title = function() return model.calendar_name:get() end, subtitle = "This calendar keeps it",
    visible = function() return model.mode:get() == "edit" end }

  local actions = P.buttons { width = w,
    { id = "event-delete", icon = "delete",
      label = function()
        if model.deleting:get() then return "Press again to delete" end
        return model.single() and "Delete this one" or "Delete"
      end,
      on_clicked = model.delete },
  }
  actions.visible = function() return model.mode:get() == "edit" end

  -- What a calendar that cannot be written shows.
  local details = P.section { id = "event-details", caption_id = "event-details-title", width = w, visible = reading,
    title = function() return model.draft.summary end,
    F.fact { id = "event-details-when", width = inner, icon = "schedule", title = "When", subtitle = model.when },
    F.fact { id = "event-details-where", width = inner, icon = "location_on", title = "Where",
      visible = function() return (model.draft.location or "") ~= "" end, subtitle = function() return model.draft.location end },
    F.fact { id = "event-details-calendar", width = inner, icon = "calendar_month", title = "Calendar",
      subtitle = function() return model.calendar_name:get() end },
    F.note(inner, function() return model.draft.description end,
      { id = "event-details-notes", visible = function() return (model.draft.description or "") ~= "" end }),
    F.note(inner, function() return "Read-only. " .. model.locked_why:get() end, { id = "event-details-locked" }),
  }

  local failure = F.note(w, function() return model.error:get() end, { id = "event-error",
    visible = function() return model.error:get() ~= "" end, color = function() return C.error end })

  local save = P.button { id = "event-save", label = "Save event", icon = "check", tone = "primary", visible = editing,
    on_clicked = model.save }
  local bar = ui.Item { width = w, height = P.BUTTON_H,
    P.button { id = "event-back", label = "Back", icon = "arrow_back", on_clicked = model.close },
    ui.Item { anchors = { right = true }, width = function() return save.width end, height = P.BUTTON_H, save } }
  local body_h = function() return get(h) - P.BUTTON_H - P.GAP end
  local root = ui.Item { id = "event-form", width = w, height = h, visible = open,
    bar,
    ui.Item { y = P.BUTTON_H + P.GAP, width = w, height = body_h,
      P.page { id = "event-scroll", width = w, height = body_h, active = open,
        failure, what, details, when, repeats, reminder, P.section(calendars), actions } },
  }
  local shown
  morf.effect("calendar.event.fill", function()
    local revision = model.revision:get()
    if revision == shown then return end
    shown = revision
    for name, input in pairs(inputs) do input.text = tostring(model.draft[name] or "") end
  end, { owner = root })
  morf.effect("calendar.event.focus", function()
    model.revision:get()
    inputs.summary.focus = model.mode:get() == "new"
  end, { owner = root })
  return root
end

--- What a calendar's kind means for a change made here.
function M.sync_note(kind)
  if kind == "found" then return "Reaches the server at the next vdirsyncer sync" end
  if kind == "folder" then return "Written to its folder" end
  return "Written to its file"
end

return M
