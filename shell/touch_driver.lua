-- Gestures anywhere on a touchscreen. The reader (lib/services/touch_reader.lua)
-- hears every contact while apps keep theirs; touch_gestures turns them into
-- gestures; touch_bindings says what each does here. The shell instance on the
-- touchscreen's own panel runs it, and only while nothing forbids it: a lock, a
-- password prompt and the capture editor stop the reader outright, so it cannot
-- see where a finger lands on a PIN pad.
--
-- It owns what it binds: a gesture it begins cancels what an edge strip was
-- doing, and while it reads, phone_gestures leaves two fingers to it (`owns`).
local morf = require("morf")
local config = require("config")
local service = require("lib.services.touch_reader")
local gestures = require("touch_gestures")
local bindings = require("touch_bindings")
local actions = require("touch_actions")
local M = {}

M.TICK = 60            -- How often resting fingers are looked at, in ms.
M.LOCK_GRACE = 5000    -- How long a lock request holds the reader without a lock.

M.state = morf.signal("eva.touch.state", "off")
-- The fingers down, each `{ id, x, y, resting }`, while something watches them.
M.fingers = morf.signal("eva.touch.fingers", {})
-- The last gesture heard: `{ key, name, action, phase, progress }`.
M.heard = morf.signal("eva.touch.heard", {})
-- Trying: gestures are named and do nothing.
M.trying = morf.signal("eva.touch.trying", false)
-- Whether anything shows the fingers.
M.watching = morf.signal("eva.touch.watching", false)

local locking = morf.signal("eva.touch.locking", false)
local reader, recogniser, running
local ticking, wall_at, event_at = nil, 0, 0
local release
local watched_lock

local function dry()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

local function login()
  local ok, bus = pcall(function() return require("models.logind").connect() end)
  return ok and bus or nil
end

--- Whether the session is locked, or about to be. EVA_FAKE_LOCKED stands in.
function M.locked()
  local fake = morf.env and morf.env("EVA_FAKE_LOCKED")
  if fake and fake ~= "" then return fake == "1" end
  if locking:get() then return true end
  local bus = login()
  return bus ~= nil and bus.state.session.locked == true
end

--- The screen the touchscreen sits on, or nil.
function M.panel()
  return service.panel(morf.screens, config.get("gestures.output"), require("auto_rotate").built_in)
end

local function own_panel()
  local panel, mine = M.panel(), (morf.screens or {})[1]
  return panel ~= nil and mine ~= nil and panel.name == mine.name
end

--- What reading needs: the setting on, this shell on the panel, the session open.
function M.allowed()
  if config.get("gestures.enabled") == false then return false end
  if morf.env("EVA_GESTURE_DRIVER") == "lisgd" then return false end
  local gesture = require("phone_gestures")
  return own_panel() and not M.locked() and not gesture.blocked() and gesture.global_allowed()
end

--- Whether the reader is hearing the touchscreen, so gestures are its own.
function M.owns() return M.state:get() == "running" end

local function publish()
  if M.watching:get() then M.fingers:set(recogniser.contacts()) end
end

local function stamp(ms)
  if ms then wall_at, event_at = morf.time.now_ms(), ms end
end

local function start_ticking()
  if ticking then return end
  ticking = morf.time.timer(M.TICK, function()
    if recogniser.count() == 0 then
      ticking:cancel()
      ticking = nil
      return
    end
    recogniser.tick(event_at + morf.time.now_ms() - wall_at)
  end, true)
end

-- What a gesture is doing: its handle, or the action to run on release.
local current

local function note(event, key, action)
  M.heard:set { key = key, name = (bindings.BY_KEY[key] or {}).name or key, action = action,
    fingers = event.fingers, kind = event.kind, direction = event.direction, edge = event.edge,
    phase = event.phase, progress = event.progress or 0, committed = event.committed == true }
end

local function begin(event, key)
  local chosen = bindings.action(key)
  note(event, key, chosen)
  if M.trying:get() or chosen == "none" then return end
  local action = actions.BY_KEY[chosen]
  if not action then return end
  require("phone_gestures").yield()
  current = { action = action, key = key, name = chosen, handle = action.follow and action.follow(event) or nil }
  if event.kind == "hold" then
    require("haptics").fire("long")
    if not current.handle then
      action.run(event, key)
      current = nil
    end
  end
end

local function hear(event)
  local key = gestures.key(event)
  if not key then return end
  if event.phase == "begin" then return begin(event, key) end
  note(event, key, M.heard:get().action)
  if not current or M.trying:get() then return end
  local gesture = current
  if event.phase == "update" then
    if gesture.handle then gesture.handle.update(event) end
  elseif event.phase == "end" then
    current = nil
    if gesture.handle then
      gesture.handle.finish(event)
    elseif event.committed then
      require("haptics").fire("commit")
      gesture.action.run(event, gesture.key)
    end
  elseif event.phase == "cancel" then
    current = nil
    if gesture.handle then gesture.handle.cancel() end
  end
end

local function regions()
  local keyboard = package.loaded.keyboard
  if not (keyboard and keyboard.active()) then return {} end
  local width, height = require("responsive").size()
  local inset = require("themes.keyboard").inset:get()
  if inset <= 0 then return {} end
  return { { name = "keyboard", x = 0, y = height - inset, width = width, height = inset } }
end

-- EVA_FAKE_TOUCH stands in for the machine: "1" a touchscreen whose lines come
-- from `touch feed`, "none" no touchscreen, "missing" no libinput, "denied" a
-- device that cannot be opened.
local function stand_in()
  local kind = morf.env and morf.env("EVA_FAKE_TOUCH")
  if not kind or kind == "" then return {} end
  local present = function() return { { name = "Stand-in touchscreen", node = "/dev/input/event99", multi = true } } end
  if kind == "none" then return { find = function() return {} end } end
  if kind == "missing" then return { find = present, installed = function() return false end } end
  return { find = present, installed = function() return true end, spawn = function(spec)
    if kind == "denied" then
      morf.time.timer(1, function() spec.on_exit(1) end, false)
    else
      spec.on_stdout("-event99  DEVICE_ADDED                 Stand-in touchscreen              seat0 default group1  cap:t")
    end
    return { kill = function() end, close = function() end }
  end }
end

local function build()
  if reader then return end
  recogniser = gestures.new { size = function() return require("responsive").size() end, regions = regions, on = hear }
  local sink = {
    down = function(id, x, y, ms)
      stamp(ms)
      recogniser.down(id, x, y, ms or event_at)
      start_ticking()
    end,
    move = function(id, x, y) recogniser.move(id, x, y) end,
    up = function(id, ms)
      stamp(ms)
      recogniser.up(id, ms or event_at)
    end,
    frame = function(ms)
      stamp(ms)
      recogniser.frame(ms or event_at)
      publish()
    end,
    cancel = function()
      recogniser.cancel()
      publish()
    end,
  }
  local seams = stand_in()
  seams.screen = function() return (morf.screens or {})[1] end
  seams.sink = sink
  seams.changed = function(state) M.state:set(state) end
  reader = service.new(seams)
end

local function watch_lock()
  if watched_lock then return end
  watched_lock = true
  local bus = login()
  if not (bus and bus.on_lock) then return end
  bus.on_lock(function()
    locking:set(true)
    if release then release:cancel() end
    release = morf.time.timer(M.LOCK_GRACE, function()
      release = nil
      locking:set(false)
    end, false)
  end)
end

--- Starts it: from here on it follows the setting, the screens, plug and unplug,
--- and whatever forbids reading.
function M.start()
  if running then return end
  running = true
  build()
  watch_lock()
  morf.effect("eva.touch.driver", function()
    if morf.window and morf.window.screens_revision then morf.window.screens_revision() end
    if M.allowed() then reader.start() else reader.stop() end
  end)
  if morf.udev and morf.udev.subscribe then
    pcall(morf.udev.subscribe, "input", function() reader.refresh() end)
  end
end

--- Whether a process is reading the touchscreen.
function M.reading() return reader ~= nil and reader.reading() end

--- `touch [state]`: what it is doing. `touch try on|off`: gestures named, not run.
--- `touch set KEY ACTION`: what a gesture does here. `touch feed LINE`: under
--- EVA_FAKE_TOUCH, a line as `libinput debug-events` prints it.
function M.register(ipc)
  ipc.touch = function(how, a, b)
    if how == "try" then M.trying:set(a == "on") return M.trying:get() end
    if how == "set" then bindings.set(a, nil, b) return bindings.action(a) end
    if how == "feed" and morf.env("EVA_FAKE_TOUCH") == "1" then return reader.feed(a) end
    if how ~= nil and how ~= "state" then error("`" .. tostring(how) .. "`: state, try, set or feed") end
    local panel = M.panel()
    return { state = M.state:get(), reading = M.reading(), allowed = M.allowed(), locked = M.locked(),
      form = require("responsive").form(), output = panel and panel.name or "", heard = M.heard:get() }
  end
end

return M
