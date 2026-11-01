local morf=require("morf")
local pages=require("pages")
local M={}
function M.build(w,h)
  local active=pages.active("calendar")
  local model=require("calendar_model").new {
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
