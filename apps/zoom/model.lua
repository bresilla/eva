-- eva-zoom's state and actions: Hyprland's cursor zoom where the keyword exists,
-- and a lens over the frozen screen everywhere. No nodes.
local morf = require("morf")
local sys = require("common.sys")
local pointer = require("lib.shell.pointer")
local frozen = require("common.freeze").new("zoom")

local M = {
  picture = frozen.picture,
  factor = morf.signal("zoom.factor", 2),
  cursor = morf.signal("zoom.cursor", 1),
  radius = morf.signal("zoom.radius", 140),
  at = morf.signal("zoom.at", { x = 0, y = 0 }),
  asked = morf.signal("zoom.asked", false),
  touched = morf.signal("zoom.touched", false),
  message = morf.signal("zoom.message", ""),
}

M.MIN, M.MAX = 1, 10
M.STEP = 0.5
M.RADII = { 96, 140, 200, 280 }
M.OPTION = "cursor:zoom_factor"

morf.effect("zoom.frozen-message", function()
  local words = frozen.message:get()
  if words ~= "" then M.message:set(words) end
end)

local function store() return sys.state("zoom", "lens.json") end

local function round(value) return math.floor(value * 100 + 0.5) / 100 end

--- `value` held to what a factor may be.
function M.clamp(value) return math.max(M.MIN, math.min(M.MAX, round(value))) end

--- Reads what was kept of the lens.
function M.load()
  local kept = sys.load(store(), {})
  if tonumber(kept.factor) then M.factor:set(M.clamp(tonumber(kept.factor))) end
  if tonumber(kept.radius) then M.radius:set(tonumber(kept.radius)) end
end

local function save()
  sys.save(store(), { factor = M.factor:get(), radius = M.radius:get() })
end

--- Whether this session has the cursor zoom keyword.
function M.native() return sys.compositor() == "hyprland" end

--- `done(factor)`: the compositor's factor, nil where it does not say.
function M.read(done)
  sys.run({ "hyprctl", "-j", "getoption", M.OPTION }, { read = true }, function(result)
    local ok, reply = pcall(morf.json.decode, result.stdout or "")
    local value = ok and type(reply) == "table" and tonumber(reply.float) or nil
    if value then M.cursor:set(value) end
    if done then done(value) end
  end)
end

local function spell(value) return ("%g"):format(value) end

local function lua_chunk(value)
  return ("hl.config({ cursor = { zoom_factor = %s } })"):format(spell(value))
end

-- Sets the keyword, reads it back, and on a Lua-configured Hyprland, which
-- refuses keywords, says it the way that takes.
local function write(value, done)
  sys.run({ "hyprctl", "keyword", M.OPTION, spell(value) }, {}, function()
    M.read(function(now)
      if now == nil or math.abs(now - value) < 0.01 or sys.dry() then return done(now or value) end
      sys.run({ "hyprctl", "eval", lua_chunk(value) }, {}, function()
        M.read(function(after) done(after or now) end)
      end)
    end)
  end)
end

local writing, waiting = false, nil

--- Asks the compositor for `value`, the latest of a run of asks winning.
function M.set_cursor(value, done)
  value = M.clamp(value)
  if writing then waiting = value return end
  writing = true
  write(value, function(now)
    writing = false
    local next_value = waiting
    waiting = nil
    if next_value and next_value ~= value then return M.set_cursor(next_value, done) end
    if done then done(now) end
  end)
end

--- What a word of the command line makes of `now`: in, out, reset or a number.
function M.word(word, now)
  if word == "in" then return M.clamp(now + M.STEP) end
  if word == "out" then return M.clamp(now - M.STEP) end
  if word == "reset" then return M.MIN end
  local value = tonumber(word)
  if value then return M.clamp(value) end
  return nil
end

--- The command line's word on the compositor; `done()` after it.
function M.command(word, done)
  M.read(function(now)
    local value = M.word(word, now or M.MIN)
    if not value then
      morf.log("warn", "eva-zoom: no such step " .. tostring(word))
      return done()
    end
    M.set_cursor(value, done)
  end)
end

--- The factor the slider stands for: the compositor's, or the lens's.
function M.current()
  if M.native() then return M.cursor:get() end
  return M.factor:get()
end

--- The lens's factor.
function M.set_factor(value)
  M.factor:set(M.clamp(value))
  save()
end

--- From the slider or a button: the compositor where it can, else the lens.
function M.set(value)
  if M.native() then M.set_cursor(value) else M.set_factor(value) end
end

--- One step of the lens, `by` 1 or -1.
function M.step(by) M.set_factor(M.factor:get() + by * M.STEP) end

--- One step of the lens's size, `by` 1 or -1.
function M.resize(by)
  local at = 1
  for index, radius in ipairs(M.RADII) do
    if radius == M.radius:get() then at = index end
  end
  M.radius:set(M.RADII[math.max(1, math.min(#M.RADII, at + by))])
  save()
end

M.scale = frozen.scale

--- Freezes the screen for the lens.
function M.open()
  local x, y = pointer.middle()
  M.at:set { x = x, y = y }
  pointer.start(function(at_x, at_y, known)
    if known then M.at:set { x = at_x, y = at_y } end
  end)
  frozen.take()
end

--- Lets the lens go.
function M.close() frozen.release() end

--- The pointer at `x`, `y`; `touch` when a finger put it there.
function M.point(x, y, touch)
  M.at:set { x = x, y = y }
  M.touched:set(touch == true)
end

--- A word at the running lens: nothing or `lens` toggles it, the rest step it.
function M.lens_word(word, shut)
  if word == nil or word == "" or word == "lens" then
    if M.picture:get() then shut() else M.open() end
    return true
  end
  if word == "reset" then shut() return true end
  local value = M.word(word, M.factor:get())
  if not value then return false end
  M.set_factor(value)
  if not M.picture:get() then M.open() end
  return true
end

return M
