-- Settings lifecycle and detail builders; the selected theme owns all layout.
-- A builder is given the host it builds in, the Settings window's model or the
-- panel's (shell/quick_details.lua), for what is on show and where links lead.
local morf=require("morf")
local M=require("settings_model")
local view=require("themes").view("utilities")
M.WIDTH,M.RADIUS=view.WIDTH,view.RADIUS
local builders={
  network=function(w,h,host) return require("connectivity").network_page(w,h,host.showing("network")) end,
  mobile=function(w,h,host) return require("connectivity").mobile_page(w,h,host.showing("mobile")) end,
  bluetooth=function(w,h,host) return require("connectivity").bluetooth_page(w,h,host.showing("bluetooth")) end,
  sound=function(w,h) return require("sound_page").output_page(w,h) end,
  ["sound/more"]=function(w,h) return require("sound_page").more_page(w,h) end,
  ["sound/equalizer"]=function(w,h) return require("equalizer_page").page(w,h) end,
  ["sound/equalizer/audiogram"]=function(w,h) return require("equalizer_page").audiogram(w,h) end,
  microphone=function(w,h) return require("sound_page").input_page(w,h) end,
  power=function(w,h,host) return require("power_page").page(w,h,host.showing("power")) end,
  bar=function(w,h) return require("bar_page").page(w,h) end,
  ["bar/tray"]=function(w,h) return require("bar_page").tray_page(w,h) end,
  osd=function(w,h) return require("osd_page").page(w,h) end,
  touch=function(w,h) return require("touch_page").page(w,h) end,
  ["touch/gesture"]=function(w,h) return require("touch_page").gesture_page(w,h) end,
  panels=function(w,h) return require("themes").view("panels_page").build(M,w,h) end,
  assistant=function(w,h) return require("themes").view("assistant_settings").page(require("assistant_model"),w,h) end,
  calendars=function(w,h) return require("themes").view("calendar_settings").page(require("calendar_sources"),w,h) end,
  notes=function(w,h) return require("notes_page").build(require("pages").shown("notes"),w,h) end,
  linked_phone=function(w,h) return require("linked_phone_page").build(require("pages").shown("linked_phone"),w,h) end,
  lock=function(w,h) return require("lock_page").page(w,h) end,
  idle=function(w,h) return require("idle_page").page(w,h) end,
  windows=function(w,h) return require("windows_page").page(w,h) end,
  ["windows/rules"]=function(w,h) return require("windows_page").rules_page(w,h) end,
  ["windows/rule"]=function(w,h) return require("windows_page").rule_page(w,h) end,
  ["windows/layouts"]=function(w,h) return require("windows_page").layouts_page(w,h) end,
  wired=function(w,h) return require("net_pages").wired_page(w,h) end,
  mesh=function(w,h) return require("net_pages").vpn_page("mesh",w,h,M.displayed) end,
  tunnel=function(w,h) return require("net_pages").vpn_page("tunnel",w,h,M.displayed) end,
  focus=function(w,h,host) return require("focus_page").page(host,w,h) end,
  ["focus/mode"]=function(w,h,host) return require("focus_page").mode_page(host,w,h) end,
  notifications=function(w,h) return require("notification_settings").page(w,h) end,
  ["notifications/app"]=function(w,h) return require("notification_settings").app_page(w,h) end,
  theme=function(w,h) return view.theme_page(M,w,h) end,
  eva=function(w,h) return view.eva_page(M,w,h) end,
  hotspot=function(w,h,host) return require("themes").view("quick_pages").hotspot_page(host,w,h) end,
  nightlight=function(w,h,host) return require("themes").view("quick_pages").nightlight_page(host,w,h) end,
  flashlight=function(w,h,host) return require("themes").view("quick_pages").flashlight_page(host,w,h) end,
  filters=function(w,h,host) return require("themes").view("quick_pages").filters_page(host,w,h) end,
  sounds=function(w,h,host) return require("themes").view("quick_pages").sounds_page(host,w,h) end,
  ["theme/lule"]=function(w,h) return require("lule_page").build(w,h) end,
}
local function active(key) return require("presentation").active("settings."..key) end
local function with_request(model) model.request=M.request return model end
local function themed(name) return require("themes").view(name) end

builders["lock/fingerprint"]=function(w,h)
  return themed("fingerprint_page").build(require("fingerprint_model"),active("lock/fingerprint"),w,h)
end
builders.software=function(w,h) return themed("software_page").build(require("software_model"),w,h) end
-- Pages of what were tools of apps/, their code still in the tool's folder.
builders["input/shortcuts"]=function(w,h) return require("apps.keys.page").build(w,h) end
builders.breaks=function(w,h) return require("apps.breaks.page").build(w,h) end
builders.screen_time=function(w,h) return themed("screen_time_page").build(require("screen_time_model"),w,h) end
builders["screen_time/app"]=function(w,h) return themed("screen_time_page").app(require("screen_time_model"),w,h) end
builders["bar/fold"]=function(w,h) return themed("bar_fold").build(require("status_model"),w,h) end
builders["theme/fonts"]=function(w,h)
  local model=require("fonts_model")
  model.active=active("theme/fonts")
  model.restore()
  morf.effect("eva.settings.fonts.list",function() if model.active() then model.load() end end)
  return themed("fonts_page").page(model,w,h)
end

-- All settings, and the pages over the shell's own configuration. Beside a
-- desk's way round it is the index of every page; on a phone, the search and
-- the categories.
builders.home=function(w,h)
  local home=themed("settings_home")
  local model={active=active("home"),request=M.request,page_present=M.page_present}
  if require("responsive").form()=="phone" then return home.build(model,w,h) end
  return home.index(model,w,h)
end
for _,category in ipairs(require("settings_registry").CATEGORIES) do
  builders[category.key]=function(w,h)
    return themed("settings_home").category({active=active(category.key),request=M.request,page_present=M.page_present},category,w,h)
  end
end
for _,name in ipairs {"launcher","rail","capture","weather","commands","bar/more","keyboard","lock/more","windows/more","phone","backups/more","input/remap"} do
  builders[name]=function(w,h) return themed("settings_form").build(name,w,h) end
end

-- Keyboard and pointer.
for _,key in ipairs {"input","input/pointer","input/devices"} do
  builders[key]=function(w,h)
    return themed("settings_input").build(with_request(require("input_model").new(key)),w,h)
  end
end
local function system(view_name,make)
  return function(w,h) return themed("settings_system")[view_name](with_request(make()),w,h) end
end
builders.datetime=system("datetime_page",function() return require("datetime_model").new("datetime") end)
builders.region=system("region_page",function() return require("datetime_model").new("region") end)
builders.users=system("users_page",function() return require("users_model").new("users") end)
builders.privacy=system("privacy_page",function() return require("privacy_page_model").new() end)
builders.firewall=system("firewall_page",function() return require("privacy_page_model").firewall() end)
builders.about=system("about_page",function() return require("about_model").about() end)
builders.updates=system("updates_page",function() return require("about_model").updates() end)
builders.displays=system("displays_page",function() return require("about_model").displays() end)
builders.storage=function(w,h) return themed("settings_devices").storage_page(with_request(require("storage_model").new()),w,h) end
builders.printers=function(w,h) return themed("settings_devices").printers_page(with_request(require("storage_model").printers()),w,h) end
builders.apps=function(w,h) return themed("settings_apps").defaults_page(with_request(require("apps_model").defaults()),w,h) end
builders.startup=function(w,h) return themed("settings_apps").startup_page(with_request(require("apps_model").startup()),w,h) end
builders.accessibility=function(w,h) return themed("settings_access").build(require("access_model").new(nil,M),w,h) end
builders["network/connection"]=function(w,h)
  return themed("settings_net").connection_page(with_request(require("connection_model").new()),w,h)
end
builders["network/proxy"]=function(w,h)
  return themed("settings_net").proxy_page(with_request(require("connection_model").proxy()),w,h)
end
builders["network/help"]=function(w,h)
  return themed("net_help").page(with_request(require("net_help_model").new()),w,h)
end
builders.welcome=function(w,h) return themed("welcome").page(require("welcome_model"),M,w,h) end
builders.backups=function(w,h) return themed("backups_page").page(with_request(require("backups_model").new()),w,h) end
--- Page `key` built anew for `host`, the Settings window's model without one.
function M.page_content(key,w,h,host) return assert(builders[key],"Unknown Settings page: "..key)(w,h,host or M) end
--- Whether page `key` has a builder.
function M.has_page(key) return builders[key]~=nil end
local visual
local built=morf.signal("eva.settings.built",false)
function M.page(w,h)
  visual=view.build(M,w,h)
  built:set(true)
  return visual.node,visual.head
end
function M.height() return built:get() and visual.height and visual.height() or 0 end
--- How tall the page stands, head included, for a sheet that fits it: the
--- cards or the page on show over them, nil until measured.
function M.fit()
  if not built:get() or not visual.laid_out() then return nil end
  local P=require("themes.layouts.page")
  local key=M.in_panel.detail:get()
  local body=visual.height()+P.GAP
  if key~="" then body=visual.detail_height(key) end
  return body and P.header_height(visual.head)+P.GAP+body or nil
end
--- The quick controls on show, or put away: shut, back on the cards, tiles still.
function M.shown(open)
  M.quick:set(open)
  if not open then
    M.in_panel.detail:set("")
    M.tiles.editing:set(false)
  end
end
morf.effect("eva.settings.lifecycle",function()
  M.shown(require("pages").active("settings")())
end)
-- An equalizer left on comes back with the shell.
do
  local ok,saved=pcall(function() return morf.json.decode(morf.fs.read(morf.paths.state("eva-equalizer.json"))) end)
  if ok and type(saved)=="table" and saved.enabled==true then
    morf.time.timer(1,function() require("equalizer_model") end,false)
  end
end
return M
