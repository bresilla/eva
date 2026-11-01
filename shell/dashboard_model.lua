-- Dashboard data and actions, independent of visual geometry.
local morf = require("morf")
local state = require("dashboard_state")
local services = require("services")
local sysinfo = require("lib.services.sysinfo")
local M = { tab = state.tab, opened = state.opened, displayed = state.displayed }
M.tabs = {
  { key = "overview", name = "Dashboard", icon = "dashboard" },
  { key = "media", name = "Media", icon = "queue_music" },
  { key = "performance", name = "Perf", icon = "speed" },
  { key = "battery", name = "Battery", icon = "battery_charging_full" },
  { key = "weather", name = "Weather", icon = "cloud" },
  { key = "terminal", name = "Terminal", icon = "terminal" },
}
do
  local KEYWORDS = { performance = "cpu memory gpu load", media = "music lyrics player", weather = "forecast temperature",
    battery = "charge power", terminal = "shell console" }
  local index = require("lib.shell.launcher.search_index")
  for position, tab in ipairs(M.tabs) do
    index.register { id = "dashboard:" .. tab.key, name = tab.key == "performance" and "Performance" or tab.name,
      keywords = KEYWORDS[tab.key], material = tab.icon, tag = "Dashboard", description = "Dashboard", kind = "menu",
      run = function()
        M.tab:set(position)
        require("dashboard").drawer.set(true)
        return "close"
      end }
  end
end
M.month_offset = require("themes.session").keep("eva.dashboard.month", 0)
--- The month the calendar shows, as a month index: this one and the offset.
function M.calendar_month()
  morf.time.minute_clock:get()
  local today = morf.time.date()
  return today.year * 12 + today.month - 1 + M.month_offset:get()
end
function M.shift_month(delta) M.month_offset:set(M.month_offset:get() + delta) end
function M.select(index)
  if M.tabs[index] then M.tab:set(index) end
end
function M.present(index) M.displayed:set(index) end
function M.overview_active() return M.opened:get() and M.displayed:get() == 1 end
local function visible(...)
  if not M.opened:get() then return false end
  local current = M.displayed:get()
  for _, index in ipairs {...} do if current == index then return true end end
  return false
end
-- Retain the last reading during visual departure without keeping sources awake.
local last={weather={available=false},system={uptime=0,hostname="",user=""},cpu=0,memory=0,storage=0,battery={},player={}}
function M.weather()
  if visible(1,5) then last.weather=services.weather() end
  return last.weather
end
M.weather_symbol = services.weather_symbol
function M.system()
  if M.opened:get() then last.system=sysinfo.system() or {} end
  return last.system
end
M.username = morf.env("USER") or morf.env("LOGNAME") or "user"
local face = morf.fs.home() .. "/.face"
M.face = morf.fs.exists(face) and face or ""
function M.desktop()
  if services.hyprland.available() then return "Hyprland" end
  local desktop = morf.env("XDG_CURRENT_DESKTOP")
  return desktop and desktop ~= "" and desktop or "Wayland"
end
function M.clock(format)
  morf.time.minute_clock:get()
  return morf.time.format(format)
end
--- Whether the clocks write twelve hours, from the bar's setting. A tracked read.
function M.twelve_hour() return require("config").get("bar.clock.twelve_hour") == true end
--- The hour as the clock setting writes it.
function M.clock_hour() return M.clock(M.twelve_hour() and "%I" or "%H") end
local function percent(kind,field)
  if visible(1,3) then
    local ok, value = pcall(sysinfo[kind])
    last[kind]=ok and tonumber(value[field]) or 0
  end
  return last[kind]
end
function M.cpu() return percent("cpu","usage") end
function M.memory() return percent("memory","percent") end
function M.storage()
  if not visible(1,3) then return last.storage end
  local ok, list = pcall(sysinfo.disks)
  if not ok then return last.storage end
  last.storage=list[1] and list[1].percent or 0
  for _, disk in ipairs(list or {}) do if disk.mount == "/" then last.storage=disk.percent or 0 break end end
  return last.storage
end
function M.battery()
  if visible(1,4) then
    local batteries=(sysinfo.battery() or {}).batteries or {}
    last.battery=batteries[1] or {}
  end
  return last.battery
end
function M.player()
  if visible(1,2) then last.player=services.player() end
  return last.player
end
function M.artwork() return require("lib.util.remote").file(M.player().art_url) end
function M.media_control(action)
  if services.media and services.media[action] then pcall(services.media[action]) end
end
local pages = {}
function M.page(index)
  if pages[index] then return pages[index] end
  pages[index] = require("dashboard_" .. M.tabs[index].key)
  return pages[index]
end
function M.desk_size()
  local _,_,w,h = require("bar").desk()
  return w,h
end
return M
