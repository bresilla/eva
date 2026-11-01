-- One Taskwarrior connection for the Tasks and Calendar pages.
local morf = require("morf")
local taskwarrior = require("lib.integrations.taskwarrior")
local M = { client = taskwarrior.new() }
M.selected_day = require("themes.session").keep("eva.planner.day", morf.time.format("%Y-%m-%d"))
M.month_offset = require("themes.session").keep("eva.planner.month", 0)
M.dates = taskwarrior

-- It polls while either page is on show, in whichever panel holds it.
local tasks_on, calendar_on = require("pages").active("tasks"), require("pages").active("calendar")
local watching = false
morf.effect("eva.planner.watch", function()
  local on = tasks_on() or calendar_on()
  if on == watching then return end
  watching = on
  -- Started outside the effect's lifetime.
  morf.time.timer(1, function() M.client.watch(on) end, false)
end)

local revision, by_day = -1, {}
function M.agenda(day)
  local now = M.client.revision:get()
  if now ~= revision then
    revision, by_day = now, {}
    for _, task in ipairs(M.client.tasks:get()) do
      local scheduled, due = taskwarrior.day(task.scheduled), taskwarrior.day(task.due)
      local function add(key, value, kind)
        if key == "" then return end
        by_day[key] = by_day[key] or {}
        local list = by_day[key]
        list[#list + 1] = { uuid = task.uuid, description = task.description, project = task.project or "",
          time = taskwarrior.date(value, "%H:%M"), kind = kind }
      end
      add(scheduled, task.scheduled, "Scheduled")
      if due ~= scheduled then add(due, task.due, "Due") end
    end
    for _, list in pairs(by_day) do
      table.sort(list, function(a, b) return a.time == b.time and a.uuid < b.uuid or a.time < b.time end)
    end
  end
  return by_day[day] or {}
end
return M
