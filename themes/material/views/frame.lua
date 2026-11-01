-- Material's rounded opening, circular seams and inward shadow.
local ui=require("morf.ui")
local theme=require("theme")
local V={}
function V.insets(bar)
  bar=bar or {left=0,top=0,right=0,bottom=0}
  return {left=theme.LEFT+bar.left,top=theme.BORDER+bar.top,
    right=theme.BORDER+bar.right,bottom=theme.BORDER+bar.bottom}
end
--- The frame's paint on `props`, for any field that joins it.
function V.paint(props)
  props.fill_color=function() return theme.color.surface end
  props.blend,props.blend_profile=theme.SEAM,"circular"
  props.shadow_color,props.shadow_blur="#000000a0",6
  return props
end
function V.build(model)
  local reveal=require("themes.reveal")
  local hidden,rest=reveal.opening(model.desk,theme.LEFT,theme.BORDER,2*theme.ROUNDING)
  local opening=reveal.part(ui.SdfShape,{id="frame-opening",shape="box",operation="subtract",radius=theme.ROUNDING,
      x=function() local x=model.desk() return x+theme.LEFT end,
      y=function() local _,y=model.desk() return y+theme.BORDER end,
      width=function() local _,_,w=model.desk() return w-theme.LEFT-theme.BORDER end,
      height=function() local _,_,_,h=model.desk() return h-2*theme.BORDER end},0,hidden,rest)
  local transition=require("themes.session").transition
  require("themes.switcher").morph(opening,"radius",theme.ROUNDING,transition and transition.frame_rounding)
  local field=V.paint {id="frame",anchors={fill=true},
    ui.SdfShape {shape="box",anchors={fill=true}},
    opening,
  }
  for _,drawer in ipairs(model.drawers) do field[#field+1]=drawer.shape end
  field[#field+1]=model.rail.shape
  field[#field+1]=model.levels.shape
  return require("themes.frame_host")(model,ui.Sdf(field),V.insets())
end
return V
