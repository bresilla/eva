-- What starts with the session: XDG autostart entries and user systemd
-- services. A system entry is turned off the way the specification says, by a
-- copy in the person's own folder marked `Hidden=true`; an entry of the
-- person's is only marked.
local morf = require("morf")
local host = require("lib.services.host")

local M = {}

--- The person's autostart folder.
function M.folder()
  return (morf.env("XDG_CONFIG_HOME") or (morf.fs.home() .. "/.config")) .. "/autostart"
end

--- The system's folders.
function M.system_folders()
  local out = {}
  for dir in (morf.env("XDG_CONFIG_DIRS") or "/etc/xdg"):gmatch("[^:]+") do out[#out + 1] = dir .. "/autostart" end
  return out
end

--- A desktop file's `[Desktop Entry]` keys.
function M.parse_desktop(text)
  local out, inside = {}, false
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local group = line:match("^%[(.-)%]$")
    if group then inside = group == "Desktop Entry"
    elseif inside then
      local key, value = line:match("^([%w%-_]+)%s*=%s*(.*)$")
      if key then out[key] = value end
    end
  end
  return out
end

local function read_folder(folder, rows, own)
  local ok, entries = pcall(morf.fs.list, folder)
  for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
    local name = type(entry) == "table" and entry.name or entry
    if tostring(name):match("%.desktop$") then
      local path = folder .. "/" .. name
      local read, text = pcall(morf.fs.read, path)
      if read then
        local keys = M.parse_desktop(text)
        local row = rows[name] or { key = name, id = name, system = not own }
        row.path = own and path or row.path or path
        row.own = row.own or own
        if own or not rows[name] then
          row.name = keys.Name or row.name or name:gsub("%.desktop$", "")
          row.exec = keys.Exec or row.exec or ""
          row.comment = keys.Comment or row.comment or ""
          row.icon = keys.Icon or row.icon
          row.enabled = keys.Hidden ~= "true" and keys["X-GNOME-Autostart-enabled"] ~= "false"
        end
        rows[name] = row
      end
    end
  end
end

--- Every entry, `{ key, id, name, exec, comment, enabled, own, system, path }`.
function M.entries(user, system)
  local rows = {}
  for _, folder in ipairs(system or M.system_folders()) do read_folder(folder, rows, false) end
  read_folder(user or M.folder(), rows, true)
  local out = {}
  for _, row in pairs(rows) do out[#out + 1] = row end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

--- `text` of a desktop file with `Hidden` set as `hidden`.
function M.with_hidden(text, hidden)
  local lines, placed = {}, false
  for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    if line:match("^Hidden%s*=") then
      if not placed then lines[#lines + 1] = "Hidden=" .. tostring(hidden) placed = true end
    elseif line ~= "" or #lines == 0 then
      lines[#lines + 1] = line
      if not placed and line == "[Desktop Entry]" then lines[#lines + 1] = "Hidden=" .. tostring(hidden) placed = true end
    end
  end
  if not placed then lines[#lines + 1] = "Hidden=" .. tostring(hidden) end
  return table.concat(lines, "\n") .. "\n"
end

--- Turns an entry on or off. `done(ok, why)`.
function M.set_enabled(row, on, done, folder)
  folder = folder or M.folder()
  if host.held("autostart " .. row.id .. " " .. tostring(on)) then return done(true) end
  local ok, text = pcall(morf.fs.read, row.path)
  if not ok then return done(nil, tostring(text)) end
  morf.fs.mkdir(folder)
  local wrote, why = pcall(morf.fs.write, folder .. "/" .. row.id, M.with_hidden(text, not on))
  done(wrote or nil, not wrote and tostring(why) or nil)
end

--- Adds an installed app. `app`: `id` (a desktop id), `name`, `exec`, `icon`.
function M.add(app, done, folder)
  folder = folder or M.folder()
  local name = tostring(app.id or app.name):gsub("[^%w_%.%-]", "-")
  if not name:match("%.desktop$") then name = name .. ".desktop" end
  if host.held("autostart add " .. name) then return done(true) end
  morf.fs.mkdir(folder)
  local lines = { "[Desktop Entry]", "Type=Application", "Name=" .. tostring(app.name or name),
    "Exec=" .. tostring(app.exec or "") }
  if app.icon then lines[#lines + 1] = "Icon=" .. app.icon end
  lines[#lines + 1] = ""
  local text = table.concat(lines, "\n")
  local wrote, why = pcall(morf.fs.write, folder .. "/" .. name, text)
  done(wrote or nil, not wrote and tostring(why) or nil)
end

--- Starts a command of the person's own with the session, as `eva-<name>.desktop`.
--- `done(ok, why)`.
function M.add_command(name, command, done, folder)
  name, command = tostring(name or ""):match("^%s*(.-)%s*$"), tostring(command or ""):match("^%s*(.-)%s*$")
  if name == "" or command == "" then return done(nil, "Give it a name and a command") end
  local slug = name:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  if slug == "" then slug = "command" end
  return M.add({ id = "eva-" .. slug, name = name, exec = command }, done, folder)
end

--- Removes the person's own entry. `done(ok, why)`.
function M.remove(row, done, folder)
  folder = folder or M.folder()
  if host.held("autostart remove " .. row.id) then return done(true) end
  local removed, why = pcall(morf.fs.remove, folder .. "/" .. row.id)
  done(removed or nil, not removed and tostring(why) or nil)
end

-- ----------------------------------------------------------- user services --

--- `systemctl --user list-unit-files`: lines into `{ unit, state }`.
function M.parse_unit_files(text)
  local out = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local unit, state = line:match("^(%S+%.service)%s+(%S+)")
    if unit and not unit:find("@", 1, true) and (state == "enabled" or state == "disabled" or state == "linked") then
      out[#out + 1] = { key = unit, unit = unit, enabled = state ~= "disabled", state = state }
    end
  end
  return out
end

--- `systemctl --user list-units`: a table of `{ active, description }` by unit.
function M.parse_units(text)
  local out = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local unit, active, sub, description = line:match("^%s*(%S+%.service)%s+%S+%s+(%S+)%s+(%S+)%s*(.*)$")
    if unit then out[unit] = { active = active == "active", sub = sub, description = description } end
  end
  return out
end

--- `done(services)`: `{ key, unit, enabled, running, description }`.
function M.services(done)
  host.read({ "systemctl", "--user", "list-unit-files", "--type=service", "--no-legend", "--no-pager" }, function(files)
    local rows = M.parse_unit_files(files)
    host.read({ "systemctl", "--user", "list-units", "--type=service", "--all", "--no-legend", "--no-pager", "--plain" },
      function(units)
        local states = M.parse_units(units)
        for _, row in ipairs(rows) do
          local state = states[row.unit] or {}
          row.running, row.description = state.active == true, state.description or ""
        end
        table.sort(rows, function(a, b) return a.unit < b.unit end)
        done(rows)
      end)
  end)
end

--- Turns a user service on or off, now and from now on.
function M.set_service(unit, on, done)
  if not unit:match("^[%w_%.@%-]+%.service$") then return done(nil, "That is not a service") end
  host.act({ "systemctl", "--user", on and "enable" or "disable", "--now", unit }, done)
end

-- ------------------------------------------------------------------ timers --

-- What each of eva's own alarms is for, by its unit's id.
local function alarms()
  local root = (morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva"
  local ok, list = pcall(function() return morf.json.decode(morf.fs.read(root .. "/clock/alarms.json")) end)
  local out = {}
  if not ok or type(list) ~= "table" then return out end
  local lib = require("lib.services.alarm")
  for _, item in ipairs(list) do out[item.id] = lib.describe(item) end
  return out
end

local function seconds(value)
  if type(value) ~= "number" or value <= 0 then return nil end
  return value / 1000000
end

--- The rows `systemctl --user list-timers --output=json` gives, soonest first:
--- `unit`, `name`, `next`, `last` (in seconds), `service`, `alarm` (what an
--- alarm of eva's says, for its own units).
function M.timer_rows(list)
  local known = alarms()
  local out = {}
  for _, row in ipairs(list) do
    local unit = tostring(row.unit or "")
    local id = unit:match("^eva%-alarm%-(.+)%.timer$")
    out[#out + 1] = { key = unit, unit = unit, name = (unit:gsub("%.timer$", "")), next = seconds(row.next),
      last = seconds(row.last), service = row.activates, alarm = id and (known[id] or "Alarm") or nil }
  end
  table.sort(out, function(a, b) return (a.next or math.huge) < (b.next or math.huge) end)
  return out
end

--- The user's timers, the scheduled jobs: `done(rows)`, or `done(nil, why)`
--- where there is no user session of systemd.
function M.timers(done)
  host.read({ "systemctl", "--user", "list-timers", "--all", "--output=json", "--no-pager" }, function(text)
    local ok, list = pcall(morf.json.decode, text or "")
    if not ok or type(list) ~= "table" then return done(nil, "no user session of systemd") end
    done(M.timer_rows(list))
  end, { timeout_ms = 3000 })
end

--- When a time comes, in a few words.
function M.when(at)
  if not at then return "never" end
  return (morf.time.format("%a %-d %b %H:%M", at))
end

return M
