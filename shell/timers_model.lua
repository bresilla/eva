-- Timers and alarms, for whatever sets them. A timer rings after a span, an alarm
-- at an hour. No nodes.
--
-- `M.use` hands them to a backend, and everything here goes through it. Without
-- one this module keeps them itself, in the state folder, and rings with a
-- notification.
--
--   M.use { add = function(entry) end, cancel = function(id) end, list = function() end }
--
-- An entry is `{ id, kind = "timer" | "alarm", label, at, seconds }`; `at` is when
-- it rings, in seconds since the epoch; `seconds` a timer's whole length.
local morf = require("morf")

local M = {}

--- What is set, soonest first.
M.entries = morf.signal("eva.timers.entries", {})
local backend
local running = {}

local function path() return morf.paths.state("eva-timers.json") end

local function save()
  morf.fs.write(path(), morf.json.encode(M.entries:get()), { atomic = true, parents = true, mode = 384 })
end

local function sorted(list)
  table.sort(list, function(a, b) return a.at < b.at end)
  return list
end

local function ring(entry)
  running[entry.id] = nil
  local left = {}
  for _, other in ipairs(M.entries:get()) do
    if other.id ~= entry.id then left[#left + 1] = other end
  end
  M.entries:set(left)
  save()
  local title = entry.kind == "alarm" and "Alarm" or "Timer done"
  local ok, notifs = pcall(require, "notifs")
  if ok and notifs.push then
    notifs.push { app = "Eva", summary = title, body = entry.label, urgency = 2 }
  end
end

local function arm(entry)
  local wait = math.max(1, (entry.at - morf.time.now()) * 1000)
  running[entry.id] = morf.time.timer(wait, function() ring(entry) end, false)
end

local function add(entry)
  entry.id = entry.id or morf.encoding.uuid()
  if backend then backend.add(entry) return entry end
  local list = {}
  for i, other in ipairs(M.entries:get()) do list[i] = other end
  list[#list + 1] = entry
  M.entries:set(sorted(list))
  save()
  arm(entry)
  return entry
end

--- Sets a timer of `seconds`, named `label`.
function M.timer(seconds, label)
  return add { kind = "timer", label = label or "", seconds = seconds, at = morf.time.now() + seconds }
end

--- Sets an alarm for the time `at`, named `label`.
function M.alarm(at, label)
  return add { kind = "alarm", label = label or "", at = at }
end

--- Takes entry `id` back.
function M.cancel(id)
  if backend then backend.cancel(id) return end
  if running[id] then running[id]:cancel() running[id] = nil end
  local left = {}
  for _, other in ipairs(M.entries:get()) do
    if other.id ~= id then left[#left + 1] = other end
  end
  M.entries:set(left)
  save()
end

--- What is set.
function M.list()
  if backend then return backend.list() end
  return M.entries:get()
end

--- Hands timers and alarms to `owner`: `add(entry)`, `cancel(id)`, `list()`.
--- What is set here goes over to it.
function M.use(owner)
  local waiting = M.entries:get()
  for id, timer in pairs(running) do
    timer:cancel()
    running[id] = nil
  end
  backend = owner
  for _, entry in ipairs(waiting) do owner.add(entry) end
  M.entries:set({})
  save()
end

-- What was set before a reload rings on; what came due meanwhile rings now.
do
  local ok, text = pcall(morf.fs.read, path())
  local fine, list = pcall(morf.json.decode, ok and text or "")
  if fine and type(list) == "table" then
    M.entries:set(sorted(list))
    if morf.window.primary and morf.window.primary() then
      for _, entry in ipairs(list) do arm(entry) end
    end
  end
end

return M
