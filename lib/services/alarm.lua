-- Alarms and timers, the one implementation behind eva-clock and the bar's
-- alarm indicator (`services.alarm`).
--
--   local alarm = require("lib.services.alarm").new { ring = true }
--   alarm.add("timer 12 min pasta")
--   alarm.armed()        -- whether anything will ring; a tracked read
--   alarm.ongoing:get()  -- the running timers, for the bar's status pill
--
-- The store is $XDG_STATE_HOME/eva/clock/alarms.json, a list of entries, each
-- `{ id, kind, label, on, at, seconds, hour, minute, days, rang }`: `kind` is
-- "timer" or "alarm", `at` the unix time it next rings, `days` the weekdays it
-- repeats on (Monday 1), `rang` the `at` it last rang for. Any process may write
-- it; the others follow the file.
--
-- With a user systemd each entry is a timer unit of its own, so it rings with no
-- shell and no window running; `sync` puts them back after a login. Without one,
-- the process given `ring` keeps the time itself. EVA_NOW is the time, for
-- tests; EVA_ALARM_ENGINE ("systemd" or "local") says which of the two to use.
local morf = require("morf")

local M = { SNOOZE = 9, UNIT = "eva-alarm-", MISSED = 3600,
  CARRIED = { "PATH", "WAYLAND_DISPLAY", "XDG_DATA_DIRS", "EVA_ALARM_SOUND", "MORF" } }

local UNITS = {
  s = 1, sec = 1, secs = 1, second = 1, seconds = 1,
  m = 60, min = 60, mins = 60, minute = 60, minutes = 60,
  h = 3600, hr = 3600, hrs = 3600, hour = 3600, hours = 3600,
}
local WEEKDAYS = {
  mon = 1, monday = 1, mondays = 1, tue = 2, tues = 2, tuesday = 2, tuesdays = 2, wed = 3, wednesday = 3,
  wednesdays = 3, thu = 4, thur = 4, thurs = 4, thursday = 4, thursdays = 4, fri = 5, friday = 5, fridays = 5,
  sat = 6, saturday = 6, saturdays = 6, sun = 7, sunday = 7, sundays = 7,
}
local DAY_NAMES = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local FILLER = { timer = true, alarm = true, set = true, at = true, ["in"] = true, ["for"] = true, remind = true,
  me = true, to = true, on = true, the = true, an = true, a = true, of = true, wake = true, up = true }

local function flag(name)
  local value = morf.env(name)
  return value ~= nil and value ~= "" and value ~= "0"
end

--- The time now: EVA_NOW where a test sets it.
function M.now() return tonumber(morf.env("EVA_NOW")) or math.floor(morf.time.now()) end

local function store()
  return (morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva/clock/alarms.json"
end

-- --------------------------------------------------------------- the words --

local function tokens_of(words)
  local out = {}
  for word in tostring(words or ""):gmatch("%S+") do out[#out + 1] = { raw = word, low = word:lower() } end
  return out
end

-- Seconds said in `tokens`, marking the words it took.
local function duration(tokens)
  local total, used = 0, false
  local function take(index, seconds)
    tokens[index].used = true
    total, used = total + seconds, true
  end
  for index, token in ipairs(tokens) do
    local low = token.low
    local next_word = tokens[index + 1] and tokens[index + 1].low or ""
    if token.used then
      low = ""
    elseif (low == "half" and next_word == "an" and tokens[index + 2] and tokens[index + 2].low == "hour") then
      take(index, 1800)
      tokens[index + 1].used, tokens[index + 2].used = true, true
    elseif (low == "an" or low == "a") and UNITS[next_word] then
      take(index, UNITS[next_word])
      tokens[index + 1].used = true
    else
      local whole = low:match("^(%d+%.?%d*)$")
      if whole and UNITS[next_word] then
        take(index, tonumber(whole) * UNITS[next_word])
        tokens[index + 1].used = true
      else
        -- "1h30", "1h30m", "90s": number and unit in one word.
        local seconds, rest, found = 0, low, false
        while true do
          local number, unit, tail = rest:match("^(%d+%.?%d*)(%a+)(.*)$")
          if not number or not UNITS[unit] then break end
          seconds, rest, found = seconds + tonumber(number) * UNITS[unit], tail, true
        end
        if found and rest:match("^%d*$") then
          if rest ~= "" then seconds = seconds + tonumber(rest) * 60 end
          take(index, seconds)
        end
      end
    end
  end
  return used and total or nil
end

-- The clock said in `tokens`: hour and minute, marking the words it took.
local function clock_of(tokens)
  local function meridiem(hour, word)
    if word == "pm" and hour < 12 then return hour + 12 end
    if word == "am" and hour == 12 then return 0 end
    return hour
  end
  for index, token in ipairs(tokens) do
    local low, next_word = token.low, tokens[index + 1] and tokens[index + 1].low or ""
    local after_at = index > 1 and tokens[index - 1].low == "at"
    local hour, minute, tail = low:match("^(%d%d?):(%d%d)(%a*)$")
    if not hour then
      hour, tail = low:match("^(%d%d?)([ap]m)$")
      minute = hour and "0"
    end
    if not hour and low:match("^%d%d?$") and (next_word == "am" or next_word == "pm" or after_at) then
      hour, minute, tail = low, "0", ""
    end
    if hour then
      local h, m = tonumber(hour), tonumber(minute)
      token.used = true
      if tail == "" and (next_word == "am" or next_word == "pm") then
        tail = next_word
        tokens[index + 1].used = true
      end
      if h <= 24 and m < 60 then return meridiem(h % 24, tail), m end
    end
    if low == "noon" or low == "midnight" then
      token.used = true
      return low == "noon" and 12 or 0, 0
    end
  end
end

-- The days said in `tokens`: which, whether they repeat, whether it is tomorrow.
local function days_of(tokens)
  local days, repeating, tomorrow = {}, false, false
  for _, token in ipairs(tokens) do
    local low = token.low
    if low == "tomorrow" then tomorrow, token.used = true, true
    elseif low == "today" or low == "tonight" then token.used = true
    elseif low == "every" then repeating, token.used = true, true
    elseif low == "daily" or (low == "day" and repeating) then
      days, repeating, token.used = { 1, 2, 3, 4, 5, 6, 7 }, true, true
    elseif low == "weekdays" or low == "weekday" then
      days, repeating, token.used = { 1, 2, 3, 4, 5 }, true, true
    elseif low == "weekends" or low == "weekend" then
      days, repeating, token.used = { 6, 7 }, true, true
    elseif WEEKDAYS[low] then
      days[#days + 1] = WEEKDAYS[low]
      if low:sub(-1) == "s" and #low > 3 then repeating = true end
      token.used = true
    end
  end
  return days, repeating, tomorrow
end

local function label_of(tokens)
  local out = {}
  for _, token in ipairs(tokens) do
    if not token.used and not FILLER[token.low] then out[#out + 1] = token.raw end
  end
  return table.concat(out, " ")
end

--- When hour:minute next comes after `now`: on one of `days` (any where it is
--- empty), not today when `skip_today`.
function M.next_at(hour, minute, days, now, skip_today)
  local wanted = {}
  for _, day in ipairs(days or {}) do wanted[day] = true end
  local any = next(wanted) == nil
  for offset = skip_today and 1 or 0, 8 do
    local date = morf.time.date(morf.time.add(now, { days = offset }))
    local at = morf.time.time { year = date.year, month = date.month, day = date.day, hour = hour, minute = minute }
    if at > now and (any or wanted[date.weekday]) then return math.floor(at) end
  end
end

--- What `words` ask for: `{ kind = "timer", seconds, label }` or
--- `{ kind = "alarm", hour, minute, days, label, at }`; nil and why when they
--- ask for neither.
function M.parse(words, now)
  now = now or M.now()
  local tokens = tokens_of(words)
  local first = tokens[1] and tokens[1].low
  local hour, minute
  if first ~= "timer" then hour, minute = clock_of(tokens) end
  if hour then
    local days, repeating, tomorrow = days_of(tokens)
    local item = { kind = "alarm", hour = hour, minute = minute, label = label_of(tokens) }
    if repeating then item.days = days end
    item.at = M.next_at(hour, minute, days, now, tomorrow and not repeating)
    return item
  end
  local seconds = duration(tokens)
  if not seconds and first == "timer" and tokens[2] and tokens[2].low:match("^%d+%.?%d*$") then
    seconds = tonumber(tokens[2].low) * 60
    tokens[2].used = true
  end
  if not seconds or seconds <= 0 then return nil, 'Say a time: "timer 12 min pasta" or "at 6pm"' end
  return { kind = "timer", seconds = math.floor(seconds), label = label_of(tokens) }
end

--- `seconds` in words: "12 min", "1 h 30 min", "45 s".
function M.span(seconds)
  seconds = math.floor(seconds + 0.5)
  if seconds < 60 then return seconds .. " s" end
  local hours, minutes, rest = seconds // 3600, (seconds % 3600) // 60, seconds % 60
  local parts = {}
  if hours > 0 then parts[#parts + 1] = hours .. " h" end
  if minutes > 0 then parts[#parts + 1] = minutes .. " min" end
  if rest > 0 and hours == 0 then parts[#parts + 1] = rest .. " s" end
  return table.concat(parts, " ")
end

--- `seconds` as a running clock: "11:32", "1:02:05".
function M.running(seconds)
  seconds = math.max(0, math.ceil(seconds))
  local hours, minutes, rest = seconds // 3600, (seconds % 3600) // 60, seconds % 60
  if hours > 0 then return ("%d:%02d:%02d"):format(hours, minutes, rest) end
  return ("%d:%02d"):format(minutes, rest)
end

--- An entry's days in words: "Weekdays", "Mon Wed", "" for once.
function M.days_words(days)
  if not days or #days == 0 then return "" end
  if #days == 7 then return "Every day" end
  local set = {}
  for _, day in ipairs(days) do set[day] = true end
  if #days == 5 and set[1] and set[2] and set[3] and set[4] and set[5] then return "Weekdays" end
  if #days == 2 and set[6] and set[7] then return "Weekends" end
  local names = {}
  for _, day in ipairs(days) do names[#names + 1] = DAY_NAMES[day] end
  return table.concat(names, " ")
end

--- What `item` will do, in words, for a hint or the command line.
function M.describe(item)
  local label = item.label ~= "" and (" · " .. item.label) or ""
  if item.kind == "timer" then return "Timer " .. M.span(item.seconds) .. label end
  local when = ("%02d:%02d"):format(item.hour, item.minute)
  local days = M.days_words(item.days)
  return "Alarm " .. when .. (days ~= "" and (" " .. days) or "") .. label
end

-- ------------------------------------------------------------- the machine --

-- How a tool of apps/ is reached from a unit, eva-clock unless named: on PATH,
-- else in this tree.
local function cli(tool)
  local name = "eva-" .. (tool or "clock")
  for dir in (morf.env("PATH") or ""):gmatch("[^:]+") do
    if morf.fs.exists(dir .. "/" .. name) then return { dir .. "/" .. name } end
  end
  local folder = tool or "clock"
  for _, relative in ipairs { "../apps/" .. folder .. "/cli", "../" .. folder .. "/cli", "../../" .. folder .. "/cli" } do
    local path = morf.paths.shell(relative)
    if morf.fs.exists(path) then return { "sh", path } end
  end
  return { name }
end

local function uses_systemd()
  local asked = morf.env("EVA_ALARM_ENGINE")
  if asked and asked ~= "" then return asked == "systemd" end
  local run = morf.env("XDG_RUNTIME_DIR")
  return run ~= nil and morf.fs.exists(run .. "/systemd/private")
end

local function calendar(item)
  local stamp = ("*-*-* %02d:%02d:00"):format(item.hour or 0, item.minute or 0)
  if item.days and #item.days > 0 then
    local names = {}
    for _, day in ipairs(item.days) do names[#names + 1] = DAY_NAMES[day] end
    return table.concat(names, ",") .. " " .. stamp
  end
  return morf.time.format("%Y-%m-%d %H:%M:%S", item.at)
end

local function repeats(item) return item.days ~= nil and #item.days > 0 end

--- `options`: `ring` (this process keeps the time where there is no systemd),
--- `delay` (ms it lets another process ring first). Returns the alarms.
function M.new(options)
  options = options or {}
  local a = {
    items = morf.signal("eva.alarm.items", {}),
    ongoing = morf.signal("eva.alarm.ongoing", {}),
    rang = morf.signal("eva.alarm.rang", {}),
    message = morf.signal("eva.alarm.message", ""),
  }
  local timer, watch, planned

  local function read()
    local ok, list = pcall(function() return morf.json.decode(morf.fs.read(store())) end)
    if ok and type(list) == "table" then return list end
    return {}
  end

  local function publish(list)
    a.items:set(list)
    local now, running = M.now(), {}
    for _, item in ipairs(list) do
      if item.on and item.kind == "timer" and item.at > now then running[#running + 1] = item end
    end
    table.sort(running, function(x, y) return x.at < y.at end)
    a.ongoing:set(running)
  end

  local function find(list, id)
    for index, item in ipairs(list) do
      if item.id == id then return item, index end
    end
  end

  local made = 0
  local function fresh_id()
    made = made + 1
    return tostring(math.floor(morf.time.now_ms())) .. "-" .. made
  end

  local schedule

  -- Changes the store from what is on disk now, so two processes do not undo
  -- each other.
  local function change(edit)
    local list = read()
    local answer = edit(list)
    morf.fs.write(store(), morf.json.encode(morf.json.array and morf.json.array(list) or list),
      { atomic = true, parents = true, mode = 384 })
    publish(list)
    schedule()
    return answer
  end

  local function run(argv, done)
    if flag("EVA_DRY_RUN") and not morf.env("EVA_ALARM_ENGINE") then
      morf.log("info", "eva: " .. table.concat(argv, " ") .. " (dry run)")
      if done then done { ok = true } end
      return
    end
    morf.process.run(argv, { timeout_ms = 5000 }, done or function() end)
  end

  local function arm(item)
    if not uses_systemd() or not item.on then return end
    local unit = M.UNIT .. item.id
    run({ "systemctl", "--user", "stop", unit .. ".timer" }, function()
      local argv = { "systemd-run", "--user", "--quiet", "--collect", "--unit=" .. unit,
        "--on-calendar=" .. calendar(item), "--timer-property=AccuracySec=1s" }
      -- A user unit starts with almost nothing of the session it rings in.
      for _, name in ipairs(M.CARRIED) do
        local value = morf.env(name)
        if value and value ~= "" then argv[#argv + 1] = "--setenv=" .. name .. "=" .. value end
      end
      argv[#argv + 1] = "--"
      for _, word in ipairs(cli()) do argv[#argv + 1] = word end
      argv[#argv + 1] = "fire"
      argv[#argv + 1] = item.id
      argv[#argv + 1] = item.label ~= "" and item.label or (item.kind == "timer" and "Timer" or "Alarm")
      run(argv)
    end)
  end

  local function disarm(item)
    if uses_systemd() then run { "systemctl", "--user", "stop", M.UNIT .. item.id .. ".timer" } end
  end

  -- Rings `item` through eva-clock, the one way anything rings.
  local function ring(item)
    local heard = a.rang:get()
    local list = {}
    for _, old in ipairs(heard) do list[#list + 1] = old end
    list[#list + 1] = item.id
    a.rang:set(list)
    local argv = cli()
    argv[#argv + 1] = "fire"
    argv[#argv + 1] = item.id
    argv[#argv + 1] = item.label ~= "" and item.label or (item.kind == "timer" and "Timer" or "Alarm")
    if flag("EVA_DRY_RUN") then
      morf.log("info", "eva: " .. table.concat(argv, " ") .. " (dry run)")
      a.finish(item.id)
      return
    end
    morf.process.detach(argv)
  end

  -- Tells the tool that set an entry, `eva-TOOL rang`, that it has rung.
  local function tell(tool)
    if type(tool) ~= "string" or not tool:match("^%l+$") then return end
    local argv = cli(tool)
    argv[#argv + 1] = "rang"
    if flag("EVA_DRY_RUN") then
      morf.log("info", "eva: " .. table.concat(argv, " ") .. " (dry run)")
      return
    end
    morf.process.detach(argv)
  end

  -- The local engine: one timer, for what rings next.
  schedule = function()
    local soonest
    if options.ring and not uses_systemd() then
      for _, item in ipairs(a.items:get()) do
        if item.on and item.rang ~= item.at and (not soonest or item.at < soonest.at) then soonest = item end
      end
    end
    if timer and soonest and planned == soonest.id .. "@" .. soonest.at then return end
    if timer then timer:cancel() timer = nil end
    if not soonest then return end
    planned = soonest.id .. "@" .. soonest.at
    local wait = math.max(0, (soonest.at - M.now()) * 1000) + (options.delay or 0)
    timer = morf.time.timer(math.floor(wait), function()
      timer = nil
      local list = read()
      local item = find(list, soonest.id)
      if item and item.on and item.rang ~= item.at then
        change(function(fresh)
          local now = find(fresh, item.id)
          if now then now.rang = now.at end
        end)
        ring(item)
      end
      schedule()
    end, false)
  end

  --- Reads the store, and follows it.
  function a.load()
    publish(read())
    schedule()
    if not watch then
      watch = morf.fs.watch(store(), function()
        publish(read())
        schedule()
      end)
    end
  end

  --- Whether anything will ring. A tracked read.
  function a.armed()
    for _, item in ipairs(a.items:get()) do
      if item.on then return true end
    end
    return false
  end

  --- What rings next, or nil. A tracked read.
  function a.next()
    local soonest
    for _, item in ipairs(a.items:get()) do
      if item.on and (not soonest or item.at < soonest.at) then soonest = item end
    end
    return soonest
  end

  --- Adds what `words` ask for, or an entry already worked out (`{ id, kind,
  --- label, at, seconds }`, as the launcher hands one over): the entry, or nil
  --- and why. `tool`, a tool of apps/, hears `eva-TOOL rang` once it has rung.
  function a.add(words, tool)
    local item, why = words, nil
    if type(words) ~= "table" then item, why = M.parse(words) end
    if not item then
      a.message:set(why)
      return nil, why
    end
    item.id = item.id or fresh_id()
    item.on = true
    item.label = item.label or ""
    item.tool = tool
    item.at = item.at or (M.now() + item.seconds)
    if item.kind == "alarm" and not item.hour then
      local date = morf.time.date(item.at)
      item.hour, item.minute = date.hour, date.minute
    end
    change(function(list) list[#list + 1] = item end)
    arm(item)
    a.message:set("")
    return item
  end

  --- Takes `id` away.
  function a.remove(id)
    local item = change(function(list)
      local found, index = find(list, id)
      if found then table.remove(list, index) end
      return found
    end)
    if item then disarm(item) end
  end
  a.cancel = a.remove

  --- What is set, for a surface that lists it.
  function a.list() return a.items:get() end

  --- Turns an alarm on or off.
  function a.set(id, on)
    local item = change(function(list)
      local found = find(list, id)
      if found then
        found.on = on == true
        if found.on and found.kind == "alarm" then
          found.at = M.next_at(found.hour, found.minute, found.days, M.now())
        end
      end
      return found
    end)
    if not item then return end
    if item.on then arm(item) else disarm(item) end
  end

  --- `seconds` more on a running timer.
  function a.extend(id, seconds)
    local item = change(function(list)
      local found = find(list, id)
      if found then found.at, found.seconds = found.at + seconds, found.seconds + seconds end
      return found
    end)
    if item then arm(item) end
  end

  --- It rang: a timer goes, a one-off alarm goes off, a repeating one moves on.
  function a.finish(id)
    local tool = change(function(list)
      local found, index = find(list, id)
      if not found then return end
      if found.kind == "timer" then table.remove(list, index)
      elseif repeats(found) then found.at = M.next_at(found.hour, found.minute, found.days, M.now())
      else found.on = false end
      return found.tool
    end)
    if tool then tell(tool) end
  end

  --- It rings again in `minutes`: a timer of its own, the entry having rung.
  function a.snooze(id, minutes)
    local found = find(read(), id)
    if not found then return end
    a.finish(id)
    local seconds = 60 * (tonumber(minutes) or M.SNOOZE)
    local item = { id = fresh_id(), kind = "timer", label = found.label, seconds = seconds, on = true,
      at = M.now() + seconds }
    change(function(list) list[#list + 1] = item end)
    arm(item)
  end

  --- Puts every entry on the machine again, after a login or a restart; what
  --- came due meanwhile rings now, or is reported missed.
  function a.sync()
    local now = M.now()
    for _, item in ipairs(read()) do
      if item.on and item.rang ~= item.at and item.at <= now then
        if repeats(item) then
          a.finish(item.id)
        elseif now - item.at > M.MISSED then
          a.message:set("Missed: " .. M.describe(item))
          a.finish(item.id)
        else
          ring(item)
        end
      end
    end
    for _, item in ipairs(read()) do
      if item.on and item.at > now and uses_systemd() then
        run({ "systemctl", "--user", "is-active", "--quiet", M.UNIT .. item.id .. ".timer" }, function(result)
          if not result.ok then arm(item) end
        end)
      end
    end
    publish(read())
    schedule()
  end

  return a
end

--- `eva-clock`'s command as a job: `done(text, why)`.
function M.job(args, done)
  local a = M.new()
  a.load()
  local how = args[1]
  local words = {}
  for index = 2, #args do words[#words + 1] = args[index] end
  -- A running unit is started by a process that ends with the job.
  local function after(text, why) morf.time.timer(300, function() done(text, why) end, false) end
  if how == "add" then
    local item, why = a.add(table.concat(words, " "))
    if not item then done(nil, why) return end
    after(M.describe(item) .. " at " .. morf.time.format("%H:%M:%S", item.at))
  elseif how == "list" then
    local lines = {}
    for _, item in ipairs(a.items:get()) do
      if item.on then lines[#lines + 1] = item.id .. "  " .. M.describe(item) end
    end
    done(#lines > 0 and table.concat(lines, "\n") or "nothing set")
  elseif how == "cancel" then
    local wanted = table.concat(words, " ")
    local gone = 0
    for _, item in ipairs(a.items:get()) do
      if wanted == "all" or item.id == wanted or item.label == wanted then
        a.remove(item.id)
        gone = gone + 1
      end
    end
    if gone == 0 then done(nil, "nothing called " .. wanted) return end
    after(gone == 1 and "cancelled" or (gone .. " cancelled"))
  elseif how == "snooze" then
    a.snooze(words[1], words[2])
    after("snoozed")
  elseif how == "done" then
    a.finish(words[1])
    after("done")
  elseif how == "sync" then
    a.sync()
    after("synced")
  else
    done(nil, "unknown command: " .. tostring(how))
  end
end

return M
