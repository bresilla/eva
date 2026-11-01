-- A surface let go with a swipe: it follows the finger the ways it may leave,
-- resists the others, flies off past its distance or at speed and springs back
-- short of them. With `reveal`, a pull short of the distance latches open and
-- shows what is under it.
--
--     local swipe = require("swipe_dismiss").new {
--       id = "toast", node = card, ways = { left = true, right = true },
--       on_dismiss = function(way) close() end,
--     }
--     card.on_panned = swipe.on_panned
--
-- The node's `translate_x` and `translate_y` are the helper's: a view leaves
-- the ones `ways` moves unset. `ways` is a table or a fn of the start point,
-- with `axes` then saying which axes it can move; `distance` (72 px, or
-- fn(way)) is how far commits, `extent` (fn(axis)) how far it flies, `reveal`
-- (`{ left = px }`) and `on_revealed(way)` (nil on shutting) the latch.
-- `moved` is a signal of how far it stands from rest. A pointer's drag gets
-- the same through `press`, `drag`, `release` and `fling`.
local morf = require("morf")
local theme = require("theme")
local motion = require("gesture_motion")
local rubber = require("rubber_band")
local M = {}

local AXIS = { left = "x", right = "x", up = "y", down = "y" }
local SIGN = { left = -1, right = 1, up = -1, down = 1 }
local AXES = { x = { left = true, right = true }, y = { up = true, down = true } }
-- The most it moves a way it may not leave.
local STIFF = 24

local function get(value, ...) if type(value) == "function" then return value(...) end return value end

local count = 0
function M.new(spec)
  count = count + 1
  local name = "eva.swipe." .. (spec.id or count)
  local s = { moved = morf.signal(name .. ".moved", 0) }
  local axes = {}
  local jumping = morf.signal(name .. ".jumping", false)
  local function can(axis)
    if type(spec.ways) == "function" then return spec.axes == nil or spec.axes[axis] end
    for way in pairs(AXES[axis]) do if spec.ways[way] then return true end end
    return false
  end
  for axis in pairs(AXES) do
    if can(axis) then
      local rest = morf.signal(name .. "." .. axis, 0)
      axes[axis] = { rest = rest, hand = require("themes.drawer_axis").new {
        node = spec.node, property = "translate_" .. axis, name = name .. "." .. axis,
        spring = spec.spring or theme.spring.spatial,
        instant = function() return jumping:get() end,
        out = function() return false end,
        away = function() return rest:get() end,
        landed = function() end,
      } }
    end
  end
  local held
  local opened
  local function settle(on, to, velocity)
    on.rest:set(to)
    on.hand.release(velocity)
    s.moved:set(to)
  end

  local function way_of(axis, travel)
    if axis == "x" then return travel < 0 and "left" or "right" end
    return travel < 0 and "up" or "down"
  end

  --- Where it stands past the distance `way` flies it.
  local function flown(way)
    local axis = AXIS[way]
    local far = spec.extent and spec.extent(axis)
      or (axis == "x" and spec.node.layout_width or spec.node.layout_height) or 0
    return SIGN[way] * (far + theme.space.xxl)
  end

  function s.on_panned(phase, dx, dy, vx, vy, x, y)
    if phase == "begin" then
      if spec.enabled and not spec.enabled() then return false end
      local horizontal = math.abs(dx) > math.abs(dy)
      local axis = horizontal and "x" or "y"
      local on = axes[axis]
      local way = way_of(axis, horizontal and dx or dy)
      local ways = get(spec.ways, x, y)
      local start = on and on.rest:get() or 0
      -- Open, a pull back shuts it whichever way it is.
      if not on or not (ways and ways[way] or start ~= 0) then return false end
      held = { axis = axis, on = on, ways = ways, at = on.hand.grab(), start = start }
    end
    if not held then return end
    local travel = held.axis == "x" and dx or dy
    if phase == "begin" or phase == "update" then
      local at = held.start + travel
      if at ~= 0 and not held.ways[way_of(held.axis, at)] then at = rubber.band(at, STIFF) end
      held.at, held.travel = at, travel
      held.on.hand.drag(at)
      s.moved:set(at)
      return true
    end
    local velocity = held.axis == "x" and vx or vy
    local at = held.at
    local grip = held
    held = nil
    velocity = velocity or 0
    if phase == "cancel" then settle(grip.on, grip.start, 0) return end
    local way = at ~= 0 and way_of(grip.axis, at) or nil
    local free = way and grip.ways[way]
    local distance = get(spec.distance, way) or 72
    local flung = free and motion.fling(grip.travel or 0, velocity) and velocity * SIGN[way] > 0
    local reveal = way and (spec.reveal or {})[way]
    if free and (math.abs(at) >= distance or flung and math.abs(at) >= (reveal or 0)) then
      settle(grip.on, flown(way), velocity)
      s.gone(way)
      return
    end
    if reveal and math.abs(at) >= reveal / 2 and velocity * SIGN[way] >= 0 then
      settle(grip.on, SIGN[way] * reveal, velocity)
      if opened ~= way then
        opened = way
        require("haptics").fire("toggle")
        if spec.on_revealed then spec.on_revealed(way) end
      end
      return
    end
    settle(grip.on, 0, velocity)
    if opened then
      opened = nil
      if spec.on_revealed then spec.on_revealed(nil) end
    end
  end

  --- It is let go `way`: told once, with the buzz of a commit.
  function s.gone(way)
    opened = nil
    require("haptics").fire("commit")
    if spec.on_dismiss then spec.on_dismiss(way) end
  end

  --- Back at rest at once, as a thing shown again.
  function s.reset()
    held, opened = nil, nil
    jumping:set(true)
    s.moved:set(0)
    for _, on in pairs(axes) do on.hand.stop() on.rest:set(0) end
    morf.time.timer(1, function() jumping:set(false) end, false)
  end

  --- Which way it stands latched open, if it does.
  function s.opened() return opened end

  --- A latch shut, on its spring.
  function s.shut()
    opened = nil
    for _, on in pairs(axes) do settle(on, 0, 0) end
    if spec.on_revealed then spec.on_revealed(nil) end
  end

  -- A pointer has no pan: its presses and drags stand in for one.
  local pressed
  function s.press(x, y) pressed = { x = x, y = y, live = false } end
  function s.drag(x, y)
    if not pressed then return end
    local dx, dy = x - pressed.x, y - pressed.y
    if not pressed.live then
      if math.max(math.abs(dx), math.abs(dy)) < theme.space.s then return end
      pressed.live = true
      if s.on_panned("begin", dx, dy, 0, 0, pressed.x, pressed.y) == false then pressed = nil return end
    end
    pressed.dx, pressed.dy = dx, dy
    s.on_panned("update", dx, dy, 0, 0)
  end
  --- Ends a pointer's drag at the speed given, if any. Whether it had moved.
  function s.release(vx, vy)
    local was = pressed
    pressed = nil
    if not (was and was.live) then return false end
    s.on_panned("end", was.dx or 0, was.dy or 0, vx or 0, vy or 0)
    return true
  end
  --- A pointer's flick `way`, told after its release.
  function s.fling(way)
    local on = axes[AXIS[way]]
    local ways = get(spec.ways)
    if not (on and ways and ways[way]) then return false end
    settle(on, flown(way), 0)
    s.gone(way)
    return true
  end
  return s
end

return M
