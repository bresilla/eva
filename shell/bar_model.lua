-- Cached bar readings and actions. No widget construction or layout policy.
local morf = require("morf")
local M = {}
function M.new(ctx)
  local services, apps = require("services"), require("apps")
  local status, battery = require("status_model"), require("battery_status_model")
  local responsive = require("responsive")
  local clock = require("clock_format")
  local model = { on=ctx.on, side=ctx.side, vertical=ctx.vertical, screen=ctx.screen, insets=ctx.insets,
    rows=morf.list_model({}), keys=status.KEYS, form=responsive.form,
    stamp=morf.signal("eva.bar.clock",{time="",date="",day="",hour="",minute="",second="",meridiem=""}),
    reading=morf.signal("eva.bar.reading",{network_icon="",mobile_icon="",battery=battery.NONE,percentage="",
      indicators={},icons={},technology="",roaming=false}) }
  function model.titles() return require("config").get("edgebar.titles")~="off" and not model.vertical() end
  -- The tray on a desk, up while the bar is and its setting says so.
  local config=require("config")
  function model.tray_on() return config.get("edgebar.tray")~="off" end
  if responsive.form()=="desk" then
    model.tray=require("tray_model").new()
    morf.effect("eva.bar.tray",function()
      if model.on() and model.tray_on() then model.tray.start() else model.tray.stop() end
    end)
  end
  local function dry()
    local v=morf.env("EVA_DRY_RUN")
    return v~=nil and v~=false and v~="" and v~="0"
  end
  -- The wheel over the bar, each with its setting: `volume` or `workspace`.
  function model.wheel_on(kind) return config.get("edgebar.wheel_"..kind)==true end
  local VOLUME_STEP=0.05
  function model.wheel_volume(steps)
    if not (model.on() and model.wheel_on("volume")) then return end
    local volume=require("osd").volume()
    require("settings_model").levels.set_volume(math.max(0,math.min(1,volume-steps*VOLUME_STEP)))
  end
  --- The workspace `delta` along, or a dry run's note of it.
  function model.step_workspace(delta)
    if not model.on() then return end
    if dry() then
      morf.log("info","eva: workspace "..delta.." (dry run)")
      return
    end
    services.workspace.step(delta)
  end
  function model.wheel_workspaces(steps)
    if not model.on() then return end
    require("workspace_turn")(steps)
  end
  function model.wheel_workspace(steps)
    if not model.on() or not model.wheel_on("workspace") then return end
    model.wheel_workspaces(steps)
  end
  --- Workspace `id` on show.
  function model.go_workspace(id)
    if not model.on() then return end
    if dry() then
      morf.log("info","eva: workspace "..tostring(id).." (dry run)")
      return
    end
    services.workspace.go(id)
  end
  -- What collapses, in `room` pixels: status_model.arrange.
  function model.arrange(room,sizes)
    local r=model.reading:get()
    sizes.level=r.battery.level
    if not r.battery.present then sizes.percent=0 end
    return status.arrange(r.indicators,room,sizes)
  end

  model.privacy=require("privacy_model").shared()
  status.connect()
  morf.effect("eva.bar.privacy",function()
    if model.on() then morf.time.timer(1,function() model.privacy.start() end,false) end
  end)
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
      technology=not airplane and m and m.state.available and m.state.technology or "",
      roaming=not airplane and m~=nil and m.state.available==true and m.state.roaming==true}
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
    local options=clock.options()
    if options.seconds or (options.format or ""):find("%%[STrsXc]") then morf.time.clock:get()
    else morf.time.minute_clock:get() end
    model.stamp:set(clock.stamp(options,morf.time.now()))
  end)
  function model.focus(address)
    if not model.on() then return false end
    if dry() then return false end
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
  --- Window `address` focused, and its menu open over it.
  function model.window_menu(address)
    if not model.on() then return end
    model.focus(address)
    require("window_menu").open()
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
  -- The clock's press: a sheet's notifications, a desk's dashboard.
  function model.press_clock()
    if responsive.sheets() then model.open_notifications() else model.toggle_dashboard() end
  end
  local function open_left(tab)
    if not model.on() then return end
    local leftbar=require("leftbar")
    leftbar.panel.select(tab)
    leftbar.drawer.set(true)
  end
  function model.open_calendar() open_left("calendar") end
  function model.open_tasks() open_left("tasks") end
  function model.settings_open()
    local s=package.loaded.sidebar and require("pages").holder("settings")
    return s and s.drawer and s.drawer.open:get() or false
  end
  function model.dashboard_open()
    local d=package.loaded.dashboard
    return d and d.drawer and d.drawer.open:get() or false
  end

  -- ------------------------------------------------------ what modules read --
  -- The notifications, from the badge every screen shares: none while Focus
  -- hides it.
  model.notifications={}
  local function notifs() return package.loaded.notifs end
  function model.notifications.count()
    local n=notifs()
    if not n then return 0 end
    local badge=n.badge:get()
    return badge.hidden and 0 or badge.unread
  end
  function model.notifications.dnd()
    local n=notifs()
    return n~=nil and n.dnd:get()==true
  end
  function model.notifications.toggle_dnd()
    local n=notifs()
    if n then n.dnd:set(not n.dnd:get()) end
  end

  local function session(name) return require("themes.session").keep(name,false) end
  function model.awake() return session("eva.utilities.awake"):get()==true end
  function model.toggle_awake() require("settings_model").set_awake(not model.awake()) end
  function model.recording()
    local capture=package.loaded.capture
    return capture~=nil and capture.recording~=nil and capture.recording:get()==true
  end
  function model.toggle_mode()
    local mode=require("themes.color_mode")
    mode.set(mode.resolve()=="light" and "dark" or "light")
  end
  function model.next_profile()
    local power=services.upower
    local profiles=power and power.state.profiles
    if not (profiles and profiles.available and power.set_profile) then return end
    local rows,at={},1
    for i=1,profiles.list:len() do
      rows[i]=profiles.list:get(i).name
      if rows[i]==profiles.active then at=i end
    end
    if #rows>0 then power.set_profile(rows[at%#rows+1]) end
  end
  function model.next_layout()
    if dry() then
      morf.log("info","eva: next keyboard layout (dry run)")
      return
    end
    local h=services.hyprland
    if h and h.available() then pcall(h.dispatch,"switchxkblayout","current next") end
  end
  local updates_source
  function model.updates()
    if not updates_source then
      local updates,poll=require("updates_model"),require("lib.util.poll")
      updates_source=poll.source {name="eva.bar.updates",interval=1800000,initial={},
        sample=function(done)
          local nix=updates.nix("",config.get("bar.updates.flake"))
          done(updates.describe(nix,nil))
        end}
    end
    return updates_source:get()
  end
  local ssh_source
  function model.ssh_sessions()
    if not ssh_source then
      ssh_source=require("lib.util.poll").source {name="eva.bar.ssh",interval=30000,initial=0,
        sample=function(done)
          morf.process.run({"who"},{timeout_ms=4000},function(result)
            local count=0
            for line in tostring(result and result.stdout or ""):gmatch("[^\n]+") do
              if line:match("%(%d+%.%d+%.%d+%.%d+%)") or line:match("%(%x*:%x*:[%x:]*%)") then count=count+1 end
            end
            done(count)
          end)
        end}
    end
    return ssh_source:get()
  end
  local trash_source
  function model.trash_count()
    if not trash_source then
      local path=(morf.env("XDG_DATA_HOME") or (morf.fs.home().."/.local/share")).."/Trash/files"
      trash_source=require("lib.util.poll").source {name="eva.bar.trash",interval=30000,initial=0,
        sample=function(done)
          local ok,entries=pcall(morf.fs.list,path)
          done(ok and type(entries)=="table" and #entries or 0)
        end}
    end
    return trash_source:get()
  end
  -- The next thing today in the planner: `{ text, tooltip }`.
  local event_source
  function model.next_event()
    if not event_source then
      event_source=require("lib.util.poll").source {name="eva.bar.event",interval=60000,initial=false,
        sample=function(done)
          local ok,rows=pcall(function() return require("planner").agenda(morf.time.format("%Y-%m-%d")) end)
          local first=ok and type(rows)=="table" and rows[1] or nil
          done(first and {text=tostring(first.description or first.title or ""),tooltip=tostring(first.project or "Today")} or false)
        end}
    end
    return event_source:get() or nil
  end
  --- The privacy list opened: the view fills this in.
  function model.show_privacy() if model.open_privacy then model.open_privacy() end end
  --- The Bar page, in the settings.
  function model.open_bar_page()
    if not model.on() then return end
    require("utilities").request("bar")
    local sidebar=require("sidebar")
    sidebar.select("settings")
    sidebar.drawer.set(true)
  end

  -- ------------------------------------------------------------- the board --
  local layout,store=require("bar_layout"),require("bar_store")
  model.live=require("live_model").new(model)
  model.modules=require("bar_modules").list(model)
  model.board=require("tiles_model").new(model.modules,responsive.form,
    {zones=layout.ZONES,store=store.new(responsive.form,store.output),editing=morf.signal("eva.bar.editing",true)})
  return model
end
return M
