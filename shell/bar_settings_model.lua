-- Bar preferences and validated mutations; views only receive this model.
local morf=require("morf")
local config=require("config")
local bar=require("bar")
local store=require("bar_store")
local clock=require("clock_format")
local M={}
function M.new(active)
  local model={key="bar-settings",active=active,
    shows={{"on","visibility","On"},{"off","visibility_off","Off"},{"auto","smartphone","Auto"}},
    sides={{"top","vertical_align_top","Top"},{"bottom","vertical_align_bottom","Bottom"},
      {"left","align_horizontal_left","Left"},{"right","align_horizontal_right","Right"}},
    title_modes={{"on","title","Shown"},{"off","apps","Icons only"}},
    dates=clock.DATES,
    screen_shows={{"","sync_alt","As set"},{"on","visibility","On"},{"off","visibility_off","Off"}},
  }
  function model.mode()
    local v=config.get("edgebar.enabled")
    return (v=="on" or v=="off") and v or "auto"
  end
  model.side=bar.side
  function model.titles() return config.get("edgebar.titles")~="off" and "on" or "off" end
  local function select(options,key,value)
    if not active() then return false end
    for _,option in ipairs(options) do
      if option[1]==value then
        if key=="edgebar.side" then bar.set_side(value) else config.set(key,value) end
        return true
      end
    end
    return false
  end
  function model.set_mode(value) return select(model.shows,"edgebar.enabled",value) end
  function model.set_side(value) return select(model.sides,"edgebar.side",value) end
  function model.set_titles(value) return select(model.title_modes,"edgebar.titles",value) end
  -- The clock.
  local function flag(name)
    return function() return config.get("bar.clock."..name)==true end,
      function(on) if active() then config.set("bar.clock."..name,on==true) end end
  end
  model.twelve_hour,model.set_twelve_hour=flag("twelve_hour")
  model.seconds,model.set_seconds=flag("seconds")
  function model.date() return config.get("bar.clock.date") end
  function model.set_date(value) return select(model.dates,"bar.clock.date",value) end
  -- Its height, and whether the battery says its percentage.
  model.heights={{"0","height","Normal"},{"32","compress","Slim"},{"48","expand","Tall"}}
  function model.height() return tostring(math.floor(tonumber(config.get("bar.height")) or 0)) end
  function model.set_height(value) if active() then config.set("bar.height",tonumber(value) or 0) end end
  function model.percent() return config.get("bar.percent")~=false end
  function model.set_percent(on) if active() then config.set("bar.percent",on==true) end end
  -- What a few modules need told: `{ key, title, hint }`, each a setting's text.
  model.details={
    {key="bar.clock.format",title="Clock pattern",hint="strftime, as %H:%M, empty for the choices above"},
    {key="bar.clock.zone",title="World clock zone",hint="Asia/Tokyo"},
    {key="bar.clock.zone_label",title="World clock name",hint="Tokyo"},
    {key="bar.countdown.date",title="Countdown to",hint="2027-01-01"},
    {key="bar.countdown.label",title="Countdown name",hint="New year"},
    {key="bar.disk.mount",title="Disk to watch",hint="/"},
    {key="bar.text",title="Text module",hint="Any words"},
    {key="bar.updates.flake",title="Flake to watch",hint="~/nixos/flake.lock"},
  }
  function model.detail(key) return config.get(key) end
  function model.set_detail(key,value) if active() then config.set(key,value) end end
  -- The modules, on the bar's own board.
  function model.bar_model() return bar.model end
  -- The screens, each with its own say.
  function model.outputs()
    morf.window.screens_revision()
    local names,seen={},{}
    local function add(name)
      if name and name~="" and not seen[name] then seen[name]=true names[#names+1]=name end
    end
    local h=require("services").hyprland
    local rows=h and h.state and h.state.outputs
    for i=1,rows and rows.len and rows:len() or 0 do add(rows:get(i).name) end
    for _,screen in ipairs(morf.screens or {}) do add(screen.name) end
    for _,row in ipairs(config.get("bar.outputs") or {}) do add(row.name) end
    return names
  end
  function model.output_on(name) return store.on(name) end
  function model.set_output_on(name,value) if active() then store.set_on(name,value) end end
  function model.output_own(name) return store.own(name) end
  function model.set_output_own(name,on)
    if active() then store.set_own(name,on==true,require("responsive").form()) end
  end
  -- The desk's own: the tray, and the wheel over the bar.
  model.desk=require("responsive").form()=="desk"
  function model.tray() return config.get("edgebar.tray")~="off" end
  function model.set_tray(on) if active() then config.set("edgebar.tray",on and "on" or "off") end end
  function model.wheel_volume() return config.get("edgebar.wheel_volume")==true end
  function model.set_wheel_volume(on) if active() then config.set("edgebar.wheel_volume",on==true) end end
  function model.wheel_workspace() return config.get("edgebar.wheel_workspace")==true end
  function model.set_wheel_workspace(on) if active() then config.set("edgebar.wheel_workspace",on==true) end end
  return model
end
return M
