-- Settings page controllers. Themes receive cached radio models and actions.
-- One model per radio, live while its page shows or the launcher lists it.
local models=require("connectivity_model")
local presentation=require("presentation")
local view=require("themes").view("connectivity")
local M,instances={},{}
local function shared(kind)
  if not instances[kind] then
    local page,mode=presentation.active("settings."..kind),presentation.active("launcher."..kind)
    instances[kind]=models.new(kind,function() return page() or mode() end)
  end
  return instances[kind]
end
M.model=shared
local function page(kind,w,h)
  return view.build(shared(kind),w,h)
end
function M.network_page(w,h) return page("network",w,h) end
function M.bluetooth_page(w,h) return page("bluetooth",w,h) end
function M.mobile_page(w,h)
  return view.build(require("mobile_model").new(presentation.active("settings.mobile")),w,h)
end
function M.networks() return instances.network and instances.network.list() or {} end
function M.devices() return instances.bluetooth and instances.bluetooth.list() or {} end
return M
