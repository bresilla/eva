-- View selected by the visual theme; services and models stay shared.
local M={}
function M.page(w,h)
  local model=require("bar_settings_model").new(require("presentation").active("settings.bar"))
  return require("themes").view("bar_page").build(model,w,h)
end
function M.tray_page(w,h)
  local model=require("bar_settings_model").new(require("presentation").active("settings.bar/tray"))
  return require("themes").view("bar_page").build_tray(model,w,h)
end
return M
