-- What sandboxed apps were allowed, from xdg-permission-store: the portals'
-- table of decisions on the session bus. It holds answers for apps that asked
-- through a portal (Flatpak, Snap): a native program never appears in it.
local host = require("lib.services.host")
local dbus_client = require("lib.services.dbus")
local unicase = require("lib.util.unicase")

local M = {}

local NAME = "org.freedesktop.impl.portal.PermissionStore"
local PATH = "/org/freedesktop/impl/portal/PermissionStore"
local TIMEOUT = 5000

-- The tables a person would look through, as the portals name them.
M.KINDS = {
  { id = "location", table = "location", entry = "location", name = "Location", icon = "location_on" },
  { id = "camera", table = "devices", entry = "camera", name = "Camera", icon = "photo_camera" },
  { id = "microphone", table = "devices", entry = "microphone", name = "Microphone", icon = "mic" },
  { id = "screenshot", table = "screenshot", entry = "screenshot", name = "Screenshots", icon = "screenshot_monitor" },
  { id = "notification", table = "notifications", entry = "notification", name = "Notifications", icon = "notifications" },
  { id = "background", table = "background", entry = "background", name = "Running in the background", icon = "layers" },
}

M.BY_ID = {}
for _, kind in ipairs(M.KINDS) do M.BY_ID[kind.id] = kind end

--- Whether a stored answer allows: location keeps an accuracy and a time,
--- everything else a yes, a no or an ask.
function M.allowed(kind, values)
  local first = values and values[1]
  if kind.id == "location" then return first ~= nil and first ~= "NONE" end
  return first == "yes"
end

--- What to store for `on`, keeping a location's last-used time.
function M.answer(kind, on, values)
  if kind.id == "location" then return { on and "EXACT" or "NONE", values and values[2] or "0" } end
  return { on and "yes" or "no" }
end

--- When a location answer was last used, in seconds, or nil.
function M.used_at(kind, values)
  if kind.id ~= "location" then return nil end
  local stamp = tonumber(values and values[2])
  if stamp and stamp > 0 then return stamp end
end

--- `done(rows)`: one `{ app, on, used_at, values }` per app that has answered
--- `kind`. No store, or nothing asked yet, is an empty list; `rows.missing`
--- says there was no store to ask.
function M.read(kind, done)
  local client = host.bus("session")
  local sent = client.call_async(NAME, PATH, NAME, "Lookup", { kind.table, kind.entry }, TIMEOUT, function(reply, why)
    local rows = {}
    if reply == nil then
      -- Asking for an entry nobody has answered is an error too.
      rows.missing = why ~= nil and tostring(why):find("NotFound", 1, true) == nil
      return done(rows)
    end
    local permissions = type(reply) == "table" and reply[1] or {}
    for app, values in pairs(permissions) do
      rows[#rows + 1] = { app = app, values = values, on = M.allowed(kind, values), used_at = M.used_at(kind, values) }
    end
    table.sort(rows, function(a, b) return a.app < b.app end)
    done(rows)
  end)
  if not sent then done { missing = true } end
end

--- Allows or refuses one app. `done(ok, why)`.
function M.set(kind, row, on, done)
  if host.held("permission " .. kind.id .. " " .. row.app) then return done(true) end
  local answer = dbus_client.typed("as", M.answer(kind, on, row.values))
  local sent, why = host.bus("session").call_async(NAME, PATH, NAME, "SetPermission",
    { kind.table, true, kind.entry, row.app, answer }, TIMEOUT, done)
  if not sent then done(nil, why) end
end

--- Forgets an app's answer, so it asks again. `done(ok, why)`.
function M.forget(kind, row, done)
  if host.held("forget permission " .. kind.id .. " " .. row.app) then return done(true) end
  local sent, why = host.bus("session").call_async(NAME, PATH, NAME, "DeletePermission",
    { kind.table, kind.entry, row.app }, TIMEOUT, done)
  if not sent then done(nil, why) end
end

--- An app id as a name: its last part.
function M.app_name(id)
  local last = tostring(id):match("([^%.]+)$") or tostring(id)
  return unicase.capitalise(last)
end

return M
