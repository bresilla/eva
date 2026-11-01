local pages=require("pages")
local M={}
function M.build(w,h)
  local model=require("calendar_model").new {
    active=pages.active("calendar"),
    can_plan=function() return pages.panel_name("tasks")~=nil end,
    edit=function(task,day)
      if pages.open("tasks") then require("tasks_page").edit(task,day) end
    end,
  }
  return require("themes").view("calendar_page").build(model,w,h)
end
return M
