-- The call screen in the shell: the theme's colours, press targets and bounce.
local kit = require("kit")
local theme = require("theme")
local V = {}

--- `spec`: `phone`, `width`, `height` (fns), `compact`.
function V.build(spec)
  local bounce = theme.bounce and theme.bounce.spatial or {}
  return require("themes.call_screen").build {
    phone = spec.phone, width = spec.width, height = spec.height, compact = spec.compact,
    look = {
      C = theme.color, text = kit.text, icon = kit.icon, action = kit.action, round = kit.round,
      bounce = { duration = bounce.duration or 300, easing = bounce.easing or "out_back" },
    },
  }
end
return V
