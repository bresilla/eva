-- Direct manipulation uses surface displacement, never coordinates relative
-- to the moving drawer. The theme's motion owns the panel: this only says
-- where the finger is and what the release decided.
local motion = require("gesture_motion")
local M = {}

function M.attach(d, ctx, theme_motion)
  local panel, axis = d.panel, ctx.axis
  local drag
  function d.interrupt_drag()
    theme_motion.stop()
    drag = nil
    d.manual = false
  end
  function d.begin_drag()
    if ctx.floating then return false end
    local was_open = d.open:get()
    theme_motion.stop()
    local origin = theme_motion.grab(panel.visible and panel[axis] or ctx.tucked())
    d.manual = true
    drag = { origin = origin, at = origin, was_open = was_open, delta = 0 }
    d.open:set(true)
    return true
  end
  function d.drag_by(delta)
    if not drag then return end
    drag.delta = delta
    local tucked = ctx.tucked()
    drag.at = math.max(math.min(0,tucked), math.min(math.max(0,tucked), drag.origin + delta))
    theme_motion.drag(drag.at)
  end
  function d.end_drag(velocity, canceled)
    if not drag then return end
    local tucked = ctx.tucked()
    local size = math.max(1, math.abs(tucked))
    local progress = 1 - math.abs(drag.at) / size
    local opening_velocity = velocity * (tucked > 0 and -1 or 1)
    local opening = progress >= 0.5
    if canceled then opening = drag.was_open
    elseif motion.fling(drag.delta, opening_velocity) then
      opening = opening_velocity > 0
    end
    drag = nil
    d.open:set(opening)
    theme_motion.release(canceled and 0 or velocity, function() d.manual = false end)
  end
end
return M
