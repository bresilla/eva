-- eva-pomodoro's state: work, short and long breaks, kept in a file so a session
-- outlives its window. The moment a phase ends is a timer in eva-clock's store,
-- which rings it and shows it in the bar. No nodes.
local morf = require("morf")
local sys = require("common.sys")
local lib = require("lib.services.alarm")
local focus = require("focus")

local M = {
  session = morf.signal("pomodoro.session", {}),
  message = morf.signal("pomodoro.message", ""),
}

M.EVERY = 4
-- Milliseconds this window lets the shell and eva-clock ring a phase's end first.
M.RING_DELAY = 3000
-- How long a job stays for the units and the verbs it started.
M.JOB_WAIT = 800

M.PHASES = {
  work = { name = "Focus", label = "focus" },
  short = { name = "Short break", label = "break" },
  long = { name = "Long break", label = "long break" },
}

M.PLANS = {
  { name = "25 / 5", work = 25, short = 5, long = 15 },
  { name = "50 / 10", work = 50, short = 10, long = 30 },
  { name = "15 / 3", work = 15, short = 3, long = 10 },
}

local function path() return sys.state("pomodoro", "session.json") end
local function store() return sys.state("clock", "alarms.json") end
local function now() return lib.now() end
local function today() return morf.time.format("%Y-%m-%d", now()) end

local function length(phase, plan) return M.PLANS[plan][phase] * 60 end

-- `session` waiting at the start of `phase`.
local function enter(session, phase)
  session.phase, session.running, session.alarm, session.at = phase, false, nil, 0
  session.seconds = length(phase, session.plan)
  session.left = session.seconds
  return session
end

local function fresh()
  return enter({ plan = 1, round = 0, today = 0, total = 0, day = today() }, "work")
end

-- The session as the file has it now.
local function read()
  local session = sys.load(path(), nil)
  if type(session) ~= "table" or not M.PHASES[session.phase] or not M.PLANS[session.plan] then return fresh() end
  if session.day ~= today() then session.day, session.today = today(), 0 end
  return session
end

local ending

local function plan_end()
  if ending then ending:cancel() ending = nil end
  local session = M.session:get()
  if not session.running or not M.follows then return end
  ending = morf.time.timer(math.floor(math.max(0, session.at - now()) * 1000) + 200, function()
    ending = nil
    M.catch_up()
  end, false)
end

local function show(session)
  M.session:set(session)
  plan_end()
end

local function write(session)
  sys.save(path(), session)
  show(session)
end

-- Quiet follows a running work phase.
local function quiet(session)
  focus.set(session.running and session.phase == "work", function(reply, why)
    M.message:set(reply == nil and why ~= "dry run" and "The shell is not running: notifications stay on" or "")
  end)
end

-- Whether eva-clock's store holds `id`, read from the file.
local function has_alarm(id)
  for _, item in ipairs(sys.load(store(), {})) do
    if item.id == id then return true end
  end
  return false
end

local function next_break(session) return session.round >= M.EVERY and "long" or "short" end

-- The phase that ran its time is counted, and the next one waits for a press.
local function finished(session)
  local after = "work"
  if session.phase == "work" then
    session.round, session.today = session.round + 1, session.today + 1
    session.total = session.total + 1
    after = next_break(session)
  elseif session.phase == "long" then
    session.round = 0
  end
  return enter(session, after)
end

--- Sets the session's state from the time and the store: a phase that has run
--- out moves on, one whose timer was cancelled elsewhere stops.
function M.catch_up()
  local session = read()
  if not session.running then
    show(session)
    return
  end
  if session.at <= now() then
    write(finished(session))
    quiet(M.session:get())
  elseif not has_alarm(session.alarm) then
    session.left, session.running, session.alarm = math.max(1, session.at - now()), false, nil
    write(session)
    quiet(session)
  else
    show(session)
  end
end

--- Reads the session. `ring` makes this process keep the time where nothing
--- else does; `follow` moves the session on its own, and follows the file.
function M.start_up(ring, follow)
  M.alarm = lib.new { ring = ring, delay = M.RING_DELAY }
  M.alarm.load()
  M.follows = follow
  if not morf.fs.exists(path()) then write(fresh()) end
  M.catch_up()
  if not follow then return end
  M.watches = {
    morf.fs.watch(path(), function() M.catch_up() end),
    morf.fs.watch(store(), function() M.catch_up() end),
  }
end

--- Seconds on the dial. A tracked read, and it ticks only while the session runs.
function M.left()
  local session = M.session:get()
  if not session.running then return session.left or 0 end
  morf.time.clock:get()
  return math.max(0, session.at - now())
end

--- How much of the phase has gone, 0 to 1.
function M.progress()
  local seconds = M.session:get().seconds or 0
  if seconds <= 0 then return 0 end
  return math.max(0, math.min(1, 1 - M.left() / seconds))
end

local function timer_words(session)
  local seconds = math.ceil(session.left)
  local amount = seconds % 60 == 0 and (seconds // 60) .. " min" or seconds .. " s"
  return ("timer %s %s"):format(amount, M.PHASES[session.phase].label)
end

--- Starts or resumes the phase on the dial.
function M.start()
  local session = read()
  if session.running then return true end
  local item, why = M.alarm.add(timer_words(session), "pomodoro")
  if not item then
    M.message:set(why)
    return false
  end
  session.running, session.alarm, session.at = true, item.id, item.at
  write(session)
  quiet(session)
  return true
end

--- Holds the phase on the dial where it is.
function M.pause()
  local session = read()
  if not session.running then return false end
  local id = session.alarm
  session.left, session.running, session.alarm = math.max(1, session.at - now()), false, nil
  write(session)
  if id then M.alarm.remove(id) end
  quiet(session)
  return true
end

function M.toggle()
  if M.session:get().running then return M.pause() end
  return M.start()
end

--- Leaves the phase uncounted for the next, running if this one ran.
function M.skip()
  local session = read()
  local ran, id = session.running, session.alarm
  local after = "work"
  if session.phase == "work" then after = next_break(session)
  elseif session.phase == "long" then session.round = 0 end
  write(enter(session, after))
  if id then M.alarm.remove(id) end
  if ran then return M.start() end
  quiet(M.session:get())
  return true
end

--- Back to a waiting first phase, the day's count kept.
function M.reset()
  local session = read()
  local id = session.alarm
  session.round = 0
  write(enter(session, "work"))
  if id then M.alarm.remove(id) end
  quiet(M.session:get())
  return true
end

--- Chooses a plan: a phase on the dial takes it if it has not begun.
function M.set_plan(index)
  if not M.PLANS[index] then return false end
  local session = read()
  session.plan = index
  if not session.running and session.left == session.seconds then enter(session, session.phase) end
  write(session)
  return true
end

--- The session in words, for the command line and the window's note.
function M.words()
  local session = M.session:get()
  local state = "ready"
  if session.running then state = "ends " .. morf.time.format("%H:%M", session.at)
  elseif session.left ~= session.seconds then state = "paused" end
  return ("%s %s, %s, %d of %d, %d today"):format(M.PHASES[session.phase].name, lib.running(M.left()), state,
    session.round, M.EVERY, session.today)
end

local ACTIONS = { start = M.start, pause = M.pause, skip = M.skip, reset = M.reset, toggle = M.toggle }

--- `eva-pomodoro`'s command: `done(text, why)`. `rang` is what eva-clock calls
--- when a phase's timer has rung.
function M.job(how, done)
  if how == "status" then
    done(M.words())
  elseif how == "rang" then
    morf.time.timer(M.JOB_WAIT, function() done(M.words()) end, false)
  elseif ACTIONS[how] then
    ACTIONS[how]()
    morf.time.timer(M.JOB_WAIT, function() done(M.words()) end, false)
  else
    done(nil, "unknown command: " .. tostring(how))
  end
end

return M
