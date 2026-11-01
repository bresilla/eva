-- Shared scene composition, with geometry and painting supplied by a theme.
-- Input policies arrive as controller-built planes; this module adds none.
local ui=require("morf.ui")
local reveal=require("themes.reveal")

-- The part `node`, kept past the `edge()` of the screen by `reach` until it
-- arrives.
local function arriving(id,node,order,edge,reach)
  local function axis() return (edge()=="left" or edge()=="right") and "translate_x" or "translate_y" end
  return reveal.part(ui.Item,{id=id,anchors={fill=true},node},order,
    function() return {[axis()]=(edge()=="left" or edge()=="top") and -reach or reach,opacity=0} end,
    function() return {[axis()]=0,opacity=1} end)
end

return function(model,frame,insets,decorations)
  local theme=require("theme")
  local panels={id="opening",anchors={fill=true,left_margin=insets.left,top_margin=insets.top,
    right_margin=insets.right,bottom_margin=insets.bottom},clip=true}
  for _,node in ipairs(model.overlays) do panels[#panels+1]=node end
  local docked={id="keyboard-dock",anchors={fill=true,bottom_margin=theme.BORDER},clip=true}
  for _,drawer in ipairs(model.drawers) do
    local host=drawer.docked and docked or panels
    host[#host+1]=drawer.panel
  end
  local function rail_edge() return require("responsive").portrait() and "bottom" or "left" end
  local desk={id="desk",x=function() local x=model.desk() return x end,
    y=function() local _,y=model.desk() return y end,
    width=function() local _,_,w=model.desk() return w end,
    height=function() local _,_,_,h=model.desk() return h end,
    arriving("arrival-rail",model.rail.node,1,rail_edge,theme.LEFT),
    arriving("arrival-levels",model.levels.node,1,function() return "right" end,theme.BORDER)}
  if decorations then desk[#desk+1]=arriving("arrival-marks",decorations,1,rail_edge,theme.LEFT) end
  desk[#desk+1]=ui.Item(panels)
  for _,trigger in ipairs(model.triggers) do desk[#desk+1]=trigger end
  local switcher=require("themes.switcher")
  for _,drawer in ipairs(model.drawers) do switcher.attach(drawer) end
  local transition=require("themes.session").transition
  switcher.morph(frame,"blend",theme.SEAM,transition and transition.seam)
  for _,node in ipairs {model.bar,model.rail.node,model.levels.node} do switcher.fade(node) end
  switcher.fade(decorations)
  local bar=arriving("arrival-bar",model.bar,2,model.bar_edge or function() return "top" end,model.bar_reach or theme.BORDER)
  local plate=require("themes.glass_plate").build(model,insets)
  return ui.Item {anchors={fill=true},plate,frame,bar,ui.Item(desk),ui.Item(docked),switcher.blocker()}
end
