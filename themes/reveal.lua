-- One motion from a login screen to the desktop: what stands over the wallpaper
-- fades off it in LEAVE ms, then the frame, the rail and the bar come in from
-- the edges. Lock and greeter read the timing; the shell's parts arrive on
-- their first frame, once per output per session, and again on `replay`.
local morf=require("morf")
local session=require("themes.session")
local M={LEAVE=170}
M.MOTION={duration=M.LEAVE,easing="out_cubic"}

local LEAD,STAGGER=180,35
local parts,running={},{}

-- The file that says this output has arrived in this session.
local function marker()
  local run,display=morf.env("XDG_RUNTIME_DIR"),morf.env("HYPRLAND_INSTANCE_SIGNATURE") or morf.env("WAYLAND_DISPLAY")
  if not run or not display or run=="" or display=="" then return nil end
  local output=(morf.screens[1] or {}).name or "output"
  return (run.."/eva/arrived-"..display.."-"..output):gsub("[^%w_./-]","_"),nil
end

-- Whether this runtime is the output's first in the session. A dry run keeps
-- the answer in memory, for this process alone.
local function first()
  if session.restoring then return false end
  local path=morf.env("EVA_DRY_RUN")~="1" and marker()
  if path then
    if morf.fs.exists(path) then return false end
    return morf.fs.write(path,"",{parents=true,mode=384})~=false
  end
  local seen=morf.reloadable("eva.reveal.seen",false)
  if seen:get() then return false end
  seen:set(true)
  return true
end

local arriving
function M.arriving()
  if arriving==nil then arriving=first() end
  return arriving
end

local function timed(order,values)
  local bounce=require("theme").bounce.spatial
  local steps={duration=bounce.duration,easing=bounce.easing,delay=LEAD+order*STAGGER}
  for property,value in pairs(values) do steps[property]=value end
  return steps
end

--- `make(props)`, the `order`th part to arrive, from `hidden()` to `rest()`.
function M.part(make,props,order,hidden,rest)
  if M.arriving() then props.enter=timed(order,hidden()) end
  local node=make(props)
  parts[#parts+1]={node=node,order=order,hidden=hidden,rest=rest}
  return node
end

--- `hidden` and `rest` for the frame's opening: past the screen's edges by
--- `reach`, then the desk less the frame.
function M.opening(desk,left,border,reach)
  return function()
    local screen=morf.screens[1] or {}
    return {x=-reach,y=-reach,width=(screen.width or 1920)+2*reach,height=(screen.height or 1080)+2*reach}
  end,function()
    local x,y,width,height=desk()
    return {x=x+left,y=y+border,width=width-left-border,height=height-2*border}
  end
end

--- Takes every part back to hidden at once, and brings them in again.
function M.replay()
  if session.restoring then return false end
  for _,handle in ipairs(running) do handle:stop() end
  running={}
  for _,part in ipairs(parts) do
    local rest,steps=part.rest(),{}
    for property,value in pairs(part.hidden()) do
      part.node[property]=value
      local step=timed(part.order,{})
      step.node,step.property,step.to=part.node,property,rest[property]
      steps[#steps+1]=step
    end
    running[#running+1]=morf.animation.play {{parallel=steps}}
  end
  return true
end

return M
