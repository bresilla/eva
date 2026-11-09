-- Shared feedback for every actionable target. Decoration moves; the input
-- rectangle stays fixed so pressing never makes a target slide away.
--
-- The decoration (a wash, one glint, a press scan bar and four corner
-- brackets that close in from further out and snap on) is built the first
-- time the pointer reaches the target, not up front: a shell holds hundreds
-- of hidden controls, and each would otherwise carry its own nodes and
-- colour bindings through every layout pass and palette change. An
-- on-screen keyboard's key keeps its two registration marks and no scan.
local ui = require("morf.ui")
local morf = require("morf")
return function(theme)
  local C = theme.color
  local attached = setmetatable({}, {__mode="k"})
  local serial=0
  local MARK="M0 0 H7 V1.5 H1.5 V7 H0 Z"
  local LEG, FAR, REST = 10, 12, 2
  local OUTWARD = {{-1,-1},{1,-1},{-1,1},{1,1}}
  local BRACKETS = {
    {{left=true,top=true},("M1 %g V1 H%g"):format(LEG,LEG)},
    {{right=true,top=true},("M0 1 H%g V%g"):format(LEG-1,LEG)},
    {{left=true,bottom=true},("M1 0 V%g H%g"):format(LEG-1,LEG)},
    {{right=true,bottom=true},("M0 %g H%g V0"):format(LEG-1,LEG-1)},
  }

  --- Whether `id` names an on-screen keyboard's key.
  local function keyed(id)
    return type(id) == "string" and id:find("osk", 1, true) ~= nil and id:find(".key.", 1, true) ~= nil
  end
  --- The pieces in `holder` from z `z`; `size()` gives the target's box.
  --- `plain` (and a keyboard's key) keeps the plain feedback: no reticle,
  --- no scan. Returns `react(over, down)`, to call whenever either changes.
  local function pieces(holder, id, size, z, plain)
    z = z or 0
    local key = plain or keyed(id)
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
    -- A press sends a bright bar with a short trail across the control.
    local scan = not key and ui.Item { id=id.."-scan",x=-16,width=16,anchors={top=true,bottom=true},opacity=0,
      ui.Rect { width=13,anchors={top=true,bottom=true},
        gradient=function() return {angle=90,stops={C.primary:alpha(0),C.primary:alpha(.5)}} end },
      ui.Rect { x=13,width=3,anchors={top=true,bottom=true},color=function() return C.primary end },
    } or nil
    ui.reparent(ui.Item { id=id.."-glint-clip",anchors={fill=true},clip=true,z=z+1,glint,scan },holder)
    -- A key keeps its registration marks on the diagonal; anything else
    -- has four brackets that close in onto its corners from further out.
    local marks={}
    if key then
      for i,corner in ipairs {{left=true,top=true},{right=true,bottom=true}} do
        marks[i]=ui.Path {id=id.."-mark-"..i,anchors=corner,width=7,height=7,z=z+2,
          view_box={0,0,7,7},d=MARK,rotation=i==1 and 0 or 180,
          fill_color=function() return C.primary end,opacity=0,
          behavior={translate_x={duration=340,easing="out_cubic"},translate_y={duration=340,easing="out_cubic"},
            opacity={duration=180}}}
        ui.reparent(marks[i],holder)
      end
    else
      for i,corner in ipairs(BRACKETS) do
        marks[i]=ui.Path {id=id.."-mark-"..i,anchors=corner[1],width=LEG,height=LEG,z=z+2,
          view_box={0,0,LEG,LEG},d=corner[2],fill_color="transparent",stroke_width=2,stroke_cap="square",
          stroke_color=function() return C.primary end,opacity=0}
        ui.reparent(marks[i],holder)
      end
    end
    local hovered,pressed,running,scanning,closing=false,false,nil,nil,nil
    return function(over, down)
      local entering,pressing=over and not hovered,down and not pressed
      hovered,pressed=over,down
      wash.opacity=down and 0.18 or over and 0.055 or 0
      if closing then closing:stop() closing=nil end
      local reticle={}
      for i,mark in ipairs(marks) do
        if key then
          local s=(over and not down) and (i==1 and -3 or 3) or 0
          mark.translate_x,mark.translate_y=s,s
        else
          for axis,property in ipairs {"translate_x","translate_y"} do
            local out=OUTWARD[i][axis]
            local rest=(over and not down) and out*REST or 0
            if entering and not down then
              reticle[#reticle+1]={node=mark,property=property,duration=240,keyframes={
                {at=0,value=out*FAR},{at=.55,value=-out,easing="out_cubic"},{at=1,value=rest,easing="out_quad"}}}
            else
              mark[property]=rest
            end
          end
        end
        mark.opacity=over and 1 or 0
      end
      if #reticle>0 then closing=morf.animation.play {{parallel=reticle},on_finished=function() closing=nil end} end
      -- Let go, a sweep under way runs out on its own.
      if not over and not down then return end
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
      if pressing and scan and w>2 then
        if scanning then scanning:stop() end
        scanning=morf.animation.play {{parallel={
          {node=scan,property="translate_x",from=0,to=w+16,duration=260,easing="out_cubic"},
          {node=scan,property="opacity",duration=280,keyframes={
            {at=0,value=0},{at=.08,value=1},{at=.7,value=.8},{at=1,value=0},
          }},
          {node=wash,property="opacity",duration=280,keyframes={
            {at=0,value=.34},{at=1,value=.18,easing="out_cubic"},
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
  return attach, pieces, keyed
end
