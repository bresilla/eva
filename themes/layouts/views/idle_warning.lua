-- The warning before an idle lock: the frame closes in as a distance field,
-- its edge soft, darkening towards the middle for as long as the warning runs.
-- Input is what cancels it, so it takes none: it has no pressable area, and all
-- of it fades away on a spring.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local C = theme.color
local V = {}

--- `spec`: `width`, `height`, `duration` (ms), `closing` (fn: the warning stands),
--- `text`.
function V.build(spec)
  local W, H, closing = spec.width, spec.height, spec.closing
  local short = math.min(W, H)
  local SOFT = math.floor(short * .22)
  local INSET = math.floor(short * .26)
  local ramp = { duration = spec.duration, easing = "linear" }
  -- The ramp only runs forward: a warning cut short goes with the outer fade.
  local ran = morf.signal("eva.idle.ran." .. tostring({}), false)
  local function closed() return ran:get() end
  local opening = ui.SdfShape {
    id = "idle-warning-opening", shape = "box", operation = "smooth_subtract", blend = SOFT,
    radius = math.floor(short * .12),
    x = function() return closed() and INSET or -SOFT end,
    y = function() return closed() and INSET or -SOFT end,
    width = function() return closed() and W - 2 * INSET or W + 2 * SOFT end,
    height = function() return closed() and H - 2 * INSET or H + 2 * SOFT end,
    behavior = { x = ramp, y = ramp, width = ramp, height = ramp },
  }
  local field = ui.Sdf { id = "idle-warning-field", anchors = { fill = true },
    fill_color = function() return C.surfaceContainerLowest:alpha(.86) end,
    opacity = function() return closed() and 1 or 0 end,
    behavior = { opacity = ramp },
    ui.SdfShape { shape = "box", x = 0, y = 0, width = W, height = H },
    opening,
  }
  local words = kit.text { id = "idle-warning-text", anchors = { center_in = true },
    text = spec.text, font_size = theme.size.normal, color = kit.ink("hi"),
    opacity = function() return closed() and 1 or 0 end,
    behavior = { opacity = { duration = math.min(spec.duration, 1200) } } }
  local root = ui.Item { id = "idle-warning", anchors = { fill = true },
    opacity = function() return closing() and 1 or 0 end,
    behavior = { opacity = theme.spring.spatial },
    field, words }
  morf.effect("eva.idle.ramp", function() if closing() then ran:set(true) end end, { owner = root })
  return root
end

return V
