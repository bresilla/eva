-- The same blurred wallpaper behind lock and greet, independent of the skin.
-- On the way out its veil lifts: the last frame is the bare picture.
local ui=require("morf.ui")
local reveal=require("themes.reveal")
return function(ctx,s,role)
  local function path()
    return type(ctx.WALLPAPER)=="function" and ctx.WALLPAPER() or ctx.WALLPAPER or ""
  end
  return ui.Item {id=role.."-auth-backdrop",anchors={fill=true},
    ui.Rect {anchors={fill=true},color=function() return ctx.C.surfaceContainerLowest end},
    ui.Image {id=role.."-wallpaper",anchors={fill=true},fill_mode="preserve_aspect_crop",
      source=path,visible=function() return path()~="" end},
    ui.Rect {id=role.."-veil",anchors={fill=true},backdrop_blur=s(28),
      color=function() return ctx.C.surface:alpha(.4) end,
      opacity=function() return ctx.scene_leaving() and 0 or 1 end,
      behavior={opacity=reveal.MOTION}},
  }
end
