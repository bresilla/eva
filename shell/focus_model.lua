-- Focus: named modes, what each lets through, and when each comes on by itself.
-- State only; the page is themes/layouts/views/focus_page.lua. Do not disturb
-- is the mode "dnd"; `notifs.dnd` follows it.
--
-- A mode, a row of `focus.modes`: `id`, `name`, `icon`;
--   allow     urgency (0..3, the lowest that passes), apps, people, calls, alarms
--   schedule  on, days (1 Monday..7 Sunday), from, to ("HH:MM"), charging, paused
--   triggers  apps (window classes), display (an output name, "any" for a second
--             screen), gamepad
--   effects   night, dark, saver, awake (booleans), ring ("" or a ring mode)
--   hide_badges, on_enter, on_exit (commands)
local morf = require("morf")
local config = require("config")

local M = {}

M.MAX = 10
M.ICONS = { "do_not_disturb_on", "work", "person", "bedtime", "sports_esports", "menu_book", "fitness_center",
  "directions_car", "self_improvement", "movie" }
-- The lengths a session can be asked for: seconds, 0 until turned off, -1 until
-- the next morning.
M.DURATIONS = { { 0, "Until off" }, { 1800, "30 min" }, { 3600, "1 hour" }, { 7200, "2 hours" }, { -1, "Until 8:00" } }
M.URGENCY = { { 0, "Everything" }, { 1, "Normal up" }, { 2, "Critical" }, { 3, "Nothing" } }
M.DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local REPEAT_CALL = 900

-- The clock; a spec sets it, as morf.time.now does not follow test.advance.
M.now = function() return morf.time.now() end
local shared = morf.shared or morf.signal
-- The machine's reason to stay quiet: "", "sharing" or "fullscreen", set by
-- focus_triggers.lua.
M.auto = shared("eva.focus.auto", "")
-- How many clients hold the D-Bus Inhibit.
M.inhibited = shared("eva.focus.inhibited", 0)
-- Runs after a timed session ended: `on_ended(mode)`; notifs.lua sets it.
M.on_ended = function() end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

-- The modes, one table until they change: `config.get` copies, and a page reads
-- them from every binding. Another screen's writes arrive through the file.
local modes_now, modes_at = config.get("focus.modes") or {}, morf.signal("eva.focus.revision", 0)
local function store(modes)
  modes_now = modes
  config.set("focus.modes", modes)
  modes_at:set(modes_at:get() + 1)
end
morf.effect("eva.focus.modes", function()
  local filed = config.get("focus.modes") or {}
  if morf.json.encode(filed) == morf.json.encode(modes_now) then return end
  modes_now = filed
  modes_at:set(modes_at:get() + 1)
end)

--- Every mode, in order. A tracked read.
function M.modes()
  modes_at:get()
  return modes_now
end

--- The mode `id`, or nil.
function M.mode(id)
  for _, mode in ipairs(M.modes()) do
    if mode.id == id then return mode end
  end
end

--- The mode on now, or nil.
function M.active() local id = config.get("focus.active") return id ~= "" and M.mode(id) or nil end
function M.active_id() return config.get("focus.active") end
--- When a timed session ends, 0 for none.
function M.ends() return config.get("focus.ends") end
--- What turned it on: "manual", "schedule", "trigger".
function M.source() return config.get("focus.source") end

--- Why quiet now: a mode's name, the automatic reason, or nil.
function M.reason()
  local mode = M.active()
  if mode then return mode.name end
  local auto = M.auto:get()
  if auto == "sharing" then return "Sharing the screen" end
  if auto == "fullscreen" then return "Fullscreen" end
  if M.inhibited:get() > 0 then return "An app asked for quiet" end
end

--- Whether anything silences notifications.
function M.quiet() return M.reason() ~= nil end

local function next_morning(now)
  local stamp = morf.time.format("%H:%M", now)
  local hour, minute = stamp:match("(%d+):(%d+)")
  local seconds = tonumber(hour) * 3600 + tonumber(minute) * 60
  local left = 8 * 3600 - seconds
  if left <= 0 then left = left + 86400 end
  return now + left
end

--- The moment a session of `seconds` ends (see DURATIONS), 0 for never.
function M.deadline(seconds, now)
  now = now or M.now()
  if seconds == -1 then return next_morning(now) end
  if (seconds or 0) <= 0 then return 0 end
  return now + seconds
end

--- Turns mode `id` on. `opts`: `seconds`, `source`.
function M.start(id, opts)
  opts = opts or {}
  if not M.mode(id) then return false, "no mode " .. tostring(id) end
  config.set("focus.active", id)
  config.set("focus.ends", M.deadline(opts.seconds))
  config.set("focus.source", opts.source or "manual")
  if (opts.source or "manual") == "manual" then config.set("focus.last", id) end
  return true
end

local function day_of(now) return tonumber(morf.time.format("%u", now)) end
local function hm(now) return morf.time.format("%H:%M", now) end
local function has(list, value)
  for _, candidate in ipairs(list or {}) do if candidate == value then return true end end
  return false
end

--- The window key of `schedule` at `now`, or nil outside it: the date it opened.
function M.window(schedule, now)
  local from, to, at, day = schedule.from, schedule.to, hm(now), day_of(now)
  local date = morf.time.format("%Y-%m-%d", now)
  if from == to then return nil end
  if from < to then
    if has(schedule.days, day) and at >= from and at < to then return date end
    return nil
  end
  if has(schedule.days, day) and at >= from then return date end
  local yesterday = day == 1 and 7 or day - 1
  if has(schedule.days, yesterday) and at < to then
    return morf.time.format("%Y-%m-%d", now - 86400)
  end
end

local function skip_key(id, window) return id .. "@" .. window end
local function skipped(id, window) return has(config.get("focus.skip"), skip_key(id, window)) end

--- Turns the mode off. A scheduled mode stays off until its window closes.
function M.stop()
  local id, now = M.active_id(), M.now()
  local mode = id ~= "" and M.mode(id) or nil
  if mode and (mode.schedule or {}).on then
    local window = M.window(mode.schedule, now)
    if window then
      local skip = copy(config.get("focus.skip") or {})
      skip[#skip + 1] = skip_key(id, window)
      config.set("focus.skip", skip)
    end
  end
  config.set("focus.active", "")
  config.set("focus.ends", 0)
  config.set("focus.source", "")
  return true
end

--- The active mode off, or the one last chosen on.
function M.toggle(seconds)
  if M.active_id() ~= "" then return M.stop() end
  return M.start(config.get("focus.last"), { seconds = seconds or config.get("focus.duration") })
end

--- Changes `field` ("name", "schedule.on", ...) of mode `id`.
function M.set(id, field, value)
  local modes, changed = copy(M.modes()), false
  for _, mode in ipairs(modes) do
    if mode.id == id then
      local node, last = mode, nil
      for part in field:gmatch("[^.]+") do
        if last then
          if type(node[last]) ~= "table" then node[last] = {} end
          node = node[last]
        end
        last = part
      end
      node[last] = value
      changed = true
    end
  end
  if changed then store(modes) end
  return changed
end

--- `value` in or out of the list `field` of mode `id`.
function M.flip(id, field, value)
  local mode = M.mode(id)
  if not mode then return false end
  local node = mode
  for part in field:gmatch("[^.]+") do node = type(node) == "table" and node[part] or nil end
  local out, found = {}, false
  for _, candidate in ipairs(node or {}) do
    if candidate == value then found = true else out[#out + 1] = candidate end
  end
  if not found then out[#out + 1] = value end
  if field:match("days$") then table.sort(out) end
  return M.set(id, field, out)
end

local function blank(id, name)
  return { id = id, name = name, icon = "self_improvement",
    allow = { urgency = 2, apps = {}, people = {}, calls = false, alarms = true },
    schedule = { on = false, days = { 1, 2, 3, 4, 5 }, from = "09:00", to = "17:00", charging = false, paused = false },
    triggers = { apps = {}, display = "", gamepad = false },
    effects = { night = false, dark = false, saver = false, awake = false, ring = "" },
    hide_badges = false, on_enter = {}, on_exit = {} }
end

--- A new mode; its id, or nil and why.
function M.add(name)
  local modes = copy(M.modes())
  if #modes >= M.MAX then return nil, "ten modes at most" end
  local stem = tostring(name or "Custom"):lower():gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", "")
  if stem == "" then stem = "custom" end
  local id, n = stem, 1
  while M.mode(id) do n = n + 1 id = stem .. "-" .. n end
  modes[#modes + 1] = blank(id, name or "Custom")
  store(modes)
  return id
end

--- Removes mode `id`; Do not disturb stays.
function M.remove(id)
  if id == "dnd" then return false, "Do not disturb cannot be removed" end
  if M.active_id() == id then M.stop() end
  local modes = {}
  for _, mode in ipairs(M.modes()) do
    if mode.id ~= id then modes[#modes + 1] = mode end
  end
  store(modes)
  return true
end

-- ------------------------------------------------------------- the filter --

local calls = {}

--- Whether notification `n`, with its rule outcome `out`, comes through.
function M.allows(n, out)
  if not M.quiet() then return true end
  if out and out.priority then return true end
  local mode, urgency = M.active(), n.urgency or 1
  local allow = mode and mode.allow or { urgency = 2, alarms = true }
  if urgency >= (allow.urgency or 2) then return true end
  if has(allow.apps, require("notification_rules").key(n)) then return true end
  local category = n.category or ""
  if allow.alarms ~= false and category:match("alarm") then return true end
  if category:match("^call") then
    local key, now = tostring(n.summary or ""), M.now()
    local was = calls[key]
    calls[key] = now
    if allow.calls or (was and now - was <= REPEAT_CALL) then return true end
  end
  local who = tostring(n.summary or ""):lower()
  for _, name in ipairs(allow.people or {}) do
    if name ~= "" and who:find(name:lower(), 1, true) then return true end
  end
  return false
end

--- Whether badges stay hidden.
function M.hides_badges()
  local mode = M.active()
  return mode ~= nil and mode.hide_badges == true
end

--- A line for the tile and the page.
function M.status()
  local mode = M.active()
  if not mode then
    local reason = M.reason()
    return reason or "Off"
  end
  local ends = M.ends()
  if ends > 0 then return mode.name .. " · until " .. morf.time.format("%H:%M", ends) end
  return mode.name
end

--- What a schedule says in a line.
function M.schedule_text(mode)
  local s = mode.schedule or {}
  if not s.on then return "Off" end
  if s.paused then return "Paused" end
  local names = {}
  for _, day in ipairs(s.days or {}) do names[#names + 1] = M.DAYS[day] end
  local days = #names == 7 and "Every day" or table.concat(names, " ")
  return days .. " · " .. s.from .. "–" .. s.to
end

-- ---------------------------------------------------------------- the tick --

local function triggered(mode, seen)
  local t = mode.triggers or {}
  for _, class in ipairs(t.apps or {}) do
    if seen.apps[class:lower()] then return true end
  end
  if t.gamepad and seen.gamepad then return true end
  local display = t.display or ""
  if display == "any" and seen.screens > 1 then return true end
  if display ~= "" and display ~= "any" and seen.outputs[display] then return true end
  return false
end

--- Settles which mode is on at `now`. `seen`: what the triggers read.
function M.tick(seen)
  local now, id = M.now(), M.active_id()
  seen = seen or { apps = {}, screens = 1, outputs = {}, charging = false, gamepad = false }
  local ends = M.ends()
  if id ~= "" and ends > 0 and now >= ends then
    local mode = M.mode(id)
    config.set("focus.active", "")
    config.set("focus.ends", 0)
    config.set("focus.source", "")
    id = ""
    if mode then M.on_ended(mode) end
  end
  if id ~= "" and M.source() ~= "manual" then
    local mode = M.mode(id)
    local schedule = mode and mode.schedule or {}
    local inside = schedule.on and not schedule.paused and M.window(schedule, now) ~= nil
      and (not schedule.charging or seen.charging)
    if not mode or not (inside or triggered(mode, seen)) then
      config.set("focus.active", "")
      config.set("focus.source", "")
      id = ""
    end
  end
  if id ~= "" then return end
  for _, mode in ipairs(M.modes()) do
    local schedule = mode.schedule or {}
    if schedule.on and not schedule.paused and (not schedule.charging or seen.charging) then
      local window = M.window(schedule, now)
      if window and not skipped(mode.id, window) then
        M.start(mode.id, { source = "schedule" })
        return
      end
    end
    if triggered(mode, seen) then
      M.start(mode.id, { source = "trigger" })
      return
    end
  end
end

return M
