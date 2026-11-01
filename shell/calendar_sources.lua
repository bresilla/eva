-- The calendars read besides Taskwarrior: `.ics` files, folders of them (what
-- vdirsyncer and khal keep), and ICS addresses, fetched into the cache so the
-- agenda works offline. Nothing is read until something asks. No nodes.
local morf = require("morf")
local config = require("config")
local ical = require("lib.integrations.ical")
local poll = require("lib.util.poll")
local M = {
  revision = morf.signal("eva.calendar.sources.revision", 0),
  sources = morf.list_model({}),
  loading = morf.signal("eva.calendar.sources.loading", false),
  said = morf.signal("eva.calendar.sources.said", ""),
  URL_TIMEOUT_MS = 20000, REFRESH_MS = 30 * 60 * 1000,
}
local parsed, instances, by_day = {}, {}, {}
local window_from, window_to = 0, 0
local job, expansion, url_timer, reload_timer
local watchers = {}
local url_state = {}

local function list(key)
  local value = config.get("calendar." .. key)
  return type(value) == "table" and value or {}
end

local function expand(path) return (morf.fs.expand(tostring(path))) end

-- FNV-1a: a stable file name for an address.
local function hash(text)
  local h = 2166136261
  for i = 1, #text do h = ((h ~ text:byte(i)) * 16777619) & 0xffffffff end
  return ("%08x"):format(h)
end

local function cache_path(url) return morf.paths.cache("calendars/" .. hash(url) .. ".ics") end

--- An address as it is fetched: webcal is https.
function M.fetchable(url) return (tostring(url):gsub("^webcals?://", "https://")) end

--- An address with what may be a secret left out, for showing.
function M.host_of(url) return tostring(url):match("^%a+://([^/]+)") or tostring(url) end

-- -------------------------------------------------------------- discovering --

-- The `path = ...` lines of a khal or vdirsyncer config.
local function configured_paths(file)
  local out = {}
  if not morf.fs.exists(file) then return out end
  local ok, text = pcall(morf.fs.read, file)
  if not ok or type(text) ~= "string" then return out end
  for line in text:gmatch("[^\n]+") do
    local value = line:match("^%s*path%s*=%s*[\"']?([^\"'#]+)[\"']?%s*$")
    if value then out[#out + 1] = (expand(value:match("^(.-)%s*$"):gsub("/%*?$", ""))) end
  end
  return out
end

-- Holds `.ics` files itself, or one folder down.
local function calendar_folders(root, out, seen)
  if not morf.fs.is_dir(root) then return end
  local ok, entries = pcall(morf.fs.list, root, { follow = true })
  if not ok then return end
  local has_files = false
  for _, entry in ipairs(entries) do
    if entry.is_file and entry.name:match("%.ics$") then has_files = true break end
  end
  if has_files then
    if not seen[root] then seen[root] = true out[#out + 1] = root end
    return
  end
  for _, entry in ipairs(entries) do
    if entry.is_dir and not entry.name:match("^%.") and not seen[entry.path] then
      local ok2, inside = pcall(morf.fs.list, entry.path, { follow = true })
      for _, file in ipairs(ok2 and inside or {}) do
        if file.is_file and file.name:match("%.ics$") then
          seen[entry.path] = true
          out[#out + 1] = entry.path
          break
        end
      end
    end
  end
end

-- Where vdirsyncer and khal keep calendars on this machine.
local function discovered()
  local out, seen = {}, {}
  if config.get("calendar.discover") == false then return out end
  local function env(name) local value = morf.env and morf.env(name) return value and value ~= "" and value or nil end
  local home = env("HOME") or morf.fs.home()
  local data, settings = env("XDG_DATA_HOME") or (home .. "/.local/share"), env("XDG_CONFIG_HOME") or (home .. "/.config")
  local roots = { data .. "/khal/calendars", data .. "/vdirsyncer", home .. "/.calendars" }
  for _, file in ipairs { settings .. "/khal/config", settings .. "/vdirsyncer/config" } do
    for _, path in ipairs(configured_paths(file)) do roots[#roots + 1] = path end
  end
  for _, root in ipairs(roots) do calendar_folders(root, out, seen) end
  return out
end

--- Everything to read: `{ id, kind, name, path }`.
function M.gather()
  local out, seen = {}, {}
  local function add(kind, path, name, value)
    if seen[path] then return end
    seen[path] = true
    out[#out + 1] = { id = path, kind = kind, path = path, name = name, value = value }
  end
  for _, file in ipairs(list("files")) do add("file", expand(file), tostring(file):match("([^/]+)$") or file, file) end
  for _, folder in ipairs(list("folders")) do add("folder", expand(folder), tostring(folder):match("([^/]+)/?$") or folder, folder) end
  for _, folder in ipairs(discovered()) do add("found", folder, folder:match("([^/]+)/?$") or folder) end
  for _, url in ipairs(list("urls")) do add("url", cache_path(url), M.host_of(url), url) end
  return out
end

--- Whether any calendar is set up or found.
function M.configured()
  return #list("files") + #list("folders") + #list("urls") > 0 or #discovered() > 0
end

--- A line for the settings.
function M.summary()
  M.revision:get()
  local count = M.sources:len()
  if count == 0 then
    return M.configured() and "Not read yet" or "None connected"
  end
  local events = 0
  for i = 1, count do events = events + (M.sources:get(i).events or 0) end
  return ("%d %s, %d events"):format(count, count == 1 and "calendar" or "calendars", events)
end

-- ------------------------------------------------------------------- loading --

-- Each instance under every local date it touches, stepped by the calendar so
-- a clock change neither repeats a day nor skips one.
local function index()
  by_day = {}
  for _, item in ipairs(instances) do
    local from, to = morf.time.date(item.at), morf.time.date(math.max(item.at, item.ends - 1))
    local first = ical.days_from_civil(from.year, from.month, from.day)
    local last = math.min(ical.days_from_civil(to.year, to.month, to.day), first + 62)
    for day = first, last do
      local key = ("%04d-%02d-%02d"):format(ical.civil_from_days(day))
      by_day[key] = by_day[key] or {}
      local rows = by_day[key]
      rows[#rows + 1] = item
    end
  end
end

local function publish()
  index()
  M.revision:set(M.revision:get() + 1)
end

local function all_events()
  local events = {}
  for _, source in pairs(parsed) do
    for _, event in ipairs(source.events) do events[#events + 1] = event end
  end
  return events
end

-- Instances for the window around `center`, in slices.
local function expand_window()
  if expansion then expansion.cancel() end
  local events = all_events()
  expansion = poll.job(function(spend)
    return ical.occurrences(events, window_from, window_to, spend)
  end, function(found)
    expansion = nil
    instances = found or {}
    publish()
  end)
end

--- Makes sure the days around `at` are known.
function M.want(at)
  if at >= window_from + 86400 * 20 and at <= window_to - 86400 * 20 then return end
  local now = morf.time.now()
  window_from = math.min(at, now) - 86400 * 45
  window_to = math.max(at, now) + 86400 * 75
  if next(parsed) then expand_window() end
end

local function read_source(source, spend)
  local paths = {}
  if source.kind == "file" or source.kind == "url" then paths[1] = source.path
  else
    local ok, entries = pcall(morf.fs.list, source.path, { follow = true })
    for _, entry in ipairs(ok and entries or {}) do
      if entry.is_file and entry.name:match("%.ics$") then paths[#paths + 1] = entry.path end
    end
  end
  local events, name, color, failed = {}, nil, nil, nil
  for _, path in ipairs(paths) do
    spend(10)
    local ok, text = pcall(morf.fs.read, path)
    if ok and type(text) == "string" then
      local fine, calendar = pcall(ical.parse, text, spend)
      if fine then
        name, color = name or calendar.name, color or calendar.color
        for _, event in ipairs(calendar.events) do
          event.calendar, event.calendar_color = source.id, nil
          events[#events + 1] = event
        end
      else
        failed = "It could not be read."
      end
    elseif source.kind ~= "url" then
      failed = "It could not be opened."
    end
  end
  for _, event in ipairs(events) do event.calendar_name = name or source.name end
  return { id = source.id, kind = source.kind, name = name or source.name, events = events, failed = failed,
    value = source.value, color = color }
end

--- Reads every calendar again, in slices.
function M.load()
  if job then job.cancel() end
  local sources = M.gather()
  if #sources == 0 then
    parsed = {}
    instances = {}
    M.sources:replace({}, "id")
    publish()
    return false
  end
  if window_from == 0 then M.want(morf.time.now()) end
  M.loading:set(true)
  job = poll.job(function(spend)
    local out = {}
    for _, source in ipairs(sources) do out[source.id] = read_source(source, spend) end
    return out
  end, function(found)
    job = nil
    M.loading:set(false)
    if not found then return end
    parsed = found
    local rows = {}
    for _, source in ipairs(sources) do
      local read = found[source.id]
      local state = read.failed or (source.kind == "url" and url_state[source.value]) or ""
      rows[#rows + 1] = { id = source.id, kind = source.kind, name = read.name, events = #read.events, state = state, value = source.value or "" }
    end
    M.sources:replace(rows, "id")
    expand_window()
  end)
  return true
end

local function reload_soon()
  if reload_timer then reload_timer:cancel() end
  reload_timer = morf.time.timer(400, function()
    reload_timer = nil
    M.load()
  end, false)
end

--- Fetches every address into the cache; a failed one keeps what it had.
function M.fetch()
  for _, url in ipairs(list("urls")) do
    local address = M.fetchable(url)
    morf.http.get(address, { timeout_ms = M.URL_TIMEOUT_MS, max_bytes = 16 * 1024 * 1024 }, function(response)
      if response and response.ok and type(response.body) == "string" and response.body:find("BEGIN:VCALENDAR", 1, true) then
        morf.fs.write(cache_path(url), response.body, { mode = 384 })
        url_state[url] = ""
      else
        local had = morf.fs.exists(cache_path(url))
        local why = response and (response.error or ("answered " .. tostring(response.status))) or "no answer"
        url_state[url] = (had and "Offline, showing the last copy: " or "Not fetched: ") .. tostring(why)
      end
      reload_soon()
    end)
  end
end

--- Reads and fetches, then follows the folders while `on`.
function M.watch(on)
  for _, watcher in ipairs(watchers) do watcher:close() end
  watchers = {}
  if url_timer then url_timer:cancel() url_timer = nil end
  if not on then return end
  M.load()
  M.fetch()
  url_timer = morf.time.timer(M.REFRESH_MS, M.fetch, true)
  for _, source in ipairs(M.gather()) do
    if source.kind ~= "url" then
      local watcher = morf.fs.watch(source.path, reload_soon)
      if watcher then watchers[#watchers + 1] = watcher end
    end
  end
end

-- ------------------------------------------------------------------- reading --

--- A person's words for an instance's time, in this machine's zone.
function M.when(item)
  if item.all_day then return "All day" end
  local from, to = morf.time.format("%H:%M", item.at), morf.time.format("%H:%M", item.ends)
  return item.ends > item.at and (from .. "–" .. to) or from
end

--- The instances on `day` ("YYYY-MM-DD").
function M.on_day(day)
  M.revision:get()
  return by_day[day] or {}
end

--- How many instances `day` has.
function M.count(day) return #M.on_day(day) end

--- The instances from `from` up to `to`.
function M.between(from, to)
  M.revision:get()
  local out = {}
  for _, item in ipairs(instances) do
    if item.at >= from and item.at < to then out[#out + 1] = item end
  end
  return out
end

--- The next instance with a time, not yet over.
function M.next_event(now)
  M.revision:get()
  for _, item in ipairs(instances) do
    if not item.all_day and item.ends > now then return item end
  end
end

-- ------------------------------------------------------------------- editing --

local function write(key, value)
  config.set("calendar." .. key, value)
  M.watch(true)
end

--- Adds a file or a folder.
function M.add_path(path)
  path = tostring(path or ""):match("^%s*(.-)%s*$")
  if path == "" then return false end
  local real = expand(path)
  local key = morf.fs.is_dir(real) and "folders" or "files"
  if not morf.fs.exists(real) then M.said:set("Nothing is at that path.") return false end
  local out = {}
  for _, item in ipairs(list(key)) do out[#out + 1] = item end
  out[#out + 1] = path
  M.said:set("")
  write(key, out)
  return true
end

--- Adds an ICS address.
function M.add_url(url)
  url = tostring(url or ""):match("^%s*(.-)%s*$")
  if not url:match("^https?://%S+$") and not url:match("^webcals?://%S+$") then
    M.said:set("That does not look like an address.")
    return false
  end
  local out = {}
  for _, item in ipairs(list("urls")) do out[#out + 1] = item end
  out[#out + 1] = url
  M.said:set("")
  write("urls", out)
  return true
end

--- Takes a source out of the settings.
function M.remove(row)
  local key = row.kind == "file" and "files" or row.kind == "folder" and "folders" or row.kind == "url" and "urls"
  if not key then return false end
  local out = {}
  for _, item in ipairs(list(key)) do
    if item ~= row.value then out[#out + 1] = item end
  end
  if row.kind == "url" then pcall(morf.fs.remove, cache_path(row.value)) end
  write(key, out)
  return true
end

return M
