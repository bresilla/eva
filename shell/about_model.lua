-- The About, Updates and Displays pages. Displays reads what
-- lib/shell/displays reads and hands every change to eva-displays; nothing
-- here arranges a monitor.
local morf = require("morf")
local about = require("lib.services.about")
local timedate = require("lib.services.timedate")
local host = require("lib.services.host")
local page_model = require("page_model")

local M = {}

--- Opens a tool of apps/, or says it is not installed.
local function opener(model, tool, name)
  return function()
    if host.open_tool(tool) then return true end
    model.say(name .. " is not installed here", true)
    return false
  end
end

function M.about(active)
  local model = page_model.new("about", active)
  local rows = morf.signal("eva.about.rows", {})
  local hostname = morf.signal("eva.about.hostname", "")
  local extra = { eva = about.eva_version() }

  local function read()
    rows:set(about.facts(extra))
    timedate.hostname(function(reply)
      if type(reply) == "table" then hostname:set(reply.StaticHostname or reply.Hostname or "") end
    end)
  end
  model.on_show(function()
    read()
    about.gpus(function(names) extra.gpus = names read() end)
    local hypr = require("lib.compositor.hyprland")
    if hypr.available() then
      hypr.version(function(info)
        if type(info) == "table" and info.version then extra.compositor = "Hyprland " .. info.version read() end
      end)
    end
  end)

  function model.rows() return rows:get() end
  function model.hostname() return hostname:get() end
  function model.hostname_declared() return timedate.hostname_declared() end
  model.nixos = host.nixos
  function model.copy()
    local ok = pcall(morf.clipboard.set, about.as_text(rows:get()))
    model.say(ok and "Copied" or "Could not reach the clipboard", not ok)
    return ok
  end
  function model.can_info() return host.tool("info") ~= nil end
  model.open_info = opener(model, "info", "eva-info")
  function model.set_hostname(name)
    local valid, why = timedate.valid_hostname(name)
    if not valid then model.say(why, true) return false end
    return model.action(function(done) timedate.set_hostname(name, done) return true end, read)
  end
  return model
end

function M.updates(active)
  local model = page_model.new("updates", active)
  function model.version() return morf.version or "" end
  function model.eva() return about.eva_version() or "" end
  model.nixos = host.nixos
  function model.available() return host.tool("update") ~= nil end
  model.open = opener(model, "update", "eva-update")
  return model
end

--- Displays: the outputs, read-only, and the way to eva-displays.
function M.displays(active)
  local model = page_model.new("displays", active)
  local lib = require("lib.shell.displays")
  local outputs = morf.signal("eva.displays.page", {})
  local fake = host.fake() and require("lib.services.host_fake")

  model.on_show(function()
    if fake then return outputs:set(fake.outputs()) end
    lib.read(function(found) outputs:set(found or {}) end)
  end)
  function model.outputs() return outputs:get() end
  function model.can_open() return host.tool("displays") ~= nil end
  model.open = opener(model, "displays", "eva-displays")
  function model.summary(row)
    if row.enabled == false then return "Off" end
    return ("%d×%d at %.0f Hz · %d%%"):format(row.width or 0, row.height or 0, row.refresh or 0,
      math.floor((row.scale or 1) * 100 + 0.5))
  end
  return model
end

return M
