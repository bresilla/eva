local models=require("net_pages_model")
local presentation=require("presentation")
local view=require("themes").view("net_pages")
local M={is_mesh_link=models.is_mesh_link}
local instances={}
--- The one model of `kind`, live while its page shows, in the Settings window
--- or the quick controls' panel, or the launcher lists it.
function M.model(kind)
  if not instances[kind] then
    local page,quick,mode=presentation.active("settings."..kind),presentation.active("quick."..kind),
      presentation.active("launcher."..kind)
    instances[kind]=models.new(kind,function() return page() or quick() or mode() end)
  end
  return instances[kind]
end
local function page(kind,w,h)
  return view.build(M.model(kind),w,h)
end
function M.wired_page(w,h) return page("wired",w,h) end
function M.vpn_page(kind,w,h) return page(kind,w,h) end
function M.tor_page(w,h) return page("tor",w,h) end
return M
