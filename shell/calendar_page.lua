local morf=require("morf")
local pages=require("pages")
local M={}
local model
--- Whether an event's form stands on the page.
function M.editing() return model~=nil and model.events.mode:get()~="" end
--- The form for a new event, on `day` or the day on show.
function M.new_event(day) return model~=nil and model.events.create(day) end
function M.build(w,h)
  local active=pages.active("calendar")
  model=require("calendar_model").new {
    active=active,
    can_plan=function() return pages.panel_name("tasks")~=nil end,
    edit=function(task,day)
      if pages.open("tasks") then require("tasks_page").edit(task,day) end
    end,
  }
  local node=require("themes").view("calendar_page").build(model,w,h)
  -- The calendars are read while the page shows, unless reminders keep them.
  morf.effect("eva.calendar.sources",function()
    local on=active()
    morf.time.timer(1,function()
      if not require("calendar_reminders").running() then model.sources.watch(on) end
    end,false)
  end,{owner=node})
  return node
end
return M
