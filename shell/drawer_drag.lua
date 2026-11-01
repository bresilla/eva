-- Direct manipulation uses surface displacement, never coordinates relative
-- to the moving drawer. The theme's motion owns the panel: this only says
-- where the finger is and what the release decided.
local motion = require("gesture_motion")
local rubber = require("themes.rubber_band")
local M = {}
-- The most a pull moves a panel past where it stands open.
local PAST_OPEN = 32

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
    local from_tucked = not panel.visible
    local origin = theme_motion.grab(from_tucked and ctx.tucked() or panel[axis])
    d.manual = true
    drag = { origin = origin, at = origin, from_tucked = from_tucked, was_open = was_open, delta = 0 }
    d.open:set(true)
    return true
  end
  function d.drag_by(delta)
    if not drag then return end
    drag.delta = delta
    local tucked = ctx.tucked()
    -- A pull from tucked is measured from where tucked is now.
    local origin = drag.from_tucked and tucked or drag.origin
    local at = origin + delta
    -- Past open it runs on elastically; past tucked there is nothing to see.
    if at * tucked < 0 then at = rubber.band(at, PAST_OPEN) end
    drag.at = tucked > 0 and math.min(tucked, at) or math.max(tucked, at)
    theme_motion.drag(drag.at)
  end
  function d.end_drag(velocity, canceled)
    if not drag then return end
    if drag.from_tucked then d.drag_by(drag.delta) end
    local tucked = ctx.tucked()
    local size = math.max(1, math.abs(tucked))
    local progress = 1 - math.max(0, drag.at * (tucked > 0 and 1 or -1)) / size
    local opening_velocity = velocity * (tucked > 0 and -1 or 1)
    local opening = progress >= 0.5
    if canceled then opening = drag.was_open
    elseif motion.fling(drag.delta, opening_velocity) then
      opening = opening_velocity > 0
    end
    if not canceled and opening ~= drag.was_open then require("haptics").fire("commit") end
    drag = nil
    d.open:set(opening)
    theme_motion.release(canceled and 0 or velocity, function() d.manual = false end)
  end
  --- For a panel with nothing else to do with a drag: toward its edge it
  --- pulls it shut under the finger.
  function d.on_panned(phase, dx, dy, vx, vy)
    local across = d.edge == "left" or d.edge == "right"
    local along = across and dx or dy
    if phase == "begin" then
      local toward = (d.edge == "top" or d.edge == "left") and -along or along
      if toward <= 0 or across ~= (math.abs(dx) > math.abs(dy)) then return false end
      return d.begin_drag()
    end
    if phase == "update" then d.drag_by(along)
    else d.end_drag((across and vx or vy) or 0, phase == "cancel") end
  end
end
return M
