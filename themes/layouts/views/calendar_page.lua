-- A month and the selected day's agenda, in the page template
-- (themes/layouts/page.lua): the month in one card with its buttons, the
-- day's forecast, events and tasks in the next, what comes next and which
-- calendars are read in the last.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local C = theme.color
local M = {}

function M.build(model, w, h)
  local inner = P.inner(w)
  local days, agenda = model.days, model.agenda
  -- The month: the kit's calendar (a day grid the arrows walk, months that
  -- slide), on the model's month and day, a dot on each day with tasks.
  local counts = morf.signal("eva.planner.counts", {})
  local function shown_month()
    for i = 1, days:len() do local day = days:get(i) if day.current then return day.key:sub(1, 7) end end
    return nil
  end
  local month = require("themes.kit.composites").calendar { id = "planner", width = inner, cell_height = 43,
    value = function() return model.selected_day:get() end,
    on_changed = function(day) model.select(day) end,
    month = shown_month,
    on_month = function(_, delta) model.step(delta) end,
    marked = function(day) return (counts:get()[day] or 0) > 0 end }
  morf.effect("eva.planner.counts", function()
    local out = {}
    for i = 1, days:len() do local day = days:get(i) out[day.key] = day.count end
    counts:set(out)
  end, { owner = month })

  -- Today at its label's width, a new event and a task sharing the rest.
  local today = P.button { id = "planner-today", label = "Today", icon = "today", on_clicked = model.today }
  local function share() return (inner - (today.layout_width or 0) - 2 * P.ROW_GAP) / 2 end
  local plan = P.button { id = "planner-add", label = "Task", icon = "add",
    enabled = model.can_plan, width = share, on_clicked = model.plan }
  local add_event = P.button { id = "planner-add-event", label = "Event", icon = "add", tone = "primary",
    width = share, on_clicked = function() model.events.create(model.selected_day:get()) end }

  local function join_button(id, link)
    return P.button { id = id, label = "Join", icon = "videocam", tone = "primary",
      on_clicked = function() model.join(link) end }
  end

  local day = { id = "planner-day", caption_id = "planner-day-title", width = w, title = model.day_title,
    note = function() return tostring(agenda:len()) .. " planned" end,
    ui.Repeater { as = "column", gap = P.ROW_GAP, width = inner, model = agenda,
      delegate = function(item)
        if item.event then
          local parts = {}
          for _, part in ipairs { item.time or "", item.project or "", item.kind or "" } do
            if part ~= "" then parts[#parts + 1] = part end
          end
          return P.row { id = "planner-event-" .. item.uuid, width = inner, icon = "groups",
            title = item.description, subtitle = table.concat(parts, " · "),
            on_clicked = function() model.events.open(item.uid, item.at) end,
            trailing = item.link ~= "" and join_button("planner-join-" .. item.uuid, item.link) or P.chevron() }
        end
        return P.row { id = "planner-task-" .. item.uuid, width = inner, icon = "event",
          title = item.description,
          subtitle = (function()
            local parts = {}
            for _, part in ipairs { item.time or "", item.kind or "", item.project or "" } do
              if part ~= "" then parts[#parts + 1] = part end
            end
            return table.concat(parts, " · ")
          end)(),
          trailing = P.chevron(), on_clicked = function() model.edit(item.uuid) end }
      end },
    P.row { id = "planner-empty", width = inner, icon = "event_available", on = function() return false end,
      title = "Nothing planned yet", subtitle = "Events and tasks show here.",
      visible = function() return agenda:len() == 0 end },
    P.row { id = "planner-weather", width = inner, height = 48,
      icon = function() local f = model.weather() return f and f.symbol or "cloud" end,
      title = function() local f = model.weather() return f and f.words or "" end,
      subtitle = function() local f = model.weather() return f and f.condition or "" end,
      visible = function() return model.weather() ~= nil end },
  }
  local function next_up() return model.next_up() end

  local failure = kit.subtitle { id = "planner-error", width = w, wrap = true, text = function() return model.error:get() end,
    font_size = theme.size.small, color = function() return C.error end }
  failure.visible = function() return (model.error:get() or "") ~= "" end

  local page = P.page { id = "planner-scroll", width = w, height = h, active = model.active,
    P.section { id = "planner-month", width = w,
      month,
      ui.Row { gap = P.ROW_GAP, align = "center", today, add_event, plan },
    },
    P.section(day),
    P.section { id = "planner-work", caption_id = "planner-work-title", width = w, title = "Work calendar",
      P.row { id = "planner-next", width = inner, icon = "schedule", on = function() return next_up() ~= nil end,
        title = function() local n = next_up() return n and n.title or "" end,
        subtitle = function() local n = next_up() return n and n.when or "" end,
        visible = function() return next_up() ~= nil end,
        trailing = P.button { id = "planner-join-next", label = "Join", icon = "videocam", tone = "primary",
          visible = function() local n = next_up() return n ~= nil and n.link ~= "" end,
          on_clicked = function() local n = next_up() if n then model.join(n.link) end end } },
      P.row { id = "planner-work-row", width = inner, icon = "calendar_month", on = model.connected,
        title = function() return model.connected() and model.sources.summary() or "No calendars yet" end,
        subtitle = function()
          return model.connected() and "Files, vdirs and addresses" or "Add a file, a vdir or a URL"
        end,
        trailing = P.chevron(), on_clicked = model.settings },
    },
    failure,
  }
  page.visible = function() return model.events.mode:get() == "" end
  return ui.Item { id = "planner-calendar", width = w, height = h, page,
    require("themes").view("calendar_event").build(model.events, w, h) }
end
return M
