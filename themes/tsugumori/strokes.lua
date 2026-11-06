-- Decorative lines follow the wallpaper accent without competing with text.
-- Keep these separate from palette roles: muted text and status ink stay legible.
local opacity = { quiet = .16, idle = .3, corner = .6, hover = .6, focus = .85 }
return function(colors, role)
  return colors.primary:alpha(assert(opacity[role or "idle"], "unknown stroke role"))
end
