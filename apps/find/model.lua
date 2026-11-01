-- eva-find's state: which way it shows the pointer, where the pointer is, the
-- rings of a press, and how long it stays. No nodes.
local morf = require("morf")
local pointer = require("lib.shell.pointer")

local M = {
  mode = morf.signal("find.mode", "spotlight"),
  at = morf.signal("find.at", { x = 0, y = 0 }),
  known = morf.signal("find.known", false),
  up = morf.signal("find.up", false),
  leaving = morf.signal("find.leaving", false),
  rings = morf.list_model({}),
}

M.MODES = { spotlight = true, crosshairs = true, ripple = true }
-- How long the spotlight stays once the pointer rests.
M.MOMENT = 1800
-- How long it takes to go.
M.GONE = 420
-- How long a ring of a press stands before it fades.
M.RING = 480

local serial = 0
local timer

local function stop_timer()
  if timer then timer:cancel() timer = nil end
end

-- The spotlight goes a moment after the pointer last moved.
local function rest()
  stop_timer()
  if M.mode:get() == "spotlight" then timer = morf.time.timer(M.MOMENT, function() M.finish() end, false) end
end

--- The mode a launch asks for: `word` is `--crosshairs`, `crosshairs` or nil.
function M.choose(word)
  local name = tostring(word or ""):gsub("^%-%-", "")
  M.mode:set(M.MODES[name] and name or "spotlight")
end

--- Finds the pointer's first position.
function M.start()
  local x, y = pointer.middle()
  M.at:set { x = x, y = y }
  pointer.start(function(at_x, at_y, known)
    M.known:set(known)
    if M.known:get() then M.at:set { x = at_x, y = at_y } end
  end)
end

--- The overlay is on the screen: the clock starts.
function M.shown()
  M.up:set(true)
  rest()
end

--- The pointer moved to `x`, `y`.
function M.point(x, y)
  M.at:set { x = x, y = y }
  M.known:set(true)
  rest()
end

--- A ring from `x`, `y`, gone by itself.
function M.ripple(x, y)
  serial = serial + 1
  local key = tostring(serial)
  M.rings:insert(M.rings:len() + 1, { key = key, x = x, y = y })
  morf.time.timer(M.RING, function()
    for index = 1, M.rings:len() do
      if M.rings:get(index).key == key then M.rings:remove(index) break end
    end
  end, false)
end

--- Springs away and ends.
function M.finish()
  if M.leaving:get() then return end
  stop_timer()
  M.leaving:set(true)
  morf.time.timer(M.GONE, function() morf.quit() end, false)
end

return M
