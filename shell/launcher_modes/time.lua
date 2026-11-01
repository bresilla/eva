-- What is to be done: Taskwarrior tasks, timers and alarms, notes, and today's
-- agenda.
local morf = require("morf")
local registry = require("lib.shell.launcher.registry")
local rows = require("lib.shell.launcher.rows")
local run = require("lib.shell.launcher.run")
local dates = require("lib.shell.launcher.dates")

local M = {}

local row, note = rows.row, rows.note

-- ------------------------------------------------------------------ tasks --

--- What the words of a new task say: its description, and `project:x`,
--- `due:friday`, `sched:monday`, `pri:H` and `+tag` taken out of it.
function M.parse_task(text)
  local fields, words, tags = {}, {}, {}
  local NAMES = { project = "project", pro = "project", due = "due", scheduled = "scheduled", sched = "scheduled",
    priority = "priority", pri = "priority", wait = "wait", recur = "recur" }
  for word in text:gmatch("%S+") do
    local key, value = word:match("^(%a+):(.+)$")
    local tag = word:match("^%+([%w_%-]+)$")
    if key and NAMES[key:lower()] then
      fields[NAMES[key:lower()]] = NAMES[key:lower()] == "priority" and value:upper() or value
    elseif tag then
      tags[#tags + 1] = tag
    else
      words[#words + 1] = word
    end
  end
  fields.description = table.concat(words, " ")
  if #tags > 0 then fields.tags = table.concat(tags, ",") end
  return fields
end

local function client() return require("planner").client end

local function loaded()
  local c = client()
  if not c.loaded:get() and not c.busy:get() and not M.asked_tasks then
    M.asked_tasks = true
    morf.time.timer(1, c.refresh, false)
  end
  return c
end

local function open_tasks()
  require("pages").open("tasks")
  return "close"
end

local function task_action(uuid, action)
  return function()
    if run.dry() then morf.log("info", "eva: launcher (dry run): task " .. action) return "close" end
    client().action(uuid, action)
    return "close"
  end
end

local function task_rows(term)
  local c = loaded()
  local list = {}
  for _, t in ipairs(c.tasks:get()) do
    local tags = table.concat(t.tags or {}, " ")
    list[#list + 1] = { task = t, name = t.description, description = (t.project or "") .. " " .. tags }
  end
  local out = {}
  for _, item in ipairs(rows.fuzzy(list, term)) do
    local t = item.task
    local details = {}
    if t.project and t.project ~= "" then details[#details + 1] = t.project end
    if t.priority and t.priority ~= "" then details[#details + 1] = "Priority " .. t.priority end
    if t.due then details[#details + 1] = "Due " .. dates.relative(require("lib.integrations.taskwarrior").timestamp(t.due) or 0) end
    if t.start then details[#details + 1] = "In progress" end
    out[#out + 1] = row {
      id = "task:" .. t.uuid, name = t.description, description = table.concat(details, "  ·  "), material = t.start and "play_circle" or "check_box_outline_blank",
      tag = "Task", copy = t.description, run = task_action(t.uuid, "done"),
      actions = {
        { name = "Finish it", material = "task_alt", run = task_action(t.uuid, "done") },
        { name = t.start and "Stop working on it" or "Start working on it", material = t.start and "stop" or "play_arrow",
          run = task_action(t.uuid, t.start and "stop" or "start") },
        { name = "Delete it", material = "delete", run = task_action(t.uuid, "delete") },
        { name = "Open the task list", material = "checklist", run = open_tasks },
      },
    }
    if #out >= 30 then break end
  end
  return out
end

registry.mode { id = "tasks", name = "Tasks", material = "checklist", shape = "cookie9", words = { "task", "tasks", "todo" },
  hint = "task buy milk due:friday +home  ·  Taskwarrior", search = function(term)
    local out = {}
    if term ~= "" then
      local fields = M.parse_task(term)
      if fields.description ~= "" then
        local bits = {}
        for _, key in ipairs { "project", "due", "scheduled", "priority", "tags" } do
          if fields[key] then bits[#bits + 1] = key .. " " .. fields[key] end
        end
        out[1] = row { id = "task:new", name = "Add “" .. fields.description .. "”", material = "add_task",
          description = #bits > 0 and table.concat(bits, "  ·  ") or "A new task  ·  Return adds it",
          run = function()
            if run.dry() then morf.log("info", "eva: launcher (dry run): add task " .. fields.description) return "close" end
            client().save(nil, fields)
            return "close"
          end }
      end
    end
    local c = loaded()
    for _, r in ipairs(task_rows(term)) do out[#out + 1] = r end
    if #out == 0 then
      local why = c.error:get()
      out[1] = note("task", why ~= "" and "Taskwarrior did not answer" or "No tasks yet", why ~= "" and why or "Type one to add it", "checklist")
    end
    return out
  end }

-- ----------------------------------------------------------------- timers --

local function timers() return require("timers_model") end

local function left_of(entry)
  local left = entry.at - morf.time.now()
  if entry.kind == "alarm" then return morf.time.format("%H:%M, %a %-d %b", entry.at) end
  return left > 0 and (dates.span(left) .. " left") or "Ringing"
end

local function set_rows()
  local out = {}
  for _, entry in ipairs(timers().list()) do
    local id = entry.id
    out[#out + 1] = row {
      id = "timer:" .. id, name = entry.label ~= "" and entry.label or (entry.kind == "alarm" and "Alarm" or "Timer"),
      description = left_of(entry) .. "  ·  Return cancels it", material = entry.kind == "alarm" and "alarm" or "timer",
      tag = entry.kind == "alarm" and "Alarm" or "Timer",
      run = function() timers().cancel(id) rows.bump() return "keep" end,
    }
  end
  return out
end

registry.mode { id = "timer", name = "Timer", material = "timer", shape = "sunny", words = { "timer" },
  hint = "timer 12m pasta  ·  timer 1h 30m", search = function(term)
    local out = {}
    local seconds, label = dates.duration(term)
    if seconds and seconds > 0 then
      label = label or ""
      out[1] = row { id = "timer:new", name = "Timer for " .. dates.span(seconds) .. (label ~= "" and (": " .. label) or ""),
        description = "Rings at " .. morf.time.format("%H:%M", morf.time.now() + seconds) .. "  ·  Return starts it", material = "timer",
        run = function() timers().timer(seconds, label) return "close" end }
    end
    for _, r in ipairs(set_rows()) do out[#out + 1] = r end
    if #out == 0 then out[1] = note("timer", "No timers running", "timer 12m pasta  ·  timer 1:30", "timer") end
    return out
  end }

--- When an alarm phrase rings, and its label: "7am", "tomorrow 7:30 standup".
function M.parse_alarm(text, now)
  now = now or morf.time.now()
  local day = 0
  local rest = text:gsub("^%s+", "")
  local word, after = rest:match("^(%a+)%s+(.+)$")
  if word and word:lower() == "tomorrow" then day, rest = 1, after end
  if word and word:lower() == "today" then rest = after end
  local hour, minute, label = dates.clock(rest)
  if not hour then return nil end
  local today = morf.time.date(now)
  local at = morf.time.time { year = today.year, month = today.month, day = today.day, hour = hour, minute = minute }
  at = morf.time.add(at, { days = day })
  if at <= now then at = morf.time.add(at, { days = 1 }) end
  return at, label or ""
end

registry.mode { id = "alarm", name = "Alarm", material = "alarm", shape = "sunny", words = { "alarm", "wake" },
  hint = "alarm 7am  ·  alarm tomorrow 7:30 standup", search = function(term)
    local out = {}
    local at, label = M.parse_alarm(term)
    if at then
      out[1] = row { id = "alarm:new", name = "Alarm at " .. morf.time.format("%H:%M, %A", at) .. (label ~= "" and (": " .. label) or ""),
        description = dates.relative(at) .. "  ·  Return sets it", material = "alarm",
        run = function() timers().alarm(at, label) return "close" end }
    end
    for _, r in ipairs(set_rows()) do out[#out + 1] = r end
    if #out == 0 then out[1] = note("alarm", "No alarms set", "alarm 7am  ·  alarm tomorrow 7:30 standup", "alarm") end
    return out
  end }

-- ------------------------------------------------------------------ notes --

registry.mode { id = "notes", name = "Notes", material = "edit_note", shape = "pill", words = { "note", "notes", "jot" },
  hint = "note call the bank  ·  one line added to the quick notes", search = function(term)
    local notes = require("notes_model")
    local out = {}
    if term ~= "" then
      out[1] = row { id = "word:note", name = "Note “" .. term .. "”", description = rows.tilde(notes.quick_path()) .. "  ·  Return adds it",
        material = "note_add", run = function() notes.quick(term) return "close" end }
    end
    local lines, shown = notes.quick_lines(), {}
    for i = #lines, 1, -1 do shown[#shown + 1] = { name = lines[i], description = "" } end
    for i, item in ipairs(rows.fuzzy(shown, term)) do
      out[#out + 1] = rows.copy("note:" .. i, item.name, nil, "notes")
      if #out >= 30 then break end
    end
    if #out == 0 then out[1] = note("notes", "No notes yet", "Type one to add it", "edit_note") end
    return out
  end }

-- -------------------------------------------------------------- assistant --

registry.mode { id = "ai", name = "Assistant", material = "auto_awesome", shape = "sunny", words = { "ai" },
  hint = "ai what is a monad  ·  asks the assistant", search = function(term)
    local assistant = require("assistant_model")
    if term == "" then return { note("ai", "Ask the assistant", assistant.summary(), "auto_awesome") } end
    return { row { id = "word:ai", name = term, material = "auto_awesome", description = "Ask the assistant  ·  " .. assistant.summary(),
      run = function() assistant.ask(term) return "close" end } }
  end }

-- ----------------------------------------------------------------- agenda --

registry.mode { id = "agenda", name = "Agenda", material = "calendar_month", shape = "cookie9", words = { "agenda", "today", "calendar" },
  hint = "agenda friday  ·  what is planned", search = function(term)
    loaded()
    local t = dates.parse(term) or morf.time.now()
    local key = morf.time.format("%Y-%m-%d", t)
    local out = {}
    for _, item in ipairs(require("planner").agenda(key)) do
      out[#out + 1] = row { id = "agenda:" .. item.uuid, name = item.description,
        description = item.kind .. (item.time ~= "" and ("  ·  " .. item.time) or ""), material = "event",
        run = open_tasks }
    end
    if #out == 0 then out[1] = note("agenda", "Nothing planned", morf.time.format("%A %-d %B", t), "event_available") end
    return out
  end }

return M
