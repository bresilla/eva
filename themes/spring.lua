-- Damped springs as motion. A spring is `{ stiffness, ratio }`, the ratio being
-- its damping against critical (1 settles without overshoot, 0.5 bounces):
--
--   spring.behavior(s)   a `ui.spring`, for a property retargeted while it moves
--   spring.curve(s)      `{ duration, easing }`, the same response as a spline,
--                        for a step of `morf.animation.play`
local ui = require("morf.ui")
local M = {}

local SEGMENTS = 14
-- Settled once within this fraction of the distance travelled.
local REST = 0.002

--- The damping `ui.spring` takes for `s`.
function M.damping(s)
  return 2 * s.ratio * math.sqrt(s.stiffness)
end

function M.behavior(s)
  return ui.spring { stiffness = s.stiffness, damping = M.damping(s) }
end

-- Position and velocity of a unit step, `t` seconds in.
local function response(s, t)
  local natural = math.sqrt(s.stiffness)
  if s.ratio >= 1 then
    local decay = math.exp(-natural * t)
    return 1 - decay * (1 + natural * t), decay * natural * natural * t
  end
  local rate = s.ratio * natural
  local ringing = natural * math.sqrt(1 - s.ratio * s.ratio)
  local decay = math.exp(-rate * t)
  local cosine, sine = math.cos(ringing * t), math.sin(ringing * t)
  return 1 - decay * (cosine + rate / ringing * sine), decay * (rate * rate / ringing + ringing) * sine
end

--- How long `s` takes to settle, in seconds.
function M.settle(s)
  local natural = math.sqrt(s.stiffness)
  local rate = math.min(s.ratio, 1) * natural
  local seconds = -math.log(REST) / rate
  return s.ratio >= 1 and seconds * 1.35 or seconds
end

function M.curve(s)
  local total = M.settle(s)
  local width = 1 / SEGMENTS
  local points = {}
  for i = 1, SEGMENTS do
    local from, to = (i - 1) * width, i * width
    local y0, v0 = response(s, from * total)
    local y1, v1 = response(s, to * total)
    if i == SEGMENTS then y1, v1 = 1, 0 end
    local third = width * total / 3
    for _, value in ipairs { from + width / 3, y0 + v0 * third, to - width / 3, y1 - v1 * third, to, y1 } do
      points[#points + 1] = value
    end
  end
  return { duration = math.floor(total * 1000 + 0.5), easing = { spline = points } }
end

--- `s` with its bounce scaled by a motion style: "calm", "balanced", "playful".
function M.styled(s, style)
  local ratio = s.ratio
  if style == "calm" then ratio = math.min(1, ratio + 0.2)
  elseif style == "playful" then ratio = math.max(0.3, ratio - 0.18) end
  return { stiffness = s.stiffness, ratio = ratio }
end

return M
