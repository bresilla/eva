-- eva-startup: the session's autostart entries and the user's timers. A system
-- entry is never written: it is switched off by a file of the same name in the
-- user's folder with `Hidden=true`, as the XDG autostart spec has it. No nodes.
local morf = require("morf")
local sys = require("common.sys")
local desktop = require("lib.util.desktop")

local M = {
  rows = morf.signal("startup.rows", {}),
  tab = morf.signal("startup.tab", 1),
  query = morf.signal("startup.query", ""),
  command_name = morf.signal("startup.command_name", ""),
  command = morf.signal("startup.command", ""),
  message = morf.signal("startup.message", ""),
  timers = morf.signal("startup.timers", {}),
  scheduled = morf.signal("startup.scheduled", "loading"),
}

M.TABS = { "apps", "add", "scheduled" }

local HIDDEN, GNOME = "Hidden", "X-GNOME-Autostart-enabled"

--- The folder a person's own entries live in.
function M.user_dir()
  return (morf.env("XDG_CONFIG_HOME") or (morf.fs.home() .. "/.config")) .. "/autostart"
end

local function system_dirs()
  local out = {}
  for dir in (morf.env("XDG_CONFIG_DIRS") or "/etc/xdg"):gmatch("[^:]+") do out[#out + 1] = dir .. "/autostart" end
  return out
end

local function entries_in(dir)
  local out = {}
  for _, entry in ipairs(morf.fs.list(dir) or {}) do
    if entry.name:match("%.desktop$") then out[#out + 1] = entry.name end
  end
  return out
end

local function enabled(keys)
  return keys[HIDDEN] ~= "true" and keys[GNOME] ~= "false"
end

-- The first system file called `id`.
local function system_file(id)
  for _, dir in ipairs(system_dirs()) do
    local path = dir .. "/" .. id
    if morf.fs.exists(path) then return path end
  end
end

--- Every entry, a user's file over a system's of the same name: `id`, `name`,
--- `comment`, `exec`, `icon`, `path`, `origin` ("user" or "system"), `over` (the
--- system file it stands in front of), `enabled`.
function M.read()
  local rows, seen = {}, {}
  local function take(dir, origin)
    for _, id in ipairs(entries_in(dir)) do
      if not seen[id] then
        seen[id] = true
        local path = dir .. "/" .. id
        local keys = desktop.parse(morf.fs.read(path))
        local over = origin == "user" and system_file(id) or nil
        local base = over and desktop.parse(morf.fs.read(over)) or {}
        rows[#rows + 1] = { id = id, name = keys.Name or base.Name or id:gsub("%.desktop$", ""),
          comment = keys.Comment or base.Comment or "", exec = keys.Exec or base.Exec or "",
          icon = keys.Icon or base.Icon or "", path = path, origin = origin, over = over, enabled = enabled(keys) }
      end
    end
  end
  take(M.user_dir(), "user")
  for _, dir in ipairs(system_dirs()) do take(dir, "system") end
  table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
  return rows
end

function M.refresh() M.rows:set(M.read()) end

-- Writes into the user's folder, or says what a dry run held back.
local function write(path, text)
  if sys.dry() then
    morf.log("info", "eva: write " .. path .. " (dry run)")
    return true
  end
  return morf.fs.write(path, text, { atomic = true, parents = true, mode = 420 })
end

local function drop(path)
  if sys.dry() then
    morf.log("info", "eva: remove " .. path .. " (dry run)")
    return true
  end
  return morf.fs.remove(path)
end

local function user_path(id) return M.user_dir() .. "/" .. id end

--- Starts the entry with the session.
function M.enable(row)
  if row.origin == "system" then
    write(user_path(row.id), desktop.set(morf.fs.read(row.path), HIDDEN, "false"))
  else
    local text = morf.fs.read(row.path)
    if row.over and text == desktop.set(morf.fs.read(row.over), HIDDEN, "true") then
      drop(row.path)
    else
      write(row.path, desktop.set(desktop.set(text, HIDDEN, nil), GNOME, nil))
    end
  end
  M.refresh()
end

--- Leaves the entry out of the session.
function M.disable(row)
  local origin = row.origin == "system" and user_path(row.id) or row.path
  write(origin, desktop.set(morf.fs.read(row.path), HIDDEN, "true"))
  M.refresh()
end

--- Takes a person's own entry away; a system entry can only be switched off.
function M.remove(row)
  if row.origin ~= "user" or row.over then return false end
  drop(row.path)
  M.refresh()
  return true
end

--- Whether the entry is one a person can delete.
function M.removable(row) return row.origin == "user" and row.over == nil end

--- The entry `name` means, by its file or its name.
function M.find(name)
  local wanted = tostring(name or ""):lower():gsub("%.desktop$", "")
  for _, row in ipairs(M.read()) do
    if row.id:lower():gsub("%.desktop$", "") == wanted or row.name:lower() == wanted then return row end
  end
end

-- ------------------------------------------------------------------- adding --

local function apps() return require("apps").installed() end

--- The installed applications matching the search, by name. A tracked read.
function M.matches()
  local query = M.query:get():match("^%s*(.-)%s*$")
  local list = apps()
  if query == "" then return list end
  local out = {}
  for _, hit in ipairs(morf.text.fuzzy(query, list, { key = "name" })) do out[#out + 1] = hit.item end
  return out
end

local function file_id(id) return id:match("%.desktop$") and id or (id .. ".desktop") end

--- Starts an installed application with the session: a copy of its entry.
function M.add(app)
  local id = file_id(app.id)
  if morf.fs.exists(user_path(id)) then
    M.message:set(app.name .. " is already there")
    return false
  end
  local text = morf.fs.read((app.folder or "") .. "/" .. id)
  if not text then
    M.message:set("Cannot read the entry of " .. app.name)
    return false
  end
  write(user_path(id), desktop.set(text, HIDDEN, nil))
  M.message:set(app.name .. " starts with the session")
  M.refresh()
  return true
end

--- Starts a command with the session.
function M.add_command(name, command)
  name, command = tostring(name or ""):match("^%s*(.-)%s*$"), tostring(command or ""):match("^%s*(.-)%s*$")
  if name == "" or command == "" then
    M.message:set("Give it a name and a command")
    return false
  end
  local slug = name:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  if slug == "" then slug = "command" end
  local id = "eva-" .. slug .. ".desktop"
  local text = desktop.set(desktop.set(desktop.set("", "Type", "Application"), "Name", name), "Exec", command)
  write(user_path(id), text)
  M.command_name:set("")
  M.command:set("")
  M.message:set(name .. " starts with the session")
  M.refresh()
  return true
end

function M.select(name)
  for index, key in ipairs(M.TABS) do
    if key == name then M.tab:set(index) return true end
  end
  return false
end

-- -------------------------------------------------------------------- timers --

-- What each of eva's own alarms is for, by its unit's id.
local function alarms()
  local lib = require("lib.services.alarm")
  local out = {}
  for _, item in ipairs(sys.load(sys.state("clock", "alarms.json"), {})) do out[item.id] = lib.describe(item) end
  return out
end

local function seconds(value)
  if type(value) ~= "number" or value <= 0 then return nil end
  return value / 1000000
end

--- The rows `systemctl --user list-timers --output=json` gives, soonest first:
--- `unit`, `name`, `next`, `last`, `service`, `alarm` (what an alarm of eva's
--- says, for its own units).
function M.timer_rows(list)
  local known = alarms()
  local out = {}
  for _, row in ipairs(list) do
    local unit = tostring(row.unit or "")
    local id = unit:match("^eva%-alarm%-(.+)%.timer$")
    out[#out + 1] = { unit = unit, name = unit:gsub("%.timer$", ""), next = seconds(row.next), last = seconds(row.last),
      service = row.activates, alarm = id and (known[id] or "Alarm") or nil }
  end
  table.sort(out, function(a, b) return (a.next or math.huge) < (b.next or math.huge) end)
  return out
end

--- Reads the timers: `done(rows)`, or nil where there is no user session.
function M.load_timers(done)
  local function finish(list)
    local rows = list and M.timer_rows(list) or nil
    M.timers:set(rows or {})
    M.scheduled:set(rows and "ready" or "none")
    if done then done(rows) end
  end
  if morf.env("EVA_FAKE_STARTUP") == "1" then
    finish(require("fake").timers(morf.time.now()))
    return
  end
  sys.run({ "systemctl", "--user", "list-timers", "--all", "--output=json", "--no-pager" },
    { read = true, timeout_ms = 3000 }, function(result)
      local ok, list = pcall(morf.json.decode, result.stdout or "")
      finish(result.ok and ok and type(list) == "table" and list or nil)
    end)
end

--- When a time comes, in a few words.
function M.when(at)
  if not at then return "never" end
  return (morf.time.format("%a %-d %b %H:%M", at))
end

-- --------------------------------------------------------- the command line --

local function line(row)
  return ("%-3s %-24s %s"):format(row.enabled and "on" or "off", (row.id:gsub("%.desktop$", "")), row.name)
end

local function by_name(name, done, act)
  local row = M.find(name)
  if not row then done(nil, "nothing called " .. tostring(name)) return end
  act(row)
  done(line(M.find(name)))
end

--- `done(text, why)` with the answer to `args`.
function M.job(args, done)
  local how = args[1]
  if how == "list" then
    local lines = {}
    for _, row in ipairs(M.read()) do lines[#lines + 1] = line(row) end
    done(#lines > 0 and table.concat(lines, "\n") or "nothing starts with the session")
  elseif how == "enable" then by_name(args[2], done, M.enable)
  elseif how == "disable" then by_name(args[2], done, M.disable)
  elseif how == "remove" then
    local row = M.find(args[2])
    if not row then done(nil, "nothing called " .. tostring(args[2])) return end
    if not M.removable(row) then done(nil, row.name .. " belongs to the system: disable it") return end
    M.remove(row)
    done("removed")
  elseif how == "timers" then
    M.load_timers(function(rows)
      if not rows then done(nil, "no user session of systemd") return end
      local lines = {}
      for _, row in ipairs(rows) do
        lines[#lines + 1] = ("%-20s %s%s"):format(M.when(row.next), row.name, row.alarm and (" (" .. row.alarm .. ")") or "")
      end
      done(#lines > 0 and table.concat(lines, "\n") or "no timers")
    end)
  else
    done(nil, "unknown command: " .. tostring(how))
  end
end

return M
