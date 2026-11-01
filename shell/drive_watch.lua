-- Drives as they arrive, and disks as they fill: a popup for the one, a
-- notification for the other, each once until things change.
local morf = require("morf")
local config = require("config")
local host = require("lib.services.host")
local storage = require("storage_model")
local udisks = require("lib.services.udisks")

local M = {}

local CHECK = 300000

--- Open `row`: mounted first if it needs to be.
local function open(row)
  local disks = storage.disks()
  local function show(path) host.act({ "xdg-open", path }) end
  if row.mounted then return show(row.mount_point) end
  disks.mount(row, function(path) if type(path) == "string" then show(path) end end)
end

local ACTIONS = { open = open, human = udisks.human,
  eject = function(row) storage.disks().eject(row) end,
  settings = function()
    local sidebar = require("sidebar")
    require("utilities").request("storage")
    sidebar.select("settings")
    sidebar.drawer.set(true)
  end }

--- Shows the popup for `row`, unless the setting says not to.
function M.plugged(row)
  if config.get("storage.popup") ~= true then return false end
  require("themes").view("drive_popup").show(row, ACTIONS)
  return true
end

local warned = {}

--- Warns about each folder in `paths` that has fallen under the limit, once
--- until it rises again.
function M.check(paths)
  local limit = tonumber(config.get("storage.low_space")) or 0
  if limit <= 0 then return end
  for _, path in ipairs(paths or { "/", morf.fs.home() }) do
    local usage = storage.usage(path)
    if usage then
      local left = usage.free / usage.total * 100
      if left < limit and not warned[path] then
        warned[path] = true
        require("notifs").push { summary = "Low disk space",
          body = ("%s has %s free"):format(path == "/" and "The system disk" or path, udisks.human(usage.free)),
          urgency = 2, app = "eva", icon = "hard_drive" }
      elseif left >= limit then
        warned[path] = nil
      end
    end
  end
end

--- Follows both, on the primary output.
function M.start()
  if morf.window.primary and not morf.window.primary() then return end
  storage.disks().on_added(M.plugged)
  if host.fake() then morf.ipc["fake-plug"] = function() require("lib.services.host_fake").plug() return true end end
  morf.time.timer(CHECK, function() M.check() end, true)
  morf.time.timer(20000, function() M.check() end, false)
end

return M
