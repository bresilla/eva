-- History grouping, expansion and actions. Themes receive no server access.
local morf = require("morf")
local config = require("config")
local notifs = require("notifs")
local rules = require("notification_rules")
local digest = require("notification_digest")
local M = { notifs = notifs }
local expanded = morf.signal("eva.sidebar.opened", {})
local pages = morf.signal("eva.sidebar.pages", {})
local visual, clearing
M.PAGE = 6

local function key_of(n) return n.key or (n.app ~= "" and n.app) or "Unknown" end

-- A group's shelf: messages above the rest, what never asked for attention
-- below them.
local function shelf(group)
  if group.priority then return 1 end
  if group.conversation then return 2 end
  if group.urgency == 0 then return 4 end
  return 3
end
M.SHELVES = { "Priority", "Conversations", "Notifications", "Silent" }

local grouped_from, grouped
function M.groups()
  local history, groups, by_app = notifs.records(), {}, {}
  if history == grouped_from then return grouped end
  for i = #history, 1, -1 do
    local n = history[i]
    local key = key_of(n)
    local group = by_app[key]
    if not group then
      group = { key = key, app = n.app ~= "" and n.app or "Unknown", items = {}, urgency = 0, unread = 0 }
      by_app[key], groups[#groups + 1] = group, group
    end
    group.items[#group.items + 1] = n
    group.urgency = math.max(group.urgency, n.urgency or 1)
    group.priority = group.priority or n.priority == true
    group.conversation = group.conversation or digest.conversation(n)
  end
  for index, group in ipairs(groups) do group.order, group.shelf = index, shelf(group) end
  table.sort(groups, function(a, b)
    if a.shelf ~= b.shelf then return a.shelf < b.shelf end
    return a.order < b.order
  end)
  grouped_from, grouped = history, groups
  return groups
end
function M.count() return #notifs.records() end
--- How many lines a shut group shows.
function M.preview() return config.get("notifications.history.preview") end
function M.is_open(key)
  local flag = expanded:get()[key]
  if flag == nil then return config.get("notifications.history.open_groups") == true end
  return flag == true
end
function M.toggle(key)
  local next = {}
  for k, on in pairs(expanded:get()) do next[k] = on end
  next[key] = not M.is_open(key)
  expanded:set(next)
end

--- How far down an open group its list starts.
function M.offset(key) return (pages:get()[key] or 0) * M.PAGE end
--- Whether `group` has entries past what its list shows.
function M.has_more(group) return #group.items > M.offset(group.key) + M.PAGE end
function M.has_less(group) return M.offset(group.key) > 0 end
function M.page(key, by)
  local next = {}
  for k, page in pairs(pages:get()) do next[k] = page end
  next[key] = math.max(0, (next[key] or 0) + by)
  pages:set(next)
end

function M.forget(id) notifs.forget(id) end
function M.copy(entry)
  local plain = require("themes.notification_text").plain
  pcall(morf.clipboard.set, plain(entry.body ~= "" and entry.body or entry.summary))
end

--- Whether the entry's sender is still there to hear its buttons.
function M.answers(n) return n ~= nil and notifs.answers:get()[tostring(n.id)] == true end

local function clear_with(ids, label)
  if clearing then return end
  if #ids == 0 then return end
  local delay = visual and visual.animate_clear() or 0
  local function finish()
    clearing = nil
    -- New arrivals during the exit belong to the next batch, not this click.
    notifs.forget_ids(ids, label)
    if visual then visual.reset_clear() end
  end
  if delay > 0 then clearing = morf.time.timer(delay, finish, false) else finish() end
end

function M.clear()
  local ids = {}
  for _, n in ipairs(notifs.history:get()) do
    if not notifs.ongoing(n) then ids[#ids + 1] = n.id end
  end
  clear_with(ids, "Cleared")
end

function M.clear_app(key) notifs.clear_app(key) end
function M.clear_silent() notifs.clear_silent() end

-- ------------------------------------------------------------- the summary --

--- The summary on show, or nil: `conversations`, `apps`, `total`, `at`.
function M.digest() return digest.shown(notifs.records()) end
--- What waits for the next summary: `{ count, next }`, or nil with nothing.
function M.digest_waiting()
  local held = digest.waiting(notifs.records())
  if #held == 0 then return nil end
  local due = digest.next_due(require("focus_model").now())
  return { count = #held, next = due and morf.time.format("%H:%M", due) or nil }
end
function M.digest_now() digest.show_now(notifs.records()) end
function M.digest_done() digest.done() end
--- Clears what the summary holds, as one batch to undo, and puts it away.
function M.digest_clear()
  local shown, ids = M.digest(), {}
  if not shown then return end
  for _, list in ipairs { shown.conversations, shown.apps } do
    for _, row in ipairs(list) do
      for _, item in ipairs(row.items) do ids[#ids + 1] = item.id end
    end
  end
  digest.done()
  clear_with(ids, "Cleared the summary")
end
--- A row of the summary pressed: its sender's own action, or its group opened.
function M.digest_open(row)
  for _, action in ipairs(row.latest.actions or {}) do
    if action.key == "default" and M.answers(row.latest) then
      notifs.invoke(row.id, "default")
      return
    end
  end
  if not M.is_open(row.key) then M.toggle(row.key) end
end
function M.undo() return notifs.undo:get() end
function M.restore() return notifs.restore() end
M.snoozed, M.dismissed = notifs.asleep, notifs.recent

--- Opens the app's rules, in Settings.
function M.rules_of(key)
  local utilities = require("utilities")
  utilities.rules_app:set(key)
  utilities.request("notifications/app")
  require("pages").open("settings")
end
--- Opens the notification settings.
function M.settings()
  require("utilities").request("notifications")
  require("pages").open("settings")
end
function M.mute(key, seconds) rules.mute(key, seconds or 0, require("focus_model").now()) end

M.active = require("presentation").active("sidebar.notifications")
function M.build(width, height)
  visual = require("themes").view("notification_history").build(M, width, height)
  return visual.node, visual.head
end
-- Remember expansion only while that application's history exists.
morf.effect("eva.history.expansion", function()
  local alive, next, changed = {}, {}, false
  for _, n in ipairs(notifs.history:get()) do alive[key_of(n)] = true end
  for key, on in pairs(expanded:get()) do
    if alive[key] then next[key] = on else changed = true end
  end
  if changed then expanded:set(next) end
end)
return M
