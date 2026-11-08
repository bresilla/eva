-- eva-breaks: when a rest falls due. The `--watch` process keeps the count: time
-- with input counts towards a break, time idle counts as the break itself, and
-- no timer runs but the one to the next break. The window and the command line
-- read what it writes and change its settings file. No nodes.
local morf = require("morf")
local sys = require("apps.common.sys")
local alarm = require("lib.services.alarm")

local M = {
  settings = morf.signal("breaks.settings", {}),
  status = morf.signal("breaks.status", {}),
  current = morf.signal("breaks.current", nil),
  tab = morf.signal("breaks.tab", 1),
}

M.KINDS = { "rest", "eyes" }
M.WORDS = {
  eyes = { title = "Look away", body = "Rest your eyes on something far off", name = "Eyes" },
  rest = { title = "Time for a rest", body = "Stand up and move about", name = "Rest" },
}
M.DEFAULTS = {
  eyes = { on = true, every = 20, length = 20 },
  rest = { on = true, every = 60, length = 300 },
  postpone = 5,
  pause_until = 0,
}
M.EVERY = { eyes = { 20, 30, 45 }, rest = { 45, 60, 90 } }
M.LENGTH = { eyes = { 20, 40, 60 }, rest = { 180, 300, 600 } }

local HELD_S = 300
local KEEP_MS = 60000
local IDLE_LEAST_S, IDLE_MOST_S = 5, 60
local DAYS_KEPT = 14

local function settings_path() return sys.state("breaks", "settings.json") end
local function state_path() return sys.state("breaks", "state.json") end

--- The time, for everything here.
function M.now() return morf.time.now() end

local function merged(saved)
  local out = {}
  for key, value in pairs(M.DEFAULTS) do
    if type(value) == "table" then
      out[key] = {}
      local kept = type(saved[key]) == "table" and saved[key] or {}
      for field, default in pairs(value) do
        out[key][field] = kept[field] == nil and default or kept[field]
      end
    else
      out[key] = saved[key] == nil and value or saved[key]
    end
  end
  return out
end

--- Reads the settings.
function M.load() M.settings:set(merged(sys.load(settings_path(), {}))) end

--- Reads what the watcher last wrote.
function M.read() M.status:set(sys.load(state_path(), {})) end

--- Saves a change made by `change(settings)`.
function M.change(change)
  local value = merged(sys.load(settings_path(), {}))
  change(value)
  sys.save(settings_path(), value)
  M.settings:set(value)
end

--- Holds the reminders off for `minutes`, none to let them go again.
function M.pause(minutes)
  M.change(function(value) value.pause_until = minutes > 0 and M.now() + minutes * 60 or 0 end)
end

local function alive(pid)
  local line = pid and morf.fs.read("/proc/" .. math.floor(pid) .. "/cmdline")
  return line ~= nil and line:find("breaks/app.lua", 1, true) ~= nil
end

--- Whether a `--watch` process is running.
function M.watching(state) return alive((state or {}).pid) end

--- Keeps the window on the watcher's file.
function M.follow()
  M.load()
  M.read()
  morf.fs.mkdir(sys.state("breaks"), { parents = true })
  if not morf.fs.exists(state_path()) then sys.save(state_path(), {}) end
  M.status_watch = morf.fs.watch(state_path(), function() M.read() end)
end

--- Starts the watcher, to outlive the page: `eva-breaks --watch`.
function M.start_watching()
  require("lib.services.host").start_tool("breaks", { "--watch" })
end

--- The day `at` falls in, as the store keys it.
function M.day(at) return morf.time.format("%Y-%m-%d", at) end

--- The kind that comes next and its seconds, of `state`; nil where none is on.
function M.next_break(state)
  local kind, left
  for _, name in ipairs(M.KINDS) do
    local due = (state.due or {})[name]
    if due and (not left or due - M.now() < left) then kind, left = name, due - M.now() end
  end
  return kind, left and math.max(0, left) or nil
end

-- --------------------------------------------------------------- the watcher --

local E

local function on(kind) return M.settings:get()[kind].on end

local function due_of(kind) return E.start[kind] + M.settings:get()[kind].every * 60 end

local function paused() return M.settings:get().pause_until > M.now() end

-- Adds the time since `active_since` to the days it fell in.
local function bank(to)
  local from = E.active_since
  if not from then return end
  while from < to do
    local date = morf.time.date(from)
    local midnight = from - (date.hour * 3600 + date.minute * 60 + date.second) + 86400
    local upto = math.min(to, midnight)
    local key = M.day(from)
    E.days[key] = (E.days[key] or 0) + (upto - from)
    from = upto
  end
  E.active_since = to
end

local function trim()
  local keys = {}
  for key in pairs(E.days) do keys[#keys + 1] = key end
  table.sort(keys)
  for index = 1, #keys - DAYS_KEPT do
    E.days[keys[index]] = nil
    E.counts[keys[index]] = nil
  end
end

local function write()
  bank(M.now())
  trim()
  local due = {}
  for _, kind in ipairs(M.KINDS) do
    if on(kind) and not paused() then due[kind] = due_of(kind) end
  end
  local current = M.current:get()
  sys.save(state_path(), { pid = morf.process_id, due = due, days = E.days, counts = E.counts, idle = E.idle_at ~= nil,
    held = E.held, current = current })
  M.status:set(sys.load(state_path(), {}))
end

local function count(what)
  local key = M.day(M.now())
  local day = E.counts[key] or { taken = 0, skipped = 0 }
  day[what] = day[what] + 1
  E.counts[key] = day
end

local arm

local function resume_keeping()
  if E.keep then return end
  E.keep = morf.time.timer(KEEP_MS, write, true)
end

local function stop_keeping()
  if E.keep then E.keep:cancel() E.keep = nil end
end

local function disarm()
  if E.timer then E.timer:cancel() E.timer = nil end
end

-- Takes the break off the screen; `after(kind)` says what it counts as.
local function leave(after)
  local current = M.current:get()
  if not current then return end
  if E.ending then E.ending:cancel() E.ending = nil end
  M.current:set(nil)
  after(current.kind)
  E.active_since = M.now()
  resume_keeping()
  arm()
  write()
end

local function reset(kind)
  E.start[kind] = M.now()
  if kind == "rest" then E.start.eyes = M.now() end
end

--- The break has run its time.
function M.finish()
  leave(function(kind)
    count("taken")
    reset(kind)
  end)
end

--- Passes this break by.
function M.skip()
  leave(function(kind)
    count("skipped")
    reset(kind)
  end)
end

--- Asks for it again in a while.
function M.postpone()
  leave(function(kind)
    local value = M.settings:get()
    E.start[kind] = M.now() + value.postpone * 60 - value[kind].every * 60
  end)
end

--- Puts a break on the screen.
function M.begin(kind)
  local now = M.now()
  bank(now)
  E.active_since = nil
  E.held = nil
  stop_keeping()
  disarm()
  local length = M.settings:get()[kind].length
  M.current:set { kind = kind, ends = now + length, length = length }
  sys.notify(M.WORDS[kind].title, M.WORDS[kind].body)
  E.ending = morf.time.timer(length * 1000, M.finish, false)
  write()
end

-- A break is due: it shows unless the shell is in do not disturb, which holds it
-- off a while.
local function fire()
  E.timer = nil
  local chosen
  for _, kind in ipairs(M.KINDS) do
    if not chosen and on(kind) and due_of(kind) <= M.now() + 1 then chosen = kind end
  end
  if not chosen then arm() return end
  sys.shell({ "focus", "state" }, { read = true }, function(answer)
    if not E or M.current:get() then return end
    if answer == true then
      E.start[chosen] = E.start[chosen] + HELD_S
      E.held = chosen
      arm()
      write()
      return
    end
    M.begin(chosen)
  end)
end

arm = function()
  disarm()
  if M.current:get() or E.idle_at then return end
  local now = M.now()
  if paused() then
    E.was_paused = true
    E.timer = morf.time.timer((M.settings:get().pause_until - now) * 1000, function()
      E.timer = nil
      M.load()
      M.settled()
    end, false)
    return
  end
  local nearest
  for _, kind in ipairs(M.KINDS) do
    if on(kind) and (not nearest or due_of(kind) < nearest) then nearest = due_of(kind) end
  end
  if nearest then E.timer = morf.time.timer(math.max(0, nearest - now) * 1000, fire, false) end
end

-- How long without input counts as gone: the shortest break, within reason.
local function idle_seconds()
  local least = IDLE_MOST_S
  local value = M.settings:get()
  for _, kind in ipairs(M.KINDS) do
    if value[kind].on then least = math.min(least, value[kind].length) end
  end
  return math.max(IDLE_LEAST_S, least)
end

local listen

--- Takes in a change to the settings.
function M.settled()
  if E.was_paused and not paused() then
    E.was_paused = false
    for _, kind in ipairs(M.KINDS) do E.start[kind] = M.now() end
  end
  if idle_seconds() ~= E.seconds then listen() end
  arm()
  write()
end

local function went_idle(after)
  if M.current:get() then return end
  E.idle_at = M.now() - after
  bank(E.idle_at)
  E.active_since = nil
  stop_keeping()
  disarm()
  write()
end

local function came_back()
  if not E.idle_at then return end
  local now = M.now()
  local away = now - E.idle_at
  E.idle_at = nil
  for _, kind in ipairs(M.KINDS) do
    if away >= M.settings:get()[kind].length then E.start[kind] = now
    else E.start[kind] = E.start[kind] + away end
  end
  E.active_since = now
  resume_keeping()
  arm()
  write()
end

listen = function()
  if E.idle then E.idle:cancel() end
  local seconds = idle_seconds()
  E.seconds = seconds
  E.idle = morf.idle.subscribe(seconds * 1000, function(idle)
    if idle then went_idle(seconds) else came_back() end
  end)
end

--- Runs the count, for as long as the process lives. False where one already
--- runs.
function M.watch()
  M.load()
  M.read()
  local last = M.status:get()
  if M.watching(last) and math.floor(last.pid) ~= morf.process_id then return false end
  local now = M.now()
  E = { start = { eyes = now, rest = now }, active_since = now, days = last.days or {}, counts = last.counts or {} }
  if not morf.fs.exists(settings_path()) then sys.save(settings_path(), M.settings:get()) end
  listen()
  E.watcher = morf.fs.watch(settings_path(), function()
    M.load()
    M.settled()
  end)
  resume_keeping()
  arm()
  write()
  return true
end

-- --------------------------------------------------------- the command line --

--- Screen time on the day of `key`.
function M.seconds(state, key) return ((state.days or {})[key]) or 0 end

--- How things stand, on one line.
function M.words(state)
  local parts = {}
  local value = M.settings:get()
  if value.pause_until > M.now() then
    parts[#parts + 1] = "paused until " .. morf.time.format("%H:%M", value.pause_until)
  elseif M.watching(state) then
    for _, kind in ipairs(M.KINDS) do
      local due = (state.due or {})[kind]
      if due then parts[#parts + 1] = kind .. " in " .. alarm.span(math.max(0, due - M.now())) end
    end
    if state.idle then parts[#parts + 1] = "idle" end
    if state.held then parts[#parts + 1] = state.held .. " held off by do not disturb" end
  else
    parts[#parts + 1] = "not watching: start eva-breaks --watch"
  end
  parts[#parts + 1] = "screen today " .. alarm.span(math.floor(M.seconds(state, M.day(M.now()))))
  return table.concat(parts, ", ")
end

--- `done(text, why)` with the answer to `args`.
function M.job(args, done)
  M.load()
  M.read()
  local how = args[1]
  if how == "status" then
    done(M.words(M.status:get()))
  elseif how == "pause" then
    local minutes = tonumber(args[2])
    if not minutes or minutes <= 0 then done(nil, "usage: eva-breaks pause MINUTES") return end
    M.pause(minutes)
    done("paused until " .. morf.time.format("%H:%M", M.settings:get().pause_until))
  elseif how == "resume" then
    M.pause(0)
    done("resumed")
  else
    done(nil, "unknown command: " .. tostring(how))
  end
end

return M
