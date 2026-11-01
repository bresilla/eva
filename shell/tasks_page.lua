local pages=require("pages")
local model=require("tasks_model").new {
  active=pages.active("tasks"),
  close=function() pages.close("tasks") end,
}
local M={edit=model.edit,editing=function() return model.editing:get() end}
function M.build(w,h) return require("themes").view("tasks_page").build(model,w,h) end
return M
