-- What the lock may say of the notifications, one level at a time:
--
--   all       app, summary and body, cut short
--   senders   which apps, and how many from each
--   count     how many, and nothing else
--   none      nothing, not even that there are any
--
-- `project` is the whole of the filter. The shell runs it before anything
-- leaves its process, and the reader drops what was written under a looser
-- level than its own. A per-app rule can only make an app quieter than the level.
--
-- Text is plain and short. No icon a sender names is loaded on the lock.
local morf = require("morf")
local M = { SUMMARY = 80, BODY = 160, ITEMS = 12, STRICT = { all = 1, senders = 2, count = 3, none = 4 } }

-- `notifications.lock_previews`, the Notifications page's name for each level.
local PREVIEWS = { all = "all", app = "senders", count = "count", none = "none" }
local TO_PREVIEWS = { all = "all", senders = "app", count = "count", none = "none" }

--- The level, from the Notifications page's setting where there is one, else
--- the lock's own.
function M.level_of(previews, own)
  if previews ~= nil then return PREVIEWS[previews] or "none" end
  return own
end

--- The Notifications page's name for `level`.
function M.preview_of(level) return TO_PREVIEWS[level] or "none" end

local function plain(value, limit)
  local text = tostring(value or ""):gsub("<[^>]->", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")
  text = text:gsub("[%c]+", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
  if utf8.len(text) and utf8.len(text) > limit then
    text = text:sub(1, utf8.offset(text, limit + 1) - 1) .. "…"
  elseif not utf8.len(text) then
    text = ""
  end
  return text
end

local function stricter(a, b)
  if (M.STRICT[b] or 0) > (M.STRICT[a] or 4) then return b end
  return M.STRICT[a] and a or "none"
end

--- What `entries` (newest last) come to at `level`. `rules(app)` is an app's
--- own level or nil; `options.since` drops what is older, `options.silent`
--- keeps low urgency.
function M.project(entries, level, rules, options)
  options = options or {}
  level = M.STRICT[level] and level or "none"
  local out = { v = 1, level = level, count = 0, items = {} }
  if level == "none" then return out end
  local by_app, order = {}, {}
  for index = #entries, 1, -1 do
    local entry = entries[index]
    local app = plain(entry.app ~= "" and entry.app or "Unknown", 40)
    local own = stricter(level, rules and rules(entry.app or "") or level)
    local keep = own ~= "none"
      and (options.silent or (entry.urgency or 1) > 0)
      and (not options.since or (entry.time or 0) >= options.since)
    if keep then
      out.count = out.count + 1
      if own == "all" and level == "all" and #out.items < M.ITEMS then
        out.items[#out.items + 1] = { app = app, summary = plain(entry.summary, M.SUMMARY),
          body = plain(entry.body, M.BODY), time = entry.time or 0 }
      elseif own ~= "count" and level ~= "count" and own ~= "all" then
        local group = by_app[app]
        if not group then
          group = { app = app, count = 0, time = entry.time or 0 }
          by_app[app] = group
          order[#order + 1] = group
        end
        group.count = group.count + 1
      end
    end
  end
  for _, group in ipairs(order) do
    if #out.items < M.ITEMS then out.items[#out.items + 1] = group end
  end
  return out
end

--- The file the shell leaves for the lock.
function M.path()
  local run = morf.env("XDG_RUNTIME_DIR")
  if not run or run == "" then return nil end
  return run .. "/eva/lock-view.json"
end

local function read_file()
  local path = M.path()
  if not path then return {} end
  local ok, text = pcall(morf.fs.read, path)
  if not ok or type(text) ~= "string" then return {} end
  local fine, value = pcall(morf.json.decode, text)
  return fine and type(value) == "table" and value or {}
end

--- The lock's reader: `prefs` are its settings. `items()` and `count()` are
--- tracked, and hold what the level allows.
function M.reader(prefs)
  local view = morf.signal("lock.view", read_file())
  local level = prefs.notifications.level
  local started = morf.time.now()
  local self = { watch = nil }
  if M.path() and level ~= "none" then
    pcall(morf.fs.mkdir, M.path():match("^(.*)/"), { parents = true })
    local ok, watch = pcall(morf.fs.watch, M.path(), function() view:set(read_file()) end)
    if ok then self.watch = watch end
  end
  local function current()
    local value = view:get()
    local got = value.notifications
    if type(got) ~= "table" or level == "none" then return { level = "none", count = 0, items = {} } end
    -- What was written under a looser level is not shown under this one.
    if (M.STRICT[got.level] or 0) < M.STRICT[level] then
      return { level = "none", count = 0, items = {} }
    end
    return got
  end
  function self.level() return current().level end
  function self.count() return tonumber(current().count) or 0 end
  function self.items()
    local items = current().items
    return type(items) == "table" and items or {}
  end
  --- What the shell says of the session's quiet modes.
  function self.mode()
    local mode = view:get().mode
    return type(mode) == "table" and mode or {}
  end
  function self.started() return started end
  return self
end

return M
