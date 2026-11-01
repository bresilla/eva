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

--- Startup apps and user services.
function M.startup(active)
  local model = page_model.new("startup", active)
  local entries = morf.signal("eva.startup.entries", {})
  local services = morf.signal("eva.startup.services", {})
  local installed = morf.signal("eva.startup.installed", {})
  local fake = require("lib.services.host").fake() and require("lib.services.host_fake")

  local function refresh()
    entries:set(fake and fake.autostart() or autostart.entries())
    autostart.services(function(rows) services:set(rows) end)
  end
  model.on_show(function()
    refresh()
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
  return model
end

return M
