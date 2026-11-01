-- A drawer's travel, held by claims: a spring aimed where it belongs, re-aimed
-- in flight and when its size changes, and a hand that takes it over and gives
-- it back at the finger's speed. Non-visual: each theme gives its own spring.
local morf = require("morf")
local ui = require("morf.ui")
local M = {}

-- A release coasts at the finger's speed until the spring has taken over.
local COAST = { seconds = 0.2, easing = "linear" }
-- The fastest release handed to the spring, in px/s.
local CARRY = 2400

--- `node`, `property`, `name`, `spring`; `out` (fn: whether it belongs out,
--- at 0), `away` (fn: where it tucks), `landed` (called on arriving at either).
--- Returns `away` (a 0..1 presence, 1 while tucked or tucking) and
--- `grab`, `drag`, `release`, `stop`, `arrived`.
function M.new(spec)
  local node, property = spec.node, spec.property
  local hand = morf.signal(spec.name .. ".hand", 0)
  local flight = morf.signal(spec.name .. ".flight", 0)
  local held = morf.signal(spec.name .. ".held", false)
  local thrown = morf.signal(spec.name .. ".thrown", false)
  local claims = ui.claims(node, {
    motion = spec.spring,
    hand = { class = "state", when = held, motion = { duration = 0 }, set = { [property] = hand } },
    throw = { class = "state", when = thrown, set = { [property] = flight },
      motion = { duration = COAST.seconds * 1000, easing = COAST.easing } },
    out = { class = "posture", when = spec.out, set = { [property] = 0 } },
    away = { set = { [property] = spec.away } },
  })
  local after
  local A = { away = claims.away.presence }

  -- The spring takes over on the first frame that saw the coast begin.
  morf.effect(spec.name .. ".thrown", function()
    if claims.throw.presence:get() > 0 then thrown:set(false) end
  end, { owner = node })

  local function current() return spec.out() and claims.out or claims.away end
  --- Whether it stands where `spec.out` says it belongs, with nothing holding it.
  function A.arrived()
    return not held:get() and not thrown:get() and current().presence:get() >= 1
  end
  morf.effect(spec.name .. ".landed", function()
    if A.arrived() then
      local done = after
      after = nil
      spec.landed()
      if done then done() end
    end
  end, { owner = node })

  --- Takes it from where it is; returns that place.
  function A.grab(from)
    after = nil
    hand:set(from or node[property])
    thrown:set(false)
    held:set(true)
    return hand:get()
  end
  function A.drag(position) hand:set(position) end
  --- Gives it back at `velocity` px/s; `done` runs once it lands.
  function A.release(velocity, done)
    after = done
    held:set(false)
    velocity = math.max(-CARRY, math.min(CARRY, velocity or 0))
    if velocity ~= 0 then
      flight:set(hand:get() + velocity * COAST.seconds)
      thrown:set(true)
    end
  end
  function A.stop()
    after = nil
    held:set(false)
    thrown:set(false)
  end
  return A
end

return M
