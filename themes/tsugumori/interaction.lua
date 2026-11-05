-- Shared feedback for every actionable target. Decoration moves; the input
-- rectangle stays fixed so pressing never makes a target slide away.
--
-- The decoration (a wash, one glint, a press scan line and the two
-- registration marks on the top-left / bottom-right diagonal) is built the
-- first time the pointer reaches the target, not up front: a shell holds
-- hundreds of hidden controls, and each would otherwise carry its own nodes
-- and colour bindings through every layout pass and palette change.
local ui = require("morf.ui")
local morf = require("morf")
return function(theme)
  local C = theme.color
  local attached = setmetatable({}, {__mode="k"})
  local serial=0
  local MARK="M0 0 H7 V1.5 H1.5 V7 H0 Z"

  --- The pieces in `holder` from z `z`; `size()` gives the target's box.
  --- Returns `react(over, down)`, to call whenever either changes.
  local function pieces(holder, id, size, z)
    z = z or 0
    local wash=ui.Rect { id=id.."-wash",anchors={fill=true},z=z,
      color=function() return C.primary end,opacity=0,
      behavior={opacity={duration=140,easing="out_cubic"}} }
    ui.reparent(wash,holder)
    -- A single clipped glint crosses the control on entry or press, and a
    -- scan line runs down it on a press. Neither moves at rest.
    local glint = ui.Path { id=id.."-glint",x=-36,width=28,
      height=function() local _, h = size() return math.max(1,h) end,
      view_box={0,0,28,100},d="M20 0 H28 L8 100 H0 Z",
      fill_color=function() return C.primary end,opacity=0 }
    local scan = ui.Rect { id=id.."-scan",anchors={left=true,right=true},height=1,
      color=function() return C.primary end,opacity=0 }
    ui.reparent(ui.Item { id=id.."-glint-clip",anchors={fill=true},clip=true,z=z+1,glint,scan },holder)
    -- Registration marks on the chamfer diagonal only (never four
    -- brackets): they close in onto the control from further out.
    local marks={}
    for i,corner in ipairs {{left=true,top=true},{right=true,bottom=true}} do
      marks[i]=ui.Path {id=id.."-mark-"..i,anchors=corner,width=7,height=7,z=z+2,
        view_box={0,0,7,7},d=MARK,rotation=i==1 and 0 or 180,
        fill_color=function() return C.primary end,opacity=0,
        behavior={translate_x={duration=340,easing="out_cubic"},translate_y={duration=340,easing="out_cubic"},
          opacity={duration=180}}}
      ui.reparent(marks[i],holder)
    end
    local hovered,pressed,running,scanning,closing=false,false,nil,nil,nil
    return function(over, down)
      local entering,pressing=over and not hovered,down and not pressed
      hovered,pressed=over,down
      wash.opacity=down and 0.18 or over and 0.055 or 0
      if closing then closing:stop() closing=nil end
      local reticle={}
      for i,mark in ipairs(marks) do
        local s=(over and not down) and (i==1 and -3 or 3) or 0
        if entering and not down then
          local far=i==1 and -10 or 10
          for _,property in ipairs {"translate_x","translate_y"} do
            reticle[#reticle+1]={node=mark,property=property,from=far,to=s,duration=260,easing="out_expo"}
          end
        else
          mark.translate_x,mark.translate_y=s,s
        end
        mark.opacity=over and 1 or 0
      end
      if #reticle>0 then closing=morf.animation.play {{parallel=reticle},on_finished=function() closing=nil end} end
      if not over and not down then
        if running then running:stop() running=nil end
        if scanning then scanning:stop() scanning=nil end
        glint.opacity,scan.opacity=0,0
        return
      end
      local w,h=size()
      if entering or pressing then
        if running then running:stop() end
        running=morf.animation.play {{parallel={
          {node=glint,property="x",from=-36,to=w+36,duration=330,easing="out_cubic"},
          {node=glint,property="opacity",duration=330,keyframes={
            {at=0,value=0},{at=.13,value=.33},{at=.65,value=.27},{at=1,value=0},
          }},
        }},on_finished=function() running=nil end}
      end
      if pressing and h>2 then
        if scanning then scanning:stop() end
        scanning=morf.animation.play {{parallel={
          {node=scan,property="translate_y",from=0,to=h-1,duration=200,easing="out_cubic"},
          {node=scan,property="opacity",duration=220,keyframes={
            {at=0,value=0},{at=.1,value=.9},{at=.7,value=.55},{at=1,value=0},
          }},
        }},on_finished=function() scanning=nil end}
      end
    end
  end

  local function attach(area, name)
    if attached[area] then return area end
    attached[area]=true
    serial=serial+1
    local id=name or "tsugumori-action-"..serial
    local react
    morf.effect(id..".feedback",function()
      local over,down=area.hovered,area.pressed
      if not react then
        if not over and not down then return end
        react=pieces(area,id,function() return area.width,area.height end,40)
      end
      react(over,down)
    end,{owner=area})
    return area
  end
  return attach, pieces
end
