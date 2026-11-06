-- Keep awake for a time: the Focus page's dial, presets and words, and
-- `eva-awake`'s, all on the shell's own keep awake (idle_model.lua), so the
-- tile, the bar's coffee and these are one state. The page acts on it directly;
-- the job asks the running shell through its `awake` verb. No nodes.
local morf = require("morf")
local alarm = require("lib.services.alarm")

local M = {}

M.PRESETS = { { label = "30 min", minutes = 30 }, { label = "1 h", minutes = 60 }, { label = "2 h", minutes = 120 } }

local POLL_MS = 2000
local GONE = "The shell is not running"

-- Where the time given is kept, for the dial to measure what is left against.
local function run_path()
  return (morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva/awake/run.json"
end
local function remember(stop, seconds)
  morf.fs.write(run_path(), morf.json.encode { stop = stop, seconds = seconds }, { atomic = true, parents = true, mode = 384 })
end
local function given(stop)
  local ok, run = pcall(function() return morf.json.decode(morf.fs.read(run_path())) end)
  if ok and type(run) == "table" and run.stop and math.abs(run.stop - stop) < 2 then return run.seconds end
end

--- The minutes `words` mean, a span or a time of day, and how they read: nil
--- and why where they mean neither.
function M.reading(words)
  local item = alarm.parse(words)
  if not item then return nil, 'Say a time: "45 min", "2 hours", "until 18:30"' end
  if item.kind == "timer" then return item.seconds / 60, alarm.span(item.seconds) end
  local left = item.at - alarm.now()
  return left / 60, ("Until %s · %s"):format(morf.time.format("%H:%M", item.at), alarm.span(left))
end

--- How the state reads on a line.
function M.words(state)
  if not state.on then return "off" end
  local stop = state["until"] or 0
  if stop <= 0 then return "on until told otherwise" end
  return ("on until %s, %s left"):format(morf.time.format("%H:%M", stop), alarm.span(math.max(0, stop - alarm.now())))
end

-- ------------------------------------------------------------- the page --

--- The Focus page's Keep awake: `on()`, `stop()`, `fraction()`, `title()`,
--- `subtitle()`, `keep(minutes)`, `say(words)`, `hint()`, `draft` and `message`.
function M.page()
  local settings, idle = require("settings_model"), require("idle_model")
  local page = { PRESETS = M.PRESETS, draft = morf.signal("eva.awake.draft", ""),
    message = morf.signal("eva.awake.message", "") }
  function page.on() return idle.awake:get() end
  function page.stop() return page.on() and idle.awake_until() or 0 end
  function page.left()
    local stop = page.stop()
    return stop > 0 and math.max(0, stop - alarm.now()) or 0
  end
  --- How much of the time given is left, for the dial. A tracked read.
  function page.fraction()
    if not page.on() then return 0 end
    local stop = page.stop()
    if stop <= 0 then return 1 end
    morf.time.clock:get()
    local span = given(stop) or page.left()
    return span > 0 and math.min(1, page.left() / span) or 1
  end
  function page.title()
    if not page.on() then return "Off" end
    if page.stop() <= 0 then return "On" end
    morf.time.clock:get()
    return alarm.running(page.left())
  end
  function page.subtitle()
    if not page.on() then return "The session sleeps as usual" end
    if page.stop() <= 0 then return "Until told otherwise" end
    return "Until " .. morf.time.format("%H:%M", page.stop())
  end
  --- Awake for `minutes`.
  function page.keep(minutes)
    settings.awake_for(minutes)
    remember(idle.awake_until(), minutes * 60)
  end
  --- What the draft would do, in words, or nil.
  function page.hint()
    local words = page.draft:get()
    if words:match("^%s*$") then return nil end
    local _, text = M.reading(words)
    return text
  end
  --- Keeps awake for what `words` say.
  function page.say(words)
    local minutes, why = M.reading(words)
    if not minutes then page.message:set(why) return false end
    page.draft:set("")
    page.message:set("")
    page.keep(minutes)
    return true
  end
  return page
end

-- ---------------------------------------------------------- the command line --

-- A verb of the running shell through the job's common.sys: `done(state, why)`.
local function ask(via, words, done, read)
  via.shell(words, { read = read }, function(state, why)
    if type(state) ~= "table" then done(nil, why ~= "dry run" and (why or GONE) or why) return end
    done(state)
  end)
end

-- Awake while process `pid` lives, then let go, unless a time has been put on
-- it since.
local function hold(via, pid, done)
  local proc = (morf.env("EVA_PROC_ROOT") or "/proc") .. "/" .. tostring(pid)
  if not tostring(pid):match("^%d+$") or not morf.fs.exists(proc) then
    done(nil, "no process " .. tostring(pid))
    return
  end
  ask(via, { "awake", "on" }, function(state, why)
    if not state then done(nil, why) return end
    local poll
    poll = morf.time.timer(POLL_MS, function()
      if morf.fs.exists(proc) then return end
      poll:cancel()
      ask(via, { "awake", "state" }, function(now, gone)
        if not now then done(nil, gone) return end
        if now.on and (now["until"] or 0) <= 0 then
          ask(via, { "awake", "off" }, function() done("process " .. pid .. " ended") end)
        else
          done("process " .. pid .. " ended")
        end
      end, true)
    end, true)
  end)
end

--- `eva-awake ARGS`: `30m`, `on`, `off`, `status`, `--pid N`. `done(text, why)`;
--- `via` is the job's common.sys.
function M.job(args, done, via)
  local how = args[1]
  local function said(state, why)
    if not state then done(nil, why) return end
    done(M.words(state))
  end
  if how == "status" then ask(via, { "awake", "state" }, said, true)
  elseif how == "off" then ask(via, { "awake", "off" }, said)
  elseif how == "on" then ask(via, { "awake", "on" }, said)
  elseif how == "--pid" then hold(via, args[2], done)
  else
    local minutes, why = M.reading(table.concat(args, " "))
    if not minutes then done(nil, why) return end
    ask(via, { "awake", "on", minutes }, function(state, gone)
      if state then remember(state["until"], minutes * 60) end
      said(state, gone)
    end)
  end
end

return M
