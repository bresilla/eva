-- Calendar reminders, raised through the shell's notification list on the
-- primary screen: each event at its own alarm, or `calendar.lead` minutes
-- before when it names none, none at all when it says so, and one morning
-- line for the day's all-day events. What was said is kept on disk, so a
-- reload says nothing twice.
local morf = require("morf")
local config = require("config")
local M = { DIGEST_HOUR = 8, TICK_MS = 30000 }
local timer, fired

local function path() return morf.paths.state("calendar-reminders.json") end

local function load_fired()
  if fired then return end
  fired = {}
  if morf.fs.exists(path()) then
    local ok, text = pcall(morf.fs.read, path())
    local fine, value = pcall(morf.json.decode, ok and text or "")
    if fine and type(value) == "table" then fired = value end
  end
end

local function remember(key, at)
  fired[key] = at
  local now = morf.time.now()
  for name, when in pairs(fired) do
    if type(when) ~= "number" or when < now - 86400 * 3 then fired[name] = nil end
  end
  morf.fs.write(path(), morf.json.encode(fired))
end

local function primary() return not morf.window.primary or morf.window.primary() end

--- The seconds before `item` its reminders fall, largest first. An event that
--- turned reminders off has none; an all-day one without its own is left to
--- the morning line.
function M.leads(item)
  if item.event.no_alarm then return {} end
  local alarms = item.event.alarms or {}
  if #alarms > 0 then
    local out = {}
    for i, alarm in ipairs(alarms) do out[i] = alarm end
    table.sort(out, function(a, b) return a > b end)
    return out
  end
  if item.all_day then return {} end
  return { (tonumber(config.get("calendar.lead")) or 10) * 60 }
end

local function words(item, now)
  if item.all_day then return morf.time.format("%A %-d %B", item.at) .. " · All day" end
  local minutes = math.max(0, math.floor((item.at - now) / 60 + 0.5))
  local when = minutes == 0 and "Starting now" or ("In %d %s"):format(minutes, minutes == 1 and "minute" or "minutes")
  local parts = { when .. ", " .. morf.time.format("%H:%M", item.at) }
  if (item.event.location or "") ~= "" then parts[#parts + 1] = item.event.location end
  return table.concat(parts, " · ")
end

--- Raises whatever is due at `now`. Returns how many were raised.
function M.tick(now)
  if config.get("calendar.reminders") == false then return 0 end
  load_fired()
  local sources, notifs = require("calendar_sources"), require("notifs")
  local raised = 0
  for _, item in ipairs(sources.between(now - 60, now + 86400 * 8)) do
    for _, lead in ipairs(M.leads(item)) do
      local due = item.at - lead
      local key = (item.event.uid or item.event.summary or "") .. "@" .. tostring(item.at) .. "-" .. tostring(lead)
      if now >= due and now < item.at + 60 and not fired[key] then
        remember(key, now)
        notifs.push { app = "Calendar", summary = item.event.summary or "Event", body = words(item, now), icon = "x-office-calendar" }
        raised = raised + 1
        break
      end
    end
  end
  local date = morf.time.date(now)
  local today = morf.time.format("%Y-%m-%d", now)
  if date.hour >= M.DIGEST_HOUR and not fired["digest-" .. today] then
    local names = {}
    for _, item in ipairs(sources.on_day(today)) do
      if item.all_day and not item.event.no_alarm then names[#names + 1] = item.event.summary or "Event" end
    end
    if #names > 0 then
      remember("digest-" .. today, now)
      notifs.push { app = "Calendar", summary = "Today", body = table.concat(names, ", "), icon = "x-office-calendar" }
      raised = raised + 1
    end
  end
  return raised
end

--- Starts the reminders where this is the primary screen and any calendar is
--- set up. Nothing runs otherwise.
function M.start()
  if timer or not primary() then return false end
  local sources = require("calendar_sources")
  if not sources.configured() then return false end
  sources.watch(true)
  timer = morf.time.timer(M.TICK_MS, function() M.tick(morf.time.now()) end, true)
  return true
end

function M.stop()
  if timer then timer:cancel() timer = nil end
end

--- Whether the reminders are keeping the calendars read.
function M.running() return timer ~= nil end

return M
