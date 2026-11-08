-- Settings page controllers. Themes receive cached radio models and actions.
-- One model per radio, live while its page shows, in the Settings window or
-- the quick controls' panel, or the launcher lists it.
local models=require("connectivity_model")
local presentation=require("presentation")
local view=require("themes").view("connectivity")
local M,instances={},{}
local function shared(kind)
  if not instances[kind] then
    local page,quick,mode=presentation.active("settings."..kind),presentation.active("quick."..kind),
      presentation.active("launcher."..kind)
    instances[kind]=models.new(kind,function() return page() or quick() or mode() end)
  end
  return instances[kind]
end
M.model=shared
-- The radio's page for one host; `shown` (fn): whether that host has it on show.
local function page(kind,w,h,shown)
  return view.build(setmetatable({shown=shown},{__index=shared(kind)}),w,h)
end
function M.network_page(w,h,shown) return page("network",w,h,shown) end
function M.bluetooth_page(w,h,shown) return page("bluetooth",w,h,shown) end
function M.mobile_page(w,h,active)
  return view.build(require("mobile_model").new(active or presentation.active("settings.mobile")),w,h)
end
function M.networks() return instances.network and instances.network.list() or {} end
function M.devices() return instances.bluetooth and instances.bluetooth.list() or {} end
return M
