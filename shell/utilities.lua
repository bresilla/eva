-- Settings lifecycle and detail builders; the selected theme owns all layout.
local morf=require("morf")
local M=require("settings_model")
local view=require("themes").view("utilities")
M.WIDTH,M.RADIUS=view.WIDTH,view.RADIUS
local builders={
  network=function(w,h) return require("connectivity").network_page(w,h) end,
  mobile=function(w,h) return require("connectivity").mobile_page(w,h) end,
  bluetooth=function(w,h) return require("connectivity").bluetooth_page(w,h) end,
  sound=function(w,h) return require("sound_page").output_page(w,h) end,
  ["sound/equalizer"]=function(w,h) return require("equalizer_page").page(w,h) end,
  ["sound/equalizer/audiogram"]=function(w,h) return require("equalizer_page").audiogram(w,h) end,
  microphone=function(w,h) return require("sound_page").input_page(w,h) end,
  power=function(w,h) return require("power_page").page(w,h) end,
  bar=function(w,h) return require("bar_page").page(w,h) end,
  osd=function(w,h) return require("osd_page").page(w,h) end,
  panels=function(w,h) return require("themes").view("panels_page").build(M,w,h) end,
  wired=function(w,h) return require("net_pages").wired_page(w,h) end,
  mesh=function(w,h) return require("net_pages").vpn_page("mesh",w,h,M.displayed) end,
  tunnel=function(w,h) return require("net_pages").vpn_page("tunnel",w,h,M.displayed) end,
  focus=function(w,h) return view.focus_page(M,w,h) end,
  theme=function(w,h) return view.theme_page(M,w,h) end,
  eva=function(w,h) return view.eva_page(M,w,h) end,
  hotspot=function(w,h) return require("themes").view("quick_pages").hotspot_page(M,w,h) end,
  nightlight=function(w,h) return require("themes").view("quick_pages").nightlight_page(M,w,h) end,
  ["theme/lule"]=function(w,h) return require("lule_page").build(w,h) end,
  ["theme/wallpaper"]=function(w,h) return require("wallpaper_page").build(w,h) end,
  ["theme/desktop"]=function(w,h) return require("themes").view("desktop_page").build(require("desktop_model"),w,h) end,
  ["theme/look"]=function(w,h) return require("themes").view("look_page").build(require("appearance_model"),w,h) end,
}
function M.page_content(key,w,h) return assert(builders[key],"Unknown Settings page: "..key)(w,h) end
local visual
local built=morf.signal("eva.settings.built",false)
function M.page(w,h)
  visual=view.build(M,w,h)
  built:set(true)
  return visual.node,visual.head
end
function M.height() return built:get() and visual.height and visual.height() or 0 end
--- How tall the page wants to stand, head included, for a sheet that fits
--- its content: the overview's cards or the detail on show, nil until they
--- are measured.
function M.fit()
  if not built:get() or not visual.laid_out() then return nil end
  local P=require("themes.layouts.page")
  local key=M.detail:get()
  local body=visual.height()+P.GAP
  if key~="" then body=visual.detail_height(key) end
  return body and P.header_height(visual.head)+P.GAP+body or nil
end
function M.shown(open)
  M.opened:set(open)
  if not open then
    M.detail:set("")
    M.tiles.editing:set(false)
  end
end
morf.effect("eva.settings.lifecycle",function()
  M.shown(require("presentation").active("sidebar.settings")())
end)
return M
