-- The Default apps and Startup apps pages. No nodes.
local morf = require("morf")
local defaults = require("lib.services.default_apps")
local autostart = require("lib.services.autostart")
local page_model = require("page_model")

local M = {}

--- Default apps: each kind with what opens it now and what could.
function M.defaults(active)
  local model = page_model.new("apps", active)
  model.KINDS = defaults.KINDS
  local chosen = morf.signal("eva.apps.chosen", {})
  local apps = morf.signal("eva.apps.candidates", {})
  model.open = morf.signal("eva.apps.open", "")
  local entries

  local function read_one(kind)
    defaults.current(kind, function(id)
      local now = {}
      for name, value in pairs(chosen:get()) do now[name] = value end
      now[kind.id] = id
      chosen:set(now)
    end)
  end
  model.on_show(function()
    entries = defaults.entries()
    local cache, by_kind = defaults.known(), {}
    for _, kind in ipairs(defaults.KINDS) do
      by_kind[kind.id] = defaults.candidates(kind, cache, entries)
      read_one(kind)
    end
    apps:set(by_kind)
  end)

  function model.candidates(kind) return apps:get()[kind.id] or {} end
  function model.managed() return defaults.managed() end
  function model.current(kind)
    local id = chosen:get()[kind.id] or ""
    if id == "" then return "None chosen" end
    for _, row in ipairs(model.candidates(kind)) do if row.id == id then return row.name end end
    return (id:gsub("%.desktop$", ""))
  end
  function model.choose(kind, row)
    return model.action(function(done) defaults.set(kind, row.id, done) return true end, function()
      read_one(kind)
      model.open:set("")
    end)
  end
  function model.toggle(kind) model.open:set(model.open:get() == kind.id and "" or kind.id) end
  return model
end

--- Startup apps, a command of one's own, user services and the scheduled jobs.
function M.startup(active)
  local model = page_model.new("startup", active)
  local entries = morf.signal("eva.startup.entries", {})
  local services = morf.signal("eva.startup.services", {})
  local installed = morf.signal("eva.startup.installed", {})
  local timers = morf.signal("eva.startup.timers", {})
  -- "loading", "ready", or "none" where there is no user session of systemd.
  model.scheduled = morf.signal("eva.startup.scheduled", "loading")
  local fake = require("lib.services.host").fake() and require("lib.services.host_fake")

  local function refresh()
    entries:set(fake and fake.autostart() or autostart.entries())
    autostart.services(function(rows) services:set(rows) end)
  end
  model.on_show(function()
    refresh()
    autostart.timers(function(rows)
      timers:set(rows or {})
      model.scheduled:set(rows and "ready" or "none")
    end)
    local rows = {}
    for id, entry in pairs(defaults.entries()) do
      rows[#rows + 1] = { key = id, id = id, name = entry.name or id, exec = entry.exec, icon = entry.icon, words = id }
    end
    table.sort(rows, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
    installed:set(rows)
  end)

  function model.entries() return entries:get() end
  function model.services() return services:get() end
  function model.installed() return installed:get() end
  function model.set_entry(row, on)
    return model.action(function(done) autostart.set_enabled(row, on, done) return true end, refresh)
  end
  function model.remove_entry(row)
    return model.action(function(done) autostart.remove(row, done) return true end, refresh)
  end
  function model.add(app)
    return model.action(function(done) autostart.add(app, done) return true end, refresh)
  end
  function model.set_service(row, on)
    return model.action(function(done) autostart.set_service(row.unit, on, done) return true end, refresh)
  end
  function model.add_command(name, command)
    return model.action(function(done) autostart.add_command(name, command, done) return true end, refresh)
  end
  function model.timers() return timers:get() end
  model.when = autostart.when
  return model
end

-- --------------------------------------------------------- the command line --

local function line(row)
  return ("%-3s %-24s %s"):format(row.enabled and "on" or "off", (row.id:gsub("%.desktop$", "")), row.name)
end

-- The entry `name` means, by its file or its name.
local function find(name)
  local wanted = tostring(name or ""):lower():gsub("%.desktop$", "")
  for _, row in ipairs(autostart.entries()) do
    if row.id:lower():gsub("%.desktop$", "") == wanted or row.name:lower() == wanted then return row end
  end
end

--- `eva-startup ARGS`: `list`, `enable NAME`, `disable NAME`, `remove NAME` and
--- `timers`. `done(text, why)`.
function M.job(args, done)
  local how = args[1]
  local function act(row, change)
    if not row then return done(nil, "nothing called " .. tostring(args[2])) end
    change(row, function(ok, why)
      if not ok then return done(nil, why) end
      done(line(find(args[2]) or row))
    end)
  end
  if how == "list" then
    local lines = {}
    for _, row in ipairs(autostart.entries()) do lines[#lines + 1] = line(row) end
    done(#lines > 0 and table.concat(lines, "\n") or "nothing starts with the session")
  elseif how == "enable" or how == "disable" then
    act(find(args[2]), function(row, finish) autostart.set_enabled(row, how == "enable", finish) end)
  elseif how == "remove" then
    local row = find(args[2])
    if row and (not row.own or row.system) then return done(nil, row.name .. " belongs to the system: disable it") end
    act(row, function(target, finish)
      autostart.remove(target, function(ok, why) if ok then done("removed") else finish(nil, why) end end)
    end)
  elseif how == "timers" then
    autostart.timers(function(rows, why)
      if not rows then return done(nil, why) end
      local lines = {}
      for _, row in ipairs(rows) do
        lines[#lines + 1] = ("%-20s %s%s"):format(autostart.when(row.next), row.name, row.alarm and (" (" .. row.alarm .. ")") or "")
      end
      done(#lines > 0 and table.concat(lines, "\n") or "no timers")
    end)
  else
    done(nil, "unknown command: " .. tostring(how))
  end
end

return M
