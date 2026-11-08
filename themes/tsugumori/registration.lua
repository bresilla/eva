-- Bounded registration cues. They decorate their host without moving content,
-- receiving input, scheduling idle work or interpreting authentication replies.
local morf=require("morf")
local ui=require("morf.ui")
return function(theme)
  return function(host,id)
    local marks={}
    for i,anchor in ipairs {{left=true,top=true},{right=true,bottom=true}} do
      marks[i]=ui.Path {id=id.."-register-"..i,z=105,anchors=anchor,
        width=18,height=18,view_box={0,0,18,18},rotation=i==2 and 180 or 0,
        d="M0 0 H18 V2 H2 V18 H0 Z",opacity=0,
        fill_color=function() return theme.color.secondary end}
      ui.reparent(marks[i],host)
    end
    local edge=ui.Rect {id=id.."-result-edge",z=105,width=3,
      anchors={left=true,top=true,bottom=true},opacity=0,
      color=function() return theme.color.primary end}
    ui.reparent(edge,host)
    -- An arrival is a target lock: four heavy brackets close onto the box
    -- from well outside it, a scan crosses it and its header band flashes.
    local lock,flash
    local running,pending
    return function(kind,delay)
      if pending then pending:cancel() pending=nil end
      if running then running:stop() running=nil end
      if lock then lock.stop(kind==nil) end
      for _,node in ipairs(marks) do
        node.opacity,node.translate_x,node.translate_y=0,0,0
      end
      edge.opacity=0
      if flash then flash.visible,flash.opacity=false,0 end
      if not kind then return end
      local duration=kind=="arrival" and 440 or 340
      local steps={}
      for i,node in ipairs(marks) do
        local sign=i==1 and -1 or 1
        local peak=kind=="arrival" and 1 or .8
        steps[#steps+1]={node=node,property="opacity",duration=duration,
          keyframes={{at=0,value=0},{at=.16,value=peak},{at=.5,value=peak*.56},{at=1,value=0}}}
        if kind=="failure" then
          steps[#steps+1]={node=node,property="translate_x",duration=duration,
            keyframes={{at=0,value=0},{at=.14,value=sign*5},{at=.36,value=-sign*2},{at=.65,value=0},{at=1,value=0}}}
        else
          for _,property in ipairs {"translate_x","translate_y"} do
            steps[#steps+1]={node=node,property=property,from=sign*(kind=="arrival" and 22 or 8),to=0,
              duration=duration,easing="out_cubic"}
          end
        end
      end
      if kind=="success" then
        steps[#steps+1]={node=edge,property="opacity",duration=duration,
          keyframes={{at=0,value=0},{at=.12,value=.85},{at=.45,value=.5},{at=1,value=0}}}
      end
      if kind=="arrival" then
        if not flash then
          flash=ui.Rect {id=id.."-header-flash",z=104,height=34,
            anchors={left=true,right=true,top=true},opacity=0,visible=false,
            color=function() return theme.color.primary end}
          ui.reparent(flash,host)
        end
        steps[#steps+1]={node=flash,property="opacity",duration=460,keyframes={
          {at=0,value=0},{at=.08,value=.5},{at=.2,value=.08},{at=.32,value=.38},{at=1,value=0}}}
      end
      local function start()
        pending=nil
        if flash and kind=="arrival" then flash.visible=true end
        running=morf.animation.play {{parallel=steps},on_finished=function(reason)
          if reason=="completed" and flash then flash.visible=false end
        end}
        if kind=="arrival" then
          lock=lock or require("themes.tsugumori.boot")(theme).new(host,id,
            {trace=false,register=false,length=22,weight=3,reach=40,z=106})
          lock.play()
        end
      end
      if delay and delay>0 then pending=morf.time.timer(delay,start,false) else start() end
    end
  end
end
