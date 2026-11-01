-- Contacts into gestures, in logical pixels. Pure logic with no nodes, so a spec
-- drives it with numbers. Fed `down`, `move`, `up` and `frame` as the touchscreen
-- reports them, and `tick` while fingers rest; it answers through `on(event)`:
--
--   local g = require("touch_gestures").new {
--     size = function() return 1280, 800 end,
--     regions = function() return { { name = "keyboard", x = 0, y = 500, width = 1280, height = 300 } } end,
--     on = function(event) end,
--   }
--
-- An event is `{ phase, kind, fingers, direction, edge, region, x, y, dx, dy, travel,
-- progress, vx, vy, spread, committed }`. `phase` is begin, update, end or cancel.
-- `kind` is swipe, pinch, tap or hold; a swipe's `direction` is up, down, left or
-- right and a pinch's in or out. `dx`, `dy` run from where the fingers landed,
-- `travel` along the direction, `progress` from 0 to 1 at TRAVEL. `end` carries
-- velocity in pixels a second, and `committed` when it went far or fast enough.
--
-- One or two fingers swipe only from an edge they started near, or from a region:
-- a scroll in an app is two fingers anywhere else. Three or more swipe anywhere,
-- and pinch. Every finger must travel with the rest.
local motion = require("gesture_motion")

local M = {
  BAND = 64,      -- How near an edge a finger lands to have started from it.
  GATHER = 250,   -- Fingers of one gesture land within this many ms of the first.
  SLOP = 12,      -- A finger moving less than this has not moved.
  START = 32,     -- How far the fingers go together before a swipe begins.
  PINCH = 32,     -- How far the fingers spread or close before a pinch begins.
  PINCH_SHARE = .15, -- And what share of their spread that must be.
  TRAVEL = 96,    -- The travel that commits on release, at any speed.
  WANDER = 3,     -- Past START this many times with no direction, nothing follows.
  AXIS = 1.2,     -- How much one axis must lead the other.
  TOGETHER = .5,  -- The share of the fingers' travel each finger must make.
  TAP = 250,      -- Lifted within this many ms, a tap.
  HOLD = 500,     -- Resting for this many ms, a long press.
  WINDOW = 100,   -- The ms of motion a release velocity is read from.
}

-- The way a finger leaves each edge.
local INWARD = { bottom = "up", top = "down", left = "right", right = "left" }
local WORDS = { "one", "two", "three", "four", "five" }

--- The name a gesture is bound under: `two_up_bottom`, `three_left`, `five_pinch_in`.
function M.key(event)
  local count = WORDS[event.fingers]
  if not count then return nil end
  if event.kind == "tap" or event.kind == "hold" then return count .. "_" .. event.kind end
  if event.kind == "pinch" then return count .. "_pinch_" .. event.direction end
  local origin = event.fingers <= 2 and (event.region or event.edge) or nil
  return count .. "_" .. event.direction .. (origin and ("_" .. origin) or "")
end

local function mean(list, read)
  local sum = 0
  for _, item in ipairs(list) do sum = sum + read(item) end
  return sum / math.max(1, #list)
end

function M.new(spec)
  local r = {}
  local contacts, fingers, run = {}, {}, nil
  local function say(event) spec.on(event) end

  local function fresh(t)
    return { start = t, last = t, peak = 0, spent = false, lifted = false, moved = false,
      shift_x = 0, shift_y = 0, history = {} }
  end

  local function shared(gesture, phase)
    return { phase = phase, kind = gesture.kind, fingers = gesture.fingers, direction = gesture.direction,
      edge = gesture.edge, region = gesture.region, x = gesture.x, y = gesture.y }
  end

  local function displacement()
    return mean(fingers, function(f) return f.x - f.sx end) + run.shift_x,
      mean(fingers, function(f) return f.y - f.sy end) + run.shift_y
  end

  -- How far apart the fingers are: at landing, and now.
  local function spreads()
    local cx0, cy0 = mean(fingers, function(f) return f.sx end), mean(fingers, function(f) return f.sy end)
    local cx, cy = mean(fingers, function(f) return f.x end), mean(fingers, function(f) return f.y end)
    return mean(fingers, function(f) return math.sqrt((f.sx - cx0) ^ 2 + (f.sy - cy0) ^ 2) end),
      mean(fingers, function(f) return math.sqrt((f.x - cx) ^ 2 + (f.y - cy) ^ 2) end), cx, cy, cx0, cy0
  end

  local function near_edges()
    local w, h = spec.size()
    local out = {}
    for _, f in ipairs(fingers) do
      if f.sy >= h - M.BAND then out.bottom = true end
      if f.sy <= M.BAND then out.top = true end
      if f.sx <= M.BAND then out.left = true end
      if f.sx >= w - M.BAND then out.right = true end
    end
    return out
  end

  local function within(region, f)
    return f.sx >= region.x and f.sx < region.x + region.width and f.sy >= region.y and f.sy < region.y + region.height
  end

  local function region_of()
    for _, region in ipairs(spec.regions and spec.regions() or {}) do
      local all = true
      for _, f in ipairs(fingers) do all = all and within(region, f) end
      if all then return region.name end
    end
  end

  local function direction_of(dx, dy)
    if math.abs(dx) > math.abs(dy) * M.AXIS then return dx < 0 and "left" or "right" end
    if math.abs(dy) > math.abs(dx) * M.AXIS then return dy < 0 and "up" or "down" end
  end

  local UNIT = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

  local function together(direction, travel)
    local unit = UNIT[direction]
    for _, f in ipairs(fingers) do
      if (f.x - f.sx) * unit[1] + (f.y - f.sy) * unit[2] < travel * M.TOGETHER then return false end
    end
    return true
  end

  local function radial(change)
    local _, _, cx, cy, cx0, cy0 = spreads()
    for _, f in ipairs(fingers) do
      local from = math.sqrt((f.sx - cx0) ^ 2 + (f.sy - cy0) ^ 2)
      local to = math.sqrt((f.x - cx) ^ 2 + (f.y - cy) ^ 2)
      if (to - from) * (change < 0 and -1 or 1) < math.abs(change) * .3 then return false end
    end
    return true
  end

  local function record(t, a, b)
    local history = run.history
    history[#history + 1] = { t = t, a = a, b = b }
    while #history > 2 and t - history[1].t > M.WINDOW do table.remove(history, 1) end
  end

  local function velocity()
    local history = run.history
    local first, last = history[1], history[#history]
    if not first or last.t - first.t < 4 then return 0, 0 end
    local seconds = (last.t - first.t) / 1000
    return (last.a - first.a) / seconds, (last.b - first.b) / seconds
  end

  -- Where the gesture stands: a pinch by its spread, a swipe along its direction.
  local function measure(event)
    local gesture = run.gesture
    if gesture.kind == "pinch" then
      local from, to = spreads()
      event.spread, event.travel = to, gesture.direction == "in" and from - to or to - from
      event.dx, event.dy = 0, 0
    else
      local dx, dy = displacement()
      local unit = UNIT[gesture.direction]
      event.dx, event.dy, event.travel = dx, dy, unit and dx * unit[1] + dy * unit[2] or 0
    end
    event.progress = math.max(0, math.min(1, event.travel / M.TRAVEL))
    return event
  end

  local function begin(kind, direction, n, edge, region)
    local _, _, _, _, cx0, cy0 = spreads()
    run.gesture = { kind = kind, direction = direction, fingers = n, edge = edge, region = region, x = cx0, y = cy0 }
    run.spent = true
    local event = measure(shared(run.gesture, "begin"))
    run.last_dx, run.last_dy, run.last_travel = event.dx, event.dy, event.travel
    record(run.last, event.dx, event.dy)
    say(event)
  end

  local function decide(t)
    if run.lifted or #fingers == 0 then return end
    local n = #fingers
    local dx, dy = displacement()
    local travel = math.sqrt(dx * dx + dy * dy)
    if n >= 3 then
      local from, to = spreads()
      local change = to - from
      if math.abs(change) >= math.max(M.PINCH, from * M.PINCH_SHARE) and math.abs(change) >= travel
        and radial(change) then
        return begin("pinch", change < 0 and "in" or "out", n, nil, region_of())
      end
    end
    if travel < M.START then return end
    local direction = direction_of(dx, dy)
    if direction and together(direction, travel) then
      local edges, edge = near_edges(), nil
      for name, inward in pairs(INWARD) do
        if edges[name] and inward == direction then edge = name end
      end
      local region = region_of()
      if n >= 3 or edge or region then return begin("swipe", direction, n, edge, region) end
      run.spent = true
    elseif travel >= M.START * M.WANDER then
      run.spent = true
    end
  end

  -- A pinch is read while every finger is down: the spread of what stays is another.
  local function advance(t)
    local gesture = run.gesture
    if gesture.kind == "hold" or #fingers == 0 or (gesture.kind == "pinch" and run.lifted) then return end
    local event = measure(shared(gesture, "update"))
    run.last_dx, run.last_dy, run.last_travel = event.dx, event.dy, event.travel
    record(t, event.dx, event.dy)
    say(event)
  end

  local function conclude(t)
    local gesture = run.gesture
    if gesture then
      local vx, vy = run.vx, run.vy
      if vx == nil then vx, vy = velocity() end
      local event = shared(gesture, "end")
      event.dx, event.dy, event.travel = run.last_dx or 0, run.last_dy or 0, run.last_travel or 0
      event.vx, event.vy = vx, vy
      if gesture.kind == "swipe" then
        local unit = UNIT[gesture.direction]
        local speed = vx * unit[1] + vy * unit[2]
        event.committed = event.travel >= M.TRAVEL
        if motion.fling(event.travel, speed) then event.committed = speed > 0 and event.travel > 0 end
      elseif gesture.kind == "pinch" then
        event.committed = event.travel >= M.TRAVEL
      else
        event.committed = true
      end
      event.progress = math.max(0, math.min(1, event.travel / M.TRAVEL))
      say(event)
    elseif not run.spent and not run.moved and t - run.start <= M.TAP and run.peak >= 1 then
      local tap = { kind = "tap", fingers = run.peak, x = run.x, y = run.y }
      local opened = shared(tap, "begin")
      say(opened)
      local closed = shared(tap, "end")
      closed.committed = true
      say(closed)
    end
    run = nil
  end

  --- A finger came down.
  function r.down(id, x, y, t)
    if contacts[id] then return end
    local finger = { id = id, x = x, y = y, sx = x, sy = y }
    contacts[id] = finger
    -- Fingers that have rested past the gather stay out of what comes next.
    if run and not run.gesture and t - run.start > M.GATHER then
      for _, f in ipairs(fingers) do f.resting = true end
      fingers, run = {}, nil
    end
    if not run then
      run = fresh(t)
      run.x, run.y = x, y
    end
    if run.gesture then
      if t - run.start > M.GATHER then finger.resting = true return end
      -- A finger joining what has just begun: the count was wrong.
      say(shared(run.gesture, "cancel"))
      run.gesture, run.spent, run.history = nil, false, {}
      for _, f in ipairs(fingers) do f.sx, f.sy = f.x, f.y end
    end
    fingers[#fingers + 1] = finger
    run.peak = math.max(run.peak, #fingers)
  end

  --- A finger moved.
  function r.move(id, x, y)
    local finger = contacts[id]
    if not finger then return end
    finger.x, finger.y = x, y
    if finger.resting or not run then return end
    if math.abs(x - finger.sx) > M.SLOP or math.abs(y - finger.sy) > M.SLOP then run.moved = true end
  end

  --- A finger lifted.
  function r.up(id, t)
    local finger = contacts[id]
    if not finger then return end
    contacts[id] = nil
    if finger.resting or not run then return end
    run.lifted = true
    if run.gesture and run.vx == nil then run.vx, run.vy = velocity() end
    -- Whatever fingers stay carry on from where the group had got to.
    local before_x, before_y = 0, 0
    if #fingers > 1 then before_x, before_y = displacement() end
    for index, f in ipairs(fingers) do
      if f == finger then table.remove(fingers, index) break end
    end
    if #fingers > 0 then
      run.shift_x, run.shift_y = 0, 0
      local after_x, after_y = displacement()
      run.shift_x, run.shift_y = before_x - after_x, before_y - after_y
    end
  end

  --- The end of a report: a set of contacts that belong together.
  function r.frame(t)
    if not run then return end
    t = t or run.last
    run.last = t
    if run.gesture then
      advance(t)
    elseif not run.spent then
      decide(t)
    end
    if #fingers == 0 then conclude(t) end
  end

  --- The clock, while fingers rest: a long press has no report to come from.
  function r.tick(t)
    if not run or run.gesture or run.spent or run.lifted or run.moved or #fingers == 0 then return end
    if t - run.start >= M.HOLD then
      begin("hold", nil, #fingers, nil, region_of())
    end
  end

  --- Everything stops: what was under way is cancelled.
  function r.cancel()
    if run and run.gesture then say(shared(run.gesture, "cancel")) end
    contacts, fingers, run = {}, {}, nil
  end

  --- The contacts down now, each `{ id, x, y }`, for a picture of the fingers.
  function r.contacts()
    local out = {}
    for _, f in pairs(contacts) do out[#out + 1] = { id = f.id, x = f.x, y = f.y, resting = f.resting == true } end
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return out
  end

  --- How many fingers are down.
  function r.count()
    local n = 0
    for _ in pairs(contacts) do n = n + 1 end
    return n
  end

  return r
end

return M
