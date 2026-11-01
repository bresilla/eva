-- Cached bar readings and actions. No widget construction or layout policy.
local morf = require("morf")
local M = {}
function M.new(ctx)
  local services, apps = require("services"), require("apps")
  local status, battery = require("status_model"), require("battery_status_model")
  local model = { on=ctx.on, side=ctx.side, vertical=ctx.vertical, screen=ctx.screen, insets=ctx.insets,
    rows=morf.list_model({}), keys=status.KEYS,
    stamp=morf.signal("eva.bar.clock",{"","",""}),
    reading=morf.signal("eva.bar.reading",{network_icon="",mobile_icon="",battery=battery.NONE,percentage="",
      indicators={},icons={},technology=""}) }
  function model.titles() return require("config").get("edgebar.titles")~="off" and not model.vertical() end
  -- The tray on a desk, up while the bar is and its setting says so.
  local config=require("config")
  function model.tray_on() return config.get("edgebar.tray")~="off" end
  if require("responsive").form()=="desk" then
    model.tray=require("tray_model").new()
    morf.effect("eva.bar.tray",function()
      if model.on() and model.tray_on() then model.tray.start() else model.tray.stop() end
    end)
  end
  -- The wheel over the bar, each with its setting: `volume` or `workspace`.
  function model.wheel_on(kind) return config.get("edgebar.wheel_"..kind)==true end
  local VOLUME_STEP=0.05
  function model.wheel_volume(steps)
    if not (model.on() and model.wheel_on("volume")) then return end
    local volume=require("osd").volume()
    require("settings_model").levels.set_volume(math.max(0,math.min(1,volume-steps*VOLUME_STEP)))
  end
  function model.wheel_workspace(steps)
    if not (model.on() and model.wheel_on("workspace")) then return end
    require("workspace_turn")(steps)
  end
  -- What collapses, in `room` pixels: status_model.arrange.
  function model.arrange(room,sizes)
    local r=model.reading:get()
    sizes.level=r.battery.level
    if not r.battery.present then sizes.percent=0 end
    return status.arrange(r.indicators,room,sizes)
  end

  status.connect()
  morf.effect("eva.bar.readings",function()
    if not model.on() then return end
    local b=battery.read()
    local m=services.modem
    local indicators=status.read(services)
    local icons={}
    for _,item in ipairs(indicators) do icons[item.key]=item.icon end
    local airplane=require("config").get("airplane.on")==true
    model.reading:set {network_icon=status.network_icon(services.net),mobile_icon=status.mobile_icon(m,airplane),
      battery=b,percentage=b.present and ("%d%%"):format(b.level) or "",indicators=indicators,icons=icons,
      technology=not airplane and m and m.state.available and m.state.technology or ""}
  end)
  morf.effect("eva.bar.windows",function()
    if not model.on() then return end
    local rows={}
    local h=services.hyprland
    if h then
      local workspace=services.workspace.active()
      local focused=(h.state.active_window or {}).address
      local clients=h.state.clients
      for i=1,clients:len() do
        local client=clients:get(i)
        if client.workspace==workspace and not client.hidden then
          local class=client.class or ""
          local icon=apps.icon(class:lower()) or apps.icon(class) or apps.icon((client.initial_class or ""):lower())
          rows[#rows+1]={address=tostring(client.address),title=client.title and client.title~="" and client.title or class,
            class=class,focused=focused==client.address,icon=icon or {}}
        end
      end
    end
    model.rows:replace(rows,"address")
  end)
  morf.effect("eva.bar.time",function()
    if not model.on() then return end
    morf.time.minute_clock:get()
    local t=morf.time.now()
    model.stamp:set {morf.time.format("%H:%M",t),morf.time.format("%a %-d %b",t),morf.time.format("%d",t)}
  end)
  function model.focus(address)
    if not model.on() then return false end
    local dry=morf.env("EVA_DRY_RUN")
    if dry and dry~="" and dry~="0" then return false end
    local h=services.hyprland
    if not h then return false end
    local workspace=services.workspace.active()
    for i=1,h.state.clients:len() do
      local client=h.state.clients:get(i)
      if tostring(client.address)==address and client.workspace==workspace and not client.hidden then
        return pcall(h.dispatch,"focuswindow","address:"..address)
      end
    end
    return false
  end
  function model.toggle_launcher()
    if not model.on() then return end
    local d=require("launcher").drawer d.set(not d.open:get())
  end
  function model.open_settings()
    if not model.on() then return end
    require("utilities").detail:set("")
    require("pages").open("settings")
  end
  function model.open_notifications()
    if not model.on() then return end
    require("pages").open("notifications")
  end
  function model.toggle_dashboard()
    if not model.on() then return end
    local d=require("dashboard").drawer d.set(not d.open:get())
  end
  function model.settings_open()
    local s=package.loaded.sidebar and require("pages").holder("settings")
    return s and s.drawer and s.drawer.open:get() or false
  end
  function model.dashboard_open()
    local d=package.loaded.dashboard
    return d and d.drawer and d.drawer.open:get() or false
  end
  return model
end
return M
