-- Per-app notification rules: what the person decided about each sender, and
-- which apps have notified. State and matching only; no nodes.
--
-- A rule is a row of `notifications.rules`: `app` (a sender's key, or "*"),
-- `category` ("" for all of the app), `match` (a Lua pattern over summary and
-- body, "" for none) and any of the FIELDS it overrides. Rules stack from the
-- general to the particular: app, then category, then content.
local morf = require("morf")
local config = require("config")

local M = {}

M.FIELDS = {
  mute = false,        -- no popup, no sound
  mute_until = 0,      -- a timed mute: seconds since the epoch
  popup = true,        -- banner on screen
  urgency = -1,        -- 0, 1, 2, or -1 for the sender's
  history = true,      -- kept in the history
  sound = "default",   -- "default", "off", or a sound name or file
  timeout = -1,        -- ms on screen, 0 until dismissed, -1 for the shell's
  priority = false,    -- rises to the top and passes every Focus mode
  hide = false,        -- content stays hidden until opened
  actions = true,      -- action buttons drawn
  hidden_actions = {}, -- action keys or labels left out
  digest = false,      -- held for the scheduled summary
  announce = false,    -- read aloud
  highlight = false,   -- a stronger card
  ring = false,        -- sounds through a silent ring mode
  run = {},            -- a command to run on arrival
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

--- A sender's key: its desktop entry, else its name.
function M.key(n)
  local entry = n and n.desktop_entry or ""
  if entry ~= "" then return entry end
  local app = n and n.app or ""
  return app ~= "" and app or "Unknown"
end

local function rows() return config.get("notifications.rules") or {} end

local function matches(rule, n, key)
  if rule.app ~= "*" and rule.app ~= key then return false end
  local category = rule.category or ""
  if category ~= "" and category ~= (n.category or "") then return false end
  local pattern = rule.match or ""
  if pattern ~= "" then
    local text = tostring(n.summary or "") .. "\n" .. tostring(n.body or "")
    local ok, found = pcall(string.find, text, pattern)
    if not ok or not found then return false end
  end
  return true
end

local function weight(rule)
  return (rule.app == "*" and 0 or 1) + ((rule.category or "") ~= "" and 2 or 0) + ((rule.match or "") ~= "" and 4 or 0)
end

local function stack(out, rule)
  for field in pairs(M.FIELDS) do
    if rule[field] ~= nil then out[field] = copy(rule[field]) end
  end
end

--- What applies to notification `n`: every field settled.
function M.outcome(n)
  local out, list, key = copy(M.FIELDS), {}, M.key(n)
  for _, rule in ipairs(rows()) do
    if matches(rule, n, key) then list[#list + 1] = rule end
  end
  table.sort(list, function(a, b) return weight(a) < weight(b) end)
  for _, rule in ipairs(list) do stack(out, rule) end
  return out
end

local function exact(app, category)
  category = category or ""
  for index, rule in ipairs(rows()) do
    if rule.app == app and (rule.category or "") == category and (rule.match or "") == "" then return index, rule end
  end
end

--- The rule as the settings show it: `app`'s fields, each settled.
function M.of(app, category)
  local out = copy(M.FIELDS)
  local _, base = exact(app)
  if base then stack(out, base) end
  if category and category ~= "" then
    local _, own = exact(app, category)
    if own then stack(out, own) end
  end
  return out
end

--- Sets one field of `app`'s rule, dropping a rule back at its defaults.
function M.set(app, field, value, category)
  if M.FIELDS[field] == nil then return false, "no rule field " .. tostring(field) end
  local list = copy(rows())
  local index = exact(app, category)
  local rule = index and list[index] or { app = app, category = category or "", match = "" }
  rule[field] = value
  local keeps = false
  for key in pairs(M.FIELDS) do
    if rule[key] ~= nil and morf.json.encode(rule[key]) ~= morf.json.encode(M.FIELDS[key]) then keeps = true end
  end
  if index then
    if keeps then list[index] = rule else table.remove(list, index) end
  elseif keeps then
    list[#list + 1] = rule
  end
  return config.set("notifications.rules", list)
end

--- Whether `app` has a rule that says anything.
function M.custom(app) return exact(app) ~= nil end

--- Every rule of `app` gone.
function M.reset(app)
  local out = {}
  for _, rule in ipairs(rows()) do
    if rule.app ~= app then out[#out + 1] = rule end
  end
  return config.set("notifications.rules", out)
end

--- Mutes `app` for `seconds`, for good with 0.
function M.mute(app, seconds, now)
  M.set(app, "mute_until", seconds > 0 and now + seconds or 0)
  return M.set(app, "mute", seconds == 0)
end
function M.unmute(app)
  M.set(app, "mute_until", 0)
  return M.set(app, "mute", false)
end

--- Whether an outcome silences now.
function M.muted(out, now) return out.mute == true or (out.mute_until or 0) > now end

--- Adds a content rule: a pattern, and what it decides.
function M.add_content(pattern, fields)
  local list = copy(rows())
  local rule = { app = "*", category = "", match = pattern }
  for key, value in pairs(fields or {}) do rule[key] = value end
  list[#list + 1] = rule
  return config.set("notifications.rules", list)
end
function M.content()
  local out = {}
  for index, rule in ipairs(rows()) do
    if (rule.match or "") ~= "" then out[#out + 1] = { index = index, rule = rule } end
  end
  return out
end
function M.remove_at(index)
  local list = copy(rows())
  table.remove(list, index)
  return config.set("notifications.rules", list)
end

-- ------------------------------------------------------------- seen apps --

local CAP = 64

--- The apps that have notified, most recent first:
--- `{ key, name, icon, categories, last }`.
function M.apps() return config.get("notifications.apps") or {} end

--- Remembers that `n` came.
function M.saw(n, now)
  local key, list = M.key(n), copy(M.apps())
  local top = list[1] ~= nil and list[1].key == key
  local row
  for index, candidate in ipairs(list) do
    if candidate.key == key then row = table.remove(list, index) break end
  end
  row = row or { key = key, categories = {} }
  local name, icon = (n.app or "") ~= "" and n.app or key, (n.icon or "") ~= "" and n.icon or row.icon or ""
  local category, fresh = n.category or "", row.name ~= name or row.icon ~= icon
  row.name, row.icon, row.last = name, icon, now
  if category ~= "" then
    local known = false
    for _, value in ipairs(row.categories or {}) do known = known or value == category end
    if not known then
      row.categories[#row.categories + 1] = category
      fresh = true
    end
  end
  if top and not fresh then return end
  table.insert(list, 1, row)
  while #list > CAP do table.remove(list) end
  config.set("notifications.apps", list)
end

--- The name `key` was last seen under.
function M.name(key)
  for _, row in ipairs(M.apps()) do
    if row.key == key then return row.name end
  end
  return key
end

function M.categories(key)
  for _, row in ipairs(M.apps()) do
    if row.key == key then return row.categories or {} end
  end
  return {}
end

return M
