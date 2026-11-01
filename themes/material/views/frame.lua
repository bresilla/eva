-- Material's rounded opening, circular seams and inward shadow.
local ui=require("morf.ui")
local theme=require("theme")
local V={}
function V.insets(bar)
  bar=bar or {left=0,top=0,right=0,bottom=0}
  return {left=theme.LEFT+bar.left,top=theme.BORDER+bar.top,
    right=theme.BORDER+bar.right,bottom=theme.BORDER+bar.bottom}
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
  local glass=require("themes.glass")
  local field={id="frame",anchors={fill=true},fill_color=function() return glass.fill(theme.color.surface,1.1) end,
    backdrop_blur=function() return glass.compositor() end,
    stroke_color=function() return glass.on() and theme.color.onSurface:alpha(.14) or "transparent" end,
    stroke_width=function() return glass.on() and 1 or 0 end,
    blend=theme.SEAM,blend_profile="circular",shadow_color="#000000a0",shadow_blur=6,
    ui.SdfShape {shape="box",anchors={fill=true}},
    opening,
  }
  for _,drawer in ipairs(model.drawers) do field[#field+1]=drawer.shape end
  field[#field+1]=model.rail.shape
  field[#field+1]=model.levels.shape
  return require("themes.frame_host")(model,ui.Sdf(field),V.insets())
end
return V
