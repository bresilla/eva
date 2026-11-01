-- Screen time: which app held the focus and for how long, by day, in one file on
-- this machine; nothing leaves it. A limit, downtime and bedtime warn and can be
-- overridden, as a shell cannot stop an app. No nodes.
--
-- What is measured comes from the compositor's focused-window events and a slow
-- tick. Locked time does not count, and no gap counts for more than two ticks,
-- so a night asleep adds nothing. `M.now` is the clock; a spec sets its own.
local morf = require("morf")
local config = require("config")

local M = {}

-- Seconds between looks, the days kept, and the minutes "more" gives.
M.TICK, M.DAYS_KEPT, M.MORE = 30, 30, 15
M.LIMITS = { { 0, "None" }, { 15, "15 m" }, { 30, "30 m" }, { 60, "1 h" }, { 120, "2 h" } }
M.PERIODS = { { 1, "Today" }, { 2, "Yesterday" }, { 7, "7 days" } }
local EVERY_DAY = { 1, 2, 3, 4, 5, 6, 7 }

M.now = function() return morf.time.now() end
-- What the warning says, or false: `{ kind, key, name, waiting }`, `waiting` an app
-- not yet opened.
M.notice = morf.signal("eva.screen_time.notice", false)
-- Moves as the counts change.
M.revision = morf.signal("eva.screen_time.revision", 0)
-- The Settings page's choices: how far back it looks, and the app it is on.
M.period = morf.signal("eva.screen_time.period", 1)
M.selected = morf.signal("eva.screen_time.selected", "")

local function path() return morf.env("EVA_SCREEN_TIME") or morf.paths.state("eva-screen-time.json") end

-- The file: `days[date][app]` seconds, `more[date][app]` minutes, `warned[date]`
-- which warnings were given, and `bedtime`, what it changed while on.
local store

local function load_store()
  if store then return store end
  local ok, text = pcall(morf.fs.read, path())
  local fine, data = pcall(morf.json.decode, ok and text or "")
  store = fine and type(data) == "table" and data or {}
  store.days, store.more, store.warned = store.days or {}, store.more or {}, store.warned or {}
  store.bedtime = store.bedtime or {}
  return store
end

local function save()
  morf.fs.write(path(), morf.json.encode(load_store()), { atomic = true, parents = true, mode = 384 })
end

local function bump() M.revision:set(M.revision:get() + 1) end

--- The date `at` falls on, as the file keys it.
function M.day(at) return morf.time.format("%Y-%m-%d", at or M.now()) end

local function trim()
  local keys = {}
  for key in pairs(store.days) do keys[#keys + 1] = key end
  table.sort(keys)
  for index = 1, #keys - M.DAYS_KEPT do
    store.days[keys[index]], store.more[keys[index]], store.warned[keys[index]] = nil, nil, nil
  end
end

-- ----------------------------------------------------------------- limits --

--- The minutes `key` may have a day, nil without a limit.
function M.limit(key)
  for _, row in ipairs(config.get("wellbeing.limits")) do
    if row.app == key then return row.minutes end
  end
end

--- Gives `key` `minutes` a day; 0 takes its limit away.
function M.set_limit(key, minutes)
  local out = {}
  for _, row in ipairs(config.get("wellbeing.limits")) do
    if row.app ~= key then out[#out + 1] = row end
  end
  if (minutes or 0) > 0 then out[#out + 1] = { app = key, minutes = minutes } end
  config.set("wellbeing.limits", out)
end

--- The seconds `key` has had on the date `day`.
function M.used(key, day)
  load_store()
  M.revision:get()
  return (store.days[day or M.day()] or {})[key] or 0
end

--- Whether today's limit on `key` is used up.
function M.spent(key)
  local minutes = M.limit(key)
  if not minutes then return false end
  local day = M.day()
  return M.used(key, day) >= (minutes + ((load_store().more[day] or {})[key] or 0)) * 60
end

local function warned(kind, key) return ((load_store().warned[M.day()] or {})[kind .. ":" .. key]) == true end

local function mark_warned(kind, key)
  local day = M.day()
  store.warned[day] = store.warned[day] or {}
  store.warned[day][kind .. ":" .. key] = true
end

--- Whether downtime is on now.
function M.downtime(at)
  local spec = config.get("wellbeing.downtime")
  if spec.on ~= true then return false end
  return require("focus_model").window({ from = spec.from, to = spec.to, days = EVERY_DAY }, at or M.now()) ~= nil
end

--- Whether `key` is let through downtime.
function M.allowed(key)
  for _, id in ipairs(config.get("wellbeing.downtime.allowed")) do
    if id == key then return true end
  end
  return false
end

--- Lets `key` through downtime, or stops letting it.
function M.set_allowed(key, on)
  local out = {}
  for _, id in ipairs(config.get("wellbeing.downtime.allowed")) do
    if id ~= key then out[#out + 1] = id end
  end
  if on then out[#out + 1] = key end
  config.set("wellbeing.downtime.allowed", out)
end

-- What `key` should be warned of now, or nil.
local function due(key)
  if M.downtime() and not M.allowed(key) then return "downtime" end
  if M.spent(key) then return "limit" end
end

-- ---------------------------------------------------------------- names --

--- How `key` reads: its app's name and icon, or the key as it came.
function M.name_of(key)
  local apps = require("apps")
  local row = apps.row(key)
  return row and row.name or key, row and row.icon or ""
end

--- Seconds as a person reads them.
function M.words(seconds)
  local minutes = math.floor((seconds or 0) / 60)
  if minutes < 1 then return (seconds or 0) > 0 and "Under a minute" or "None" end
  if minutes < 60 then return minutes .. " min" end
  local rest = minutes % 60
  return (minutes // 60) .. " h" .. (rest > 0 and " " .. rest .. " min" or "")
end

--- What the last `count` days (ending today, or the one before for `start` 1)
--- held: rows `{ key, name, seconds }`, most used first, and the total.
function M.report(count, start)
  load_store()
  M.revision:get()
  local sums, total = {}, 0
  for back = start or 0, (start or 0) + count - 1 do
    for key, seconds in pairs(store.days[M.day(M.now() - back * 86400)] or {}) do
      sums[key] = (sums[key] or 0) + seconds
      total = total + seconds
    end
  end
  local rows = {}
  for key, seconds in pairs(sums) do rows[#rows + 1] = { key = key, name = (M.name_of(key)), seconds = seconds } end
  table.sort(rows, function(a, b)
    if a.seconds ~= b.seconds then return a.seconds > b.seconds end
    return a.name < b.name
  end)
  return rows, total
end

--- What the page's period shows: `report`'s two answers.
function M.shown()
  local choice = M.period:get()
  if choice == 2 then return M.report(1, 1) end
  return M.report(choice)
end

--- Forgets everything counted, the settings staying.
function M.forget()
  local bedtime = load_store().bedtime
  store = { days = {}, more = {}, warned = {}, bedtime = bedtime }
  save()
  bump()
end

-- ---------------------------------------------------------------- warnings --

local pending

local function raise(kind, key, go)
  pending = go
  M.notice:set { kind = kind, key = key, name = (M.name_of(key)), waiting = go ~= nil }
end

--- Whether opening `row` waits for a word first: true once the warning is up,
--- and `go()` runs if the person opens it all the same.
function M.holds(row, go)
  if config.get("wellbeing.enabled") ~= true then return false end
  local kind = due(row.id)
  if not kind or warned(kind, row.id) then return false end
  raise(kind, row.id, go)
  return true
end

local function closes()
  local now = M.notice:get()
  M.notice:set(false)
  pending = nil
  return now
end

--- Lets it be for the rest of the day, opening what was waiting.
function M.override()
  local go, now = pending, M.notice:get()
  if now then
    mark_warned(now.kind, now.key)
    save()
  end
  closes()
  if go then go() end
end

--- `M.MORE` minutes more of the app warned about, today.
function M.extend()
  local go, now = pending, M.notice:get()
  if not now then return end
  local day = M.day()
  store.more[day] = store.more[day] or {}
  store.more[day][now.key] = (store.more[day][now.key] or 0) + M.MORE
  save()
  bump()
  closes()
  if go then go() end
end

--- Leaves what was waiting shut, and closes the app's window if it has one up.
function M.step_away()
  local now, waiting = M.notice:get(), pending
  closes()
  if not now or waiting then return end
  local windows = require("windows_model")
  local window = windows.active()
  if window and M.app_of(window.class) == now.key then windows.close(window.address) end
end

-- --------------------------------------------------------------- measuring --

local held

--- The app a window's class belongs to: its desktop entry where it has one.
function M.app_of(class)
  local entry = require("apps").entry_for(class)
  return entry and entry.id or class
end

local function locked()
  local ok, is = pcall(function() return require("wallpaper_model").locked() end)
  return ok and is == true
end

-- Adds what has passed to the app that held the focus.
local function bank()
  local now = M.now()
  if not held then return end
  local seconds = math.max(0, math.min(now - held.since, 2 * M.TICK))
  held.since = now
  if seconds <= 0 or locked() then return end
  load_store()
  local day = M.day(now)
  store.days[day] = store.days[day] or {}
  store.days[day][held.key] = (store.days[day][held.key] or 0) + seconds
  trim()
  save()
  bump()
end

local function check()
  if not held or M.notice:get() then return end
  local kind = due(held.key)
  if kind and not warned(kind, held.key) then raise(kind, held.key) end
end

--- `class` has the focus now, "" for nothing.
function M.focus(class)
  bank()
  held = class and class ~= "" and { key = M.app_of(class), since = M.now() } or nil
  check()
end

--- Looks again at what has the focus.
function M.sample(address)
  if config.get("wellbeing.enabled") ~= true then
    held = nil
    return
  end
  local windows = require("windows_model")
  local window = address and address ~= "" and windows.get(address) or windows.active()
  M.focus(window and window.class or "")
end

-- ----------------------------------------------------------------- bedtime --

--- Whether bedtime is on now.
function M.bedtime() M.revision:get() return load_store().bedtime.on == true end

local function schedule_window(at)
  local spec = config.get("wellbeing.bedtime")
  if spec.on ~= true then return nil end
  return require("focus_model").window({ from = spec.from, to = spec.to, days = EVERY_DAY }, at or M.now())
end

local function enter()
  local kept, spec = store.bedtime, config.get("wellbeing.bedtime")
  local filters = require("quick_hardware").filters()
  kept.on = true
  kept.greyed = spec.grayscale == true and not filters.on("grayscale")
  if kept.greyed then filters.set("grayscale", true) end
  local focus = require("focus_model")
  kept.quieted = spec.quiet == true and focus.active_id() == ""
  if kept.quieted then focus.start("sleep", { source = "bedtime" }) end
end

local function leave()
  local kept = store.bedtime
  if kept.greyed then require("quick_hardware").filters().set("grayscale", false) end
  local focus = require("focus_model")
  if kept.quieted and focus.source() == "bedtime" then focus.stop() end
  kept.on, kept.greyed, kept.quieted = false, false, false
end

local function settle_bedtime()
  local kept = load_store().bedtime
  local window = schedule_window()
  if kept.skip and kept.skip ~= window then kept.skip = nil end
  local wanted = kept.manual == true or (window ~= nil and kept.skip == nil)
  if wanted == (kept.on == true) then return end
  if wanted then enter() else leave() end
  save()
  bump()
end

--- Bedtime on or off by hand. Off inside its hours, it stays off till they end.
function M.set_bedtime(on)
  local kept = load_store().bedtime
  kept.manual = on == true
  kept.skip = not on and schedule_window() or nil
  settle_bedtime()
end

-- ------------------------------------------------------------- the settings --

--- The hours of `key` ("wellbeing.downtime.from" and so on), if `text` is a time.
function M.set_time(key, text)
  local hour, minute = tostring(text):match("^(%d%d):(%d%d)$")
  if hour and tonumber(hour) < 24 and tonumber(minute) < 60 then config.set(key, text) end
end

--- Starts measuring, from the screen that holds the shell's duties.
function M.start()
  if morf.window.primary and not morf.window.primary() then return end
  local hyprland = require("services").hyprland
  if hyprland and hyprland.on then hyprland.on("activewindowv2", M.sample) end
  morf.time.timer(M.TICK * 1000, function()
    M.sample()
    settle_bedtime()
  end, true)
  morf.effect("eva.screen_time.bedtime", function()
    config.get("wellbeing.bedtime")
    settle_bedtime()
  end)
  M.sample()
end

--- `screen-time status|today|bedtime on|off`; `screen-time warn ID` shows the
--- warning for the app ID, to look at.
function M.verb(how, value)
  how = how or "status"
  if how == "warn" then
    raise("limit", value)
    return true
  end
  if how == "bedtime" then
    if value == "on" or value == "off" then M.set_bedtime(value == "on") end
    return M.bedtime()
  end
  if how == "today" then
    local rows = M.report(1)
    return rows
  end
  if how == "status" then
    local _, total = M.report(1)
    return { enabled = config.get("wellbeing.enabled"), total = total, app = held and held.key or "",
      downtime = M.downtime(), bedtime = M.bedtime(), notice = M.notice:get() }
  end
  error("`" .. tostring(how) .. "`: status, today, bedtime or warn")
end

return M
