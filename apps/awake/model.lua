-- eva-awake: a face on the shell's keep awake. It holds no inhibitor: the time
-- and the state are the shell's, through its `awake` verb, so the Keep awake
-- tile and the bar's coffee are this same state. No nodes.
local morf = require("morf")
local sys = require("common.sys")
local alarm = require("lib.services.alarm")
local unwrap = require("lib.util.reply")

local M = {
  on = morf.signal("awake.on", false),
  stop = morf.signal("awake.stop", 0),
  span = morf.signal("awake.span", 0),
  up = morf.signal("awake.up", true),
  draft = morf.signal("awake.draft", ""),
  message = morf.signal("awake.message", ""),
}

M.PRESETS = { { label = "30 min", minutes = 30 }, { label = "1 h", minutes = 60 }, { label = "2 h", minutes = 120 } }

local POLL_MS = 2000
local GONE = "The shell is not running"

local function run_path() return sys.state("awake", "run.json") end

--- Seconds left, 0 with no time on it. A tracked read.
function M.left()
  local stop = M.stop:get()
  return stop > 0 and math.max(0, stop - alarm.now()) or 0
end

--- How much of the time given is left, for the dial. A tracked read.
function M.fraction()
  if not M.on:get() then return 0 end
  local stop, span = M.stop:get(), M.span:get()
  if stop <= 0 then return 1 end
  morf.time.clock:get()
  return span > 0 and M.left() / span or 1
end

-- The shell's state, the time it was given read from where this tool left it.
local function follow(state)
  M.up:set(true)
  local stop = state["until"] or 0
  if stop ~= M.stop:get() then
    local run = sys.load(run_path(), {})
    local given = run.stop and math.abs(run.stop - stop) < 2 and run.seconds
    M.span:set(given or math.max(0, stop - alarm.now()))
  end
  M.stop:set(stop)
  M.on:set(state.on == true)
end

-- Sends a verb: `done(state, why)`.
local function send(words, seconds, done)
  sys.shell(words, nil, function(answer, why)
    local state = unwrap(answer)
    if type(state) ~= "table" then
      if why ~= "dry run" then M.up:set(false) end
      if done then done(nil, why or GONE) end
      return
    end
    if seconds then sys.save(run_path(), { stop = state["until"], seconds = seconds }) end
    follow(state)
    if done then done(state) end
  end)
end

--- Asks the shell how things stand.
function M.ask(done)
  sys.shell({ "awake", "state" }, { read = true }, function(answer, why)
    local state = unwrap(answer)
    if type(state) == "table" then
      follow(state)
      if done then done(state) end
      return
    end
    M.up:set(false)
    M.on:set(false)
    if done then done(nil, why or GONE) end
  end)
end

--- Asks the shell how things stand, every POLL_MS while the window is open.
function M.start()
  M.ask()
  morf.time.timer(POLL_MS, function() M.ask() end, true)
end

--- Awake for `minutes`.
function M.keep(minutes, done) send({ "awake", "on", minutes }, minutes * 60, done) end

--- Awake until told otherwise.
function M.forever(done) send({ "awake", "on" }, nil, done) end

function M.off(done) send({ "awake", "off" }, nil, done) end

--- The minutes `words` mean, a span or a time of day, and how they read: nil
--- and why where they mean neither.
function M.reading(words)
  local item = alarm.parse(words)
  if not item then return nil, 'Say a time: "45 min", "2 hours", "until 18:30"' end
  if item.kind == "timer" then return item.seconds / 60, alarm.span(item.seconds) end
  local left = item.at - alarm.now()
  return left / 60, ("Until %s · %s"):format(morf.time.format("%H:%M", item.at), alarm.span(left))
end

--- What the draft would do, in words, or nil.
function M.hint()
  local words = M.draft:get()
  if words:match("^%s*$") then return nil end
  local _, text = M.reading(words)
  return text
end

--- Keeps awake for what `words` say.
function M.say(words)
  local minutes, why = M.reading(words)
  if not minutes then
    M.message:set(why)
    return false
  end
  M.draft:set("")
  M.message:set("")
  M.keep(minutes)
  return true
end

--- How the state reads on a line.
function M.words(state)
  if not state.on then return "off" end
  local stop = state["until"] or 0
  if stop <= 0 then return "on until told otherwise" end
  return ("on until %s, %s left"):format(morf.time.format("%H:%M", stop), alarm.span(math.max(0, stop - alarm.now())))
end

-- Awake while process `pid` lives, then let go, unless a time has been put on
-- it since.
local function hold(pid, done)
  local proc = (morf.env("EVA_PROC_ROOT") or "/proc") .. "/" .. tostring(pid)
  if not tostring(pid):match("^%d+$") or not morf.fs.exists(proc) then
    done(nil, "no process " .. tostring(pid))
    return
  end
  M.forever(function(state, why)
    if not state then done(nil, why) return end
    local poll
    poll = morf.time.timer(POLL_MS, function()
      if morf.fs.exists(proc) then return end
      poll:cancel()
      M.ask(function(now, gone)
        if not now then done(nil, gone) return end
        if now.on and (now["until"] or 0) <= 0 then
          M.off(function() done("process " .. pid .. " ended") end)
        else
          done("process " .. pid .. " ended")
        end
      end)
    end, true)
  end)
end

--- `done(text, why)` with the answer to `args`.
function M.job(args, done)
  local how = args[1]
  local function said(state, why)
    if not state then done(nil, why) return end
    done(M.words(state))
  end
  if how == "status" then M.ask(said)
  elseif how == "off" then M.off(said)
  elseif how == "on" then M.forever(said)
  elseif how == "--pid" then hold(args[2], done)
  else
    local words = {}
    for index = 1, #args do words[#words + 1] = args[index] end
    local minutes, why = M.reading(table.concat(words, " "))
    if not minutes then done(nil, why) return end
    M.keep(minutes, said)
  end
end

return M
