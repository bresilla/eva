local morf=require("morf")
local M={}
--- The page, in `panel` (the left one, unless one is named), on show while
--- `active()`.
function M.build(w,h,active,panel)
  active=active or require("presentation").active("leftbar.calendar")
  local model=require("calendar_model").new {
    active=active,
    edit=function(task,day)
      local holder=panel or require("leftbar").panel
      if not holder.select("tasks") then require("pages").open("tasks") end
      require("tasks_page").edit(task,day)
    end,
  }
  local node=require("themes").view("calendar_page").build(model,w,h)
  -- The calendars are read while the page shows, unless reminders keep them.
  -- Only the left panel keeps the tasks read by itself.
  local tasks_kept=not panel or panel.id=="leftbar"
  morf.effect("eva.calendar.sources",function()
    local on=active()
    morf.time.timer(1,function()
      if not require("calendar_reminders").running() then model.sources.watch(on) end
      if not tasks_kept then require("planner").client.watch(on) end
    end,false)
  end,{owner=node})
  return node
end
return M
