-- Optional phone integration: a sleeping surface consumes all touches.
-- The same shield is used by the lockscreen and the separate greetd user.
--
-- A sleeping screen is either off, or, on a panel the system says can do it,
-- lit dark and dim with the lock's ambient face: `M.ambient()` says which.
local morf=require("morf")
local ui=require("morf.ui")
local M={}
local cfg,runtime,instance
local ok,raw=pcall(morf.fs.read,morf.env("EVA_PHONE_SCREEN_CONFIG") or "/etc/eva/phone-screen.json")
if ok and type(raw)=="string" then
  local valid,value=pcall(morf.json.decode,raw)
  if valid and type(value)=="table" and type(value.command)=="string" then cfg=value end
end
runtime,instance=morf.env("XDG_RUNTIME_DIR"),morf.env("HYPRLAND_INSTANCE_SIGNATURE")
local dry=morf.env("EVA_DRY_RUN")
--- Whether this machine runs the phone profile, dry or not.
function M.present() return cfg~=nil end
--- Whether the panel is said to be able to stay lit.
function M.always_on() return cfg~=nil and cfg.alwaysOn==true end
if not cfg or not runtime or not instance or (dry and dry~="" and dry~="0") then
  local fake=dry=="1" and morf.env("EVA_FAKE_AMBIENT")=="1"
  function M.attach() end
  function M.asleep() return false end
  function M.ambient() return fake end
  function M.allow_ambient() end
  function M.sleep() if cfg then morf.log("info","phone screen: off (dry run)") end end
  return M
end
local path=runtime.."/phone-screen-"..instance..".status"
local allowed=runtime.."/phone-screen-"..instance..".ambient"
local function read()
  local valid,value=pcall(morf.fs.read,path)
  return valid and type(value)=="string" and value:match("^(%a+)%s*$") or "on"
end
local mode=morf.signal("phone.screen.mode",read())
M.watch=morf.fs.watch(path,function() mode:set(read()) end)
local function sleeping() return mode:get()=="off" or mode:get()=="ambient" end
--- Whether the phone display is blanked; tracked, so an effect re-runs on change.
function M.asleep() return sleeping() end
--- Whether it is lit, dark and dim, rather than off.
function M.ambient() return mode:get()=="ambient" end
--- Tells the screen script the ambient face may stand, while the lock does.
function M.allow_ambient(on)
  if not M.always_on() then return end
  if on then pcall(morf.fs.write,allowed,"",{mode=384}) else pcall(morf.fs.remove,allowed) end
end
--- Puts the panel to sleep: a double tap on the lock's empty space.
function M.sleep()
  morf.process.run({cfg.command,"off"},{timeout_ms=15000,max_output=2048},function(result)
    if not result.ok then morf.log("warn","phone sleep: "..(result.stderr or "failed")) end
  end)
end
function M.attach(root,spec)
  local pending=false
  local taps=require("themes.double_tap").new {
    now=morf.time.now_ms,
    movement=math.min(spec.width,spec.height)*.025,
    separation=math.min(spec.width,spec.height)*.06,
    allowed=function() return sleeping() and cfg.doubleTap==true and not pending end,
    wake=function()
      pending=true
      morf.log("info","phone screen: double-tap wake")
      morf.process.run({cfg.command,"wake"},{timeout_ms=5000,max_output=2048},function(result)
        pending=false
        if not result.ok then morf.log("warn","phone wake: "..(result.stderr or "failed")) end
      end)
    end,
  }
  local shield=ui.MouseArea {
    id=spec.prefix.."-wake-shield",anchors={fill=true},z=10000,
    visible=sleeping,
    on_touch_pressed=taps.down,on_touch_moved=taps.move,
    on_touch_released=taps.up,on_touch_canceled=taps.cancel,
    -- Consume the mouse events synthesized from touches, too.
    on_clicked=function() end,on_dragged=function() end,on_key_pressed=function() end,
  }
  local was_sleeping
  morf.effect(spec.prefix..".phone-sleep."..(spec.output or ""),function()
    local value=sleeping()
    if value~=was_sleeping then
      was_sleeping=value taps.reset()
      if value and spec.rest then spec.rest() end
    end
  end,{owner=shield})
  ui.reparent(shield,root)
end
return M
