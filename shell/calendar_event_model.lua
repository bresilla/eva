-- One calendar event on the page: the form over it, and what saving and
-- deleting ask of its calendar. State only: the files are calendar_sources'.
local morf = require("morf")
local ical = require("lib.integrations.ical")
local M = {}

M.REPEATS = { { "none", "block", "Never" }, { "DAILY", "today", "Daily" }, { "WEEKLY", "date_range", "Weekly" },
  { "MONTHLY", "calendar_month", "Monthly" }, { "YEARLY", "event_repeat", "Yearly" } }
M.REMINDERS = { { "default", nil, "Default" }, { "none", nil, "None" }, { "0", nil, "At start" }, { "300", nil, "5 min" },
  { "900", nil, "15 min" }, { "1800", nil, "30 min" }, { "3600", nil, "1 hour" }, { "86400", nil, "1 day" } }
-- Before an all-day event's midnight: 54000 seconds is 9:00 the day before.
M.DAY_REMINDERS = { { "default", nil, "That morning" }, { "54000", nil, "Day before" }, { "none", nil, "None" } }
M.SCOPES = { { "one", "event", "This one" }, { "all", "event_repeat", "All of them" } }

local BLANK = { summary = "", location = "", description = "", from_day = "", from_time = "", to_day = "", to_time = "",
  all_day = false, repeats = "none", until_day = "", reminder = "default", calendar = "", scope = "all" }
local TEXT = { "summary", "location", "description" }

--- "YYYY-MM-DD" as `{ year, month, day }`, or nil if no such day.
local function day_of(text)
  local y, m, d = tostring(text):match("^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*$")
  if not y then return nil end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m < 1 or m > 12 or d < 1 then return nil end
  local ry, rm, rd = ical.civil_from_days(ical.days_from_civil(y, m, d))
  if ry ~= y or rm ~= m or rd ~= d then return nil end
  return { year = y, month = m, day = d }
end

--- "9", "9:30" or "0930" as hours and minutes, or nil.
local function clock_of(text)
  text = tostring(text):match("^%s*(.-)%s*$")
  local h, n = text:match("^(%d%d?):(%d%d)$")
  if not h then h, n = text:match("^(%d%d)(%d%d)$") end
  if not h then h, n = text:match("^(%d%d?)$"), "0" end
  h, n = tonumber(h), tonumber(n)
  if not h or h > 23 or n > 59 then return nil end
  return h, n
end

local function day_text(at) return morf.time.format("%Y-%m-%d", at) end
local function clock_text(at) return morf.time.format("%H:%M", at) end

--- `freq` and last day ("YYYY-MM-DD" or "") of a rule the form can say, or
--- "custom" for one it cannot.
function M.plain_rule(event)
  local rule = event.rule
  if not rule then return "none", "" end
  local text = (event.rule_text or ""):upper()
  for key in text:gmatch("([%w%-]+)=") do
    if key ~= "FREQ" and key ~= "UNTIL" and key ~= "WKST" then return "custom", "" end
  end
  if not rule.freq or rule.interval ~= 1 then return "custom", "" end
  local last = ""
  if rule.until_time then
    local epoch = ical.epoch(rule.until_time)
    last = day_text(epoch)
  end
  return rule.freq, last
end

local function reminder_of(event)
  if event.no_alarm then return "none" end
  local alarms = event.alarms or {}
  if #alarms == 0 then return "default" end
  if #alarms > 1 then return "custom" end
  local key = tostring(math.floor(alarms[1]))
  for _, row in ipairs(event.all_day and M.DAY_REMINDERS or M.REMINDERS) do
    if row[1] == key then return key end
  end
  return "custom"
end

function M.new(ctx)
  local sources = ctx.sources
  local model = { REPEATS = M.REPEATS, REMINDERS = M.REMINDERS, DAY_REMINDERS = M.DAY_REMINDERS, SCOPES = M.SCOPES,
    mode = morf.signal("eva.calendar.event.mode", ""), error = morf.signal("eva.calendar.event.error", ""),
    deleting = morf.signal("eva.calendar.event.deleting", false), revision = morf.signal("eva.calendar.event.revision", 0),
    draft = morf.state(BLANK), locked_why = morf.signal("eva.calendar.event.locked", ""),
    calendar_name = morf.signal("eva.calendar.event.calendar", ""), repeating = morf.signal("eva.calendar.event.repeating", false) }
  local item, original = nil, {}

  local function fill(values)
    original = {}
    for key, value in pairs(BLANK) do
      local now = values[key]
      if now == nil then now = value end
      model.draft[key], original[key] = now, now
    end
    model.error:set("")
    model.deleting:set(false)
    model.revision:set(model.revision:get() + 1)
  end

  --- Opens an empty form on `day` ("YYYY-MM-DD"), in the first calendar that
  --- can take it.
  function model.create(day)
    if not ctx.active() then return false end
    day = day or ctx.day()
    local now = morf.time.now()
    local base = morf.time.date(now)
    local hour = day == day_text(now) and math.min(base.hour + 1, 22) or 9
    local calendars = sources.writable()
    item = nil
    fill { from_day = day, to_day = day, from_time = ("%02d:00"):format(hour), to_time = ("%02d:00"):format(hour + 1),
      calendar = calendars[1] and calendars[1].id or "" }
    model.locked_why:set("")
    model.repeating:set(false)
    model.calendar_name:set("")
    model.mode:set("new")
    return true
  end

  --- Opens the event at this instance: its form, or what it says where its
  --- calendar cannot be written.
  function model.open(uid, at)
    if not ctx.active() then return false end
    local found = sources.instance(uid, at)
    if not found then return false end
    item = found
    local event, master = found.event, sources.master(found.event)
    local repeats, last = M.plain_rule(master)
    local to = found.all_day and math.max(found.at, found.ends - 1) or found.ends
    fill { summary = event.summary or "", location = event.location or "", description = event.description or "",
      from_day = day_text(found.at), from_time = clock_text(found.at), to_day = day_text(to), to_time = clock_text(to),
      all_day = found.all_day == true, repeats = repeats, until_day = last, reminder = reminder_of(event),
      calendar = event.calendar or "", scope = (master.rule ~= nil) and "one" or "all" }
    local locked = sources.locked(event.calendar) or ""
    model.locked_why:set(locked)
    model.repeating:set(master.rule ~= nil)
    model.calendar_name:set(event.calendar_name or "")
    model.mode:set(locked ~= "" and "read" or "edit")
    return true
  end

  function model.close()
    item = nil
    model.deleting:set(false)
    model.mode:set("")
  end

  function model.set(name, value)
    if BLANK[name] == nil then return end
    model.draft[name] = value
    model.deleting:set(false)
  end

  --- The calendars a new event can go in.
  function model.calendars() return sources.writable() end
  --- Whether it is the whole of a repeating event being changed, or a single one.
  function model.single() return model.repeating:get() and model.draft.scope == "one" end
  --- Whether this rule is one the form cannot say.
  function model.custom() return model.draft.repeats == "custom" end

  local function day_gap(from, to)
    return ical.days_from_civil(to.year, to.month, to.day) - ical.days_from_civil(from.year, from.month, from.day)
  end

  local function plus_days(date, days)
    local y, m, d = ical.civil_from_days(ical.days_from_civil(date.year, date.month, date.day) + days)
    return { year = y, month = m, day = d }
  end

  -- The form's start and end as `{ from, to, days }`: instants for a timed
  -- event, civil dates for an all-day one. Nil and why when they do not read.
  local function times()
    local d = model.draft
    local from_day, to_day = day_of(d.from_day), day_of(d.to_day)
    if not from_day then return nil, "The start is not a date: write 2026-11-01." end
    if not to_day then return nil, "The end is not a date: write 2026-11-01." end
    if d.all_day then
      local days = day_gap(from_day, to_day)
      if days < 0 then return nil, "It ends before it starts." end
      return { from = from_day, to = to_day, days = days }
    end
    local h, n = clock_of(d.from_time)
    if not h then return nil, "The start time is not a time: write 9:30." end
    local eh, en = clock_of(d.to_time)
    if not eh then return nil, "The end time is not a time: write 10:30." end
    local from = morf.time.time { year = from_day.year, month = from_day.month, day = from_day.day, hour = h, minute = n }
    local to = morf.time.time { year = to_day.year, month = to_day.month, day = to_day.day, hour = eh, minute = en }
    if to < from then return nil, "It ends before it starts." end
    return { from = from, to = to }
  end

  -- The start and end to write. Moving a whole repeating event moves its first
  -- day by what the shown one moved, so its rule stays where it was.
  local function timing(span, master, repeats)
    local first = day_of(model.draft.from_day)
    if master and master.rule and not model.single() then
      first = plus_days(morf.time.date(ical.epoch(master.start)), day_gap(day_of(original.from_day), first))
    end
    if model.draft.all_day then
      local function date(day)
        return { year = day.year, month = day.month, day = day.day, hour = 0, minute = 0, second = 0, date = true }
      end
      return date(first), date(plus_days(first, span.days + 1))
    end
    local like = (master and not master.start.date) and { zone = master.start.zone } or { zone = "utc" }
    if repeats and like.zone == "utc" then like = {} end
    local clock = morf.time.date(span.from)
    local from = morf.time.time { year = first.year, month = first.month, day = first.day, hour = clock.hour, minute = clock.minute }
    return ical.time_at(from, like), ical.time_at(from + (span.to - span.from), like)
  end

  local function alarms_of(key)
    if key == "none" then return false end
    if key == "default" then return {} end
    return { tonumber(key) }
  end

  -- What saving would change, or nil and why.
  local function build()
    local d, new = model.draft, item == nil
    local master = item and sources.master(item.event)
    if (d.summary or ""):match("^%s*$") then return nil, "Give it a name." end
    local span, why = times()
    if not span then return nil, why end
    local change = {}
    for _, name in ipairs(TEXT) do
      if new or d[name] ~= original[name] then change[name] = d[name] end
    end
    local single = model.single()
    local rule_changed = not single and d.repeats ~= "custom"
      and (new or d.repeats ~= original.repeats or d.until_day ~= original.until_day)
    local repeats = rule_changed and d.repeats ~= "none"
    -- Starting to repeat lets go of UTC, so it keeps its hour over a clock change.
    local moved = new or single or d.all_day ~= original.all_day or (repeats and master and master.start.zone == "utc")
    for _, name in ipairs { "from_day", "to_day", "from_time", "to_time" } do moved = moved or d[name] ~= original[name] end
    if moved or rule_changed then
      local start, finish = timing(span, master, repeats)
      if moved then change.start, change.finish = start, finish end
      if rule_changed then change.rule = repeats and ical.rule_text(d.repeats, d.until_day, start) or "" end
    end
    if d.reminder ~= "custom" and d.reminder ~= original.reminder then change.alarms = alarms_of(d.reminder) end
    if new and change.rule == "" then change.rule = nil end
    return change
  end

  --- Saves the form to the event's calendar. True, or false with what went
  --- wrong in `error`.
  function model.save()
    if model.mode:get() ~= "new" and model.mode:get() ~= "edit" then return false end
    local change, why = build()
    if not change then model.error:set(why) return false end
    if next(change) == nil then model.close() return true end
    local done, failed
    if item then done, failed = sources.change(item, change, model.single())
    else done, failed = sources.create(model.draft.calendar ~= "" and model.draft.calendar or nil, change) end
    if not done then model.error:set(tostring(failed)) return false end
    model.close()
    return true
  end

  --- The first press asks; the second takes the event out.
  function model.delete()
    if model.mode:get() ~= "edit" or not item then return false end
    if not model.deleting:get() then model.deleting:set(true) return false end
    local done, failed = sources.delete(item, model.single())
    if not done then
      model.deleting:set(false)
      model.error:set(tostring(failed))
      return false
    end
    model.close()
    return true
  end

  --- A person's words for when it is, on a page that only reads.
  function model.when()
    local d = model.draft
    if d.all_day then return d.from_day == d.to_day and d.from_day .. " · All day" or (d.from_day .. " to " .. d.to_day) end
    return d.from_day .. " · " .. d.from_time .. "–" .. d.to_time
  end
  return model
end

return M
