local morf=require("morf")
local M={}
function M.build(w,h)
  local active=require("presentation").active("leftbar.calendar")
  local model=require("calendar_model").new {
    active=active,
    edit=function(task,day)
      require("leftbar").panel.select("tasks") require("tasks_page").edit(task,day)
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
