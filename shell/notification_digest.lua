-- The scheduled summary: what apps set to wait (their rule's `digest`) held in
-- the history until a time in `notifications.digest_times`, then handed over as
-- one notice and a card at the head of the history, conversations first.
--
-- A time slept through is caught on waking, once. A Focus that holds notices
-- back holds this one too, until it ends. What the card shows is read from the
-- history each time, so no message reaches this file's store, and what is
-- dismissed from the history leaves the card.
local morf = require("morf")
local config = require("config")
local focus = require("focus_model")
local M = {}

local shared = morf.shared or morf.signal
-- The card on show: `{ from, to, at }`, the seconds it spans and when it came.
M.card = shared("eva.notifications.digest.card", false)
-- When a summary was last made: what is older than this has had its turn.
M.since = shared("eva.notifications.digest.since", 0)

local loaded = false

local function now() return focus.now() end

local function path()
  local chosen = morf.env and morf.env("EVA_NOTIFICATION_STORE")
  if chosen and chosen ~= "" then return chosen .. ".digest" end
  if morf.capabilities and morf.capabilities.headless then return nil end
  return morf.paths.state("notifications/digest.json")
end

local function save()
  local file = path()
  if file then morf.fs.write(file, morf.json.encode { since = M.since:get(), card = M.card:get() }, { atomic = true, parents = true }) end
end

--- Reads the store, on the screen that keeps the clock. A first start begins
--- counting now, so nothing older is raised at once; a reload finds the shared
--- signals as they were, and a headless run starts from its store alone.
function M.start()
  if loaded then return end
  loaded = true
  local headless = morf.capabilities and morf.capabilities.headless
  if not headless and M.since:get() > 0 then return end
  M.card:set(false)
  local file, stored = path(), nil
  if file and morf.fs.exists(file) then
    local ok, text = pcall(morf.fs.read, file)
    local fine, value = pcall(morf.json.decode, ok and text or "")
    if fine and type(value) == "table" then stored = value end
  end
  M.since:set(stored and tonumber(stored.since) or now())
  if stored and type(stored.card) == "table" then M.card:set(stored.card) end
end

--- The times of `notifications.digest_times` as `{ hour, minute }`, those that
--- read as times.
function M.times()
  local out = {}
  for _, text in ipairs(config.get("notifications.digest_times") or {}) do
    local hour, minute = tostring(text):match("^(%d%d?):(%d%d)$")
    hour, minute = tonumber(hour), tonumber(minute)
    if hour and hour < 24 and minute < 60 then out[#out + 1] = { hour = hour, minute = minute } end
  end
  return out
end

local function today_at(at, time)
  local date = morf.time.date(at)
  return morf.time.time { year = date.year, month = date.month, day = date.day, hour = time.hour, minute = time.minute }
end

--- The last time due at or before `at`, or nil with none set.
function M.last_due(at)
  local best
  for _, time in ipairs(M.times()) do
    local due = today_at(at, time)
    if due > at then due = morf.time.add(due, { days = -1 }) end
    if not best or due > best then best = due end
  end
  return best
end

--- The next time due after `at`, or nil with none set.
function M.next_due(at)
  local best
  for _, time in ipairs(M.times()) do
    local due = today_at(at, time)
    if due <= at then due = morf.time.add(due, { days = 1 }) end
    if not best or due < best then best = due end
  end
  return best
end

--- Whether `n` is someone talking: a messaging category, or a reply field.
function M.conversation(n)
  if tostring(n.category or ""):match("^im") then return true end
  for _, action in ipairs(n.actions or {}) do
    if action.key == "inline-reply" then return true end
  end
  return false
end

-- What the history holds that is waiting from `from` to `to`.
local function held(records, from, to)
  local out = {}
  for _, record in ipairs(records) do
    local at = record.time or 0
    if record.digest and at > from and at <= to then out[#out + 1] = record end
  end
  return out
end

--- What waits for the next summary, oldest first.
function M.waiting(records)
  local card = M.card:get()
  return held(records, card and card.to or M.since:get(), math.huge)
end

local function plural(count, word) return ("%d %s%s"):format(count, word, count == 1 and "" or "s") end

--- The card's rows for `records`, oldest first: `conversations` and `apps`,
--- newest first, each `{ key, title, app, id, latest, items }`, and `total`.
--- `key` is the group its sender has in the history.
function M.gather(records)
  local conversations, apps, by_who, by_app = {}, {}, {}, {}
  for index = #records, 1, -1 do
    local n = records[index]
    local app = n.app ~= "" and n.app or "Unknown"
    local key = n.key or app
    local who = M.conversation(n) and (key .. "\n" .. tostring(n.summary or ""))
    local list, seen, name = apps, by_app, key
    if who then list, seen, name = conversations, by_who, who end
    local row = seen[name]
    if not row then
      row = { key = key, app = app, title = who and tostring(n.summary or app) or app, id = n.id, latest = n, items = {} }
      seen[name] = row
      list[#list + 1] = row
    end
    row.items[#row.items + 1] = n
  end
  return { total = #records, conversations = conversations, apps = apps }
end

--- The notice a summary comes with, or nil with nothing new in it.
function M.notice(records)
  if #records == 0 then return nil end
  local found, parts = M.gather(records), {}
  if #found.conversations > 0 then parts[1] = plural(#found.conversations, "conversation") end
  for _, row in ipairs(found.apps) do parts[#parts + 1] = row.app end
  return { summary = ("%d notification%s for you"):format(#records, #records == 1 and "" or "s"),
    body = table.concat(parts, " · ") }
end

-- The card from what waits. Anything an unfinished card held stays in it.
local function make(records, at)
  local card = M.card:get()
  local from = card and card.from or M.since:get()
  local hold = held(records, from, at)
  M.since:set(at)
  if #hold > 0 then M.card:set { from = from, to = at, at = at } end
  save()
  return hold
end

--- Run on the clock: makes the summary a due time calls for, once. Raises its
--- notice through `push` with what `read` has not covered. True when one came.
function M.tick(records, read, push)
  local at = now()
  local due = M.last_due(at)
  if not due or due <= M.since:get() or focus.quiet() then return false end
  local fresh = {}
  for _, record in ipairs(make(records, at)) do
    if (record.time or 0) > read then fresh[#fresh + 1] = record end
  end
  local notice = M.notice(fresh)
  if not notice then return false end
  push { app = "Eva", summary = notice.summary, body = notice.body, icon = "notifications", transient = true, category = "eva.digest",
    actions = { { key = "open", label = "Open" } }, on_action = function()
      if package.loaded.sidebar then require("pages").open("notifications") end
    end }
  return true
end

--- The summary now, ahead of its time.
function M.show_now(records) make(records, now()) end

--- Puts the card away; what it held stays in the history.
function M.done()
  M.card:set(false)
  save()
end

local read_records, read_card, read_rows

--- What the card shows: `gather`'s rows and `at`, or nil with nothing left in
--- it. One table until the history or the card changes.
function M.shown(records)
  local card = M.card:get()
  if not card then return nil end
  if records ~= read_records or card ~= read_card then
    read_records, read_card = records, card
    read_rows = M.gather(held(records, card.from, card.to))
    read_rows.at = card.at
  end
  return read_rows.total > 0 and read_rows or nil
end

return M
