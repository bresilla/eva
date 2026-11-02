-- One finger out of many short touches. A touchscreen can report a fast finger
-- as a run of contacts, each lifting and landing a little further on within a
-- few milliseconds. A lift waits GAP; a landing within REACH of it carries that
-- finger on, and otherwise the lift stands.
--
--   local stitch = require("touch_stitch").new(recogniser)
--   stitch.down(id, x, y, t)  stitch.move(id, x, y)  stitch.up(id, t)
--   stitch.flush(t)           -- lets go of lifts older than GAP, true if any went
local M = { GAP = 60, REACH = 320 }

function M.new(target)
  local s = {}
  -- `live`: each contact's finger. `lifted`: fingers waiting to see if they land.
  local live, lifted, place, serial = {}, {}, {}, 0

  --- Lets go of lifts older than GAP; true when any went.
  function s.flush(t)
    local any = false
    for finger, at in pairs(lifted) do
      if t - at > M.GAP then
        lifted[finger], place[finger] = nil, nil
        target.up(finger, at)
        any = true
      end
    end
    return any
  end

  local function nearest(x, y)
    local found, best
    for finger in pairs(lifted) do
      local p = place[finger]
      local away = math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)
      if away <= M.REACH and (not best or away < best) then found, best = finger, away end
    end
    return found
  end

  function s.down(id, x, y, t)
    s.flush(t)
    local finger = nearest(x, y)
    if finger then
      lifted[finger] = nil
      live[id] = finger
      place[finger] = { x = x, y = y }
      target.move(finger, x, y)
      return
    end
    serial = serial + 1
    live[id], place[serial] = serial, { x = x, y = y }
    target.down(serial, x, y, t)
  end

  function s.move(id, x, y)
    local finger = live[id]
    if not finger then return end
    place[finger] = { x = x, y = y }
    target.move(finger, x, y)
  end

  function s.up(id, t)
    local finger = live[id]
    if not finger then return end
    live[id] = nil
    lifted[finger] = t
  end

  function s.cancel()
    live, lifted, place = {}, {}, {}
    target.cancel()
  end

  return s
end

return M
