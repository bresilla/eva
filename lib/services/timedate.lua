-- The clock, the language and the machine's name: systemd's timedate1, locale1
-- and hostname1, each asked without waiting. `*_declared()` says whether the
-- system's configuration holds the value.
local host = require("lib.services.host")
local dbus_client = require("lib.services.dbus")

local M = {}

local PROPERTIES = "org.freedesktop.DBus.Properties"
local TIMEOUT = 25000

M.TIME = "org.freedesktop.timedate1"
M.LOCALE = "org.freedesktop.locale1"
M.HOST = "org.freedesktop.hostname1"

local function path(name) return "/" .. name:gsub("%.", "/") end

local function properties(name, done)
  local sent, why = host.bus("system").call1_async(name, path(name), PROPERTIES, "GetAll", { name }, TIMEOUT, done)
  if not sent then done(nil, why) end
end

local function call(name, method, arguments, done, what)
  if host.held(what or method) then return done(true) end
  local sent, why = host.bus("system").call_async(name, path(name), name, method, arguments, TIMEOUT, done)
  if not sent then done(nil, why) end
end

--- `done(properties, err)`: Timezone, NTP, CanNTP, NTPSynchronized, LocalRTC,
--- TimeUSec.
function M.time(done) properties(M.TIME, done) end
function M.locale(done) properties(M.LOCALE, done) end
function M.hostname(done) properties(M.HOST, done) end

--- `done(zones, err)`.
function M.timezones(done)
  local sent, why = host.bus("system").call1_async(M.TIME, path(M.TIME), M.TIME, "ListTimezones", nil, TIMEOUT, done)
  if not sent then done(nil, why) end
end

function M.set_timezone(zone, done) call(M.TIME, "SetTimezone", { zone, true }, done, "timezone " .. zone) end
function M.set_ntp(on, done) call(M.TIME, "SetNTP", { on == true, true }, done, "ntp " .. tostring(on)) end

--- Sets the clock to `seconds` since the epoch.
function M.set_time(seconds, done)
  call(M.TIME, "SetTime", { dbus_client.x(math.floor(seconds) * 1000000), false, true }, done, "set time")
end

--- Sets the system locale: `assignments` is a list such as `{ "LANG=nl_NL.UTF-8" }`.
function M.set_locale(assignments, done)
  call(M.LOCALE, "SetLocale", { dbus_client.typed("as", assignments), true }, done, "set locale")
end

function M.set_hostname(name, done)
  call(M.HOST, "SetStaticHostname", { name, true }, done, "hostname " .. name)
end

--- A name a static hostname may be, or nil and why not.
function M.valid_hostname(name)
  if #name == 0 then return nil, "Give it a name" end
  if #name > 63 then return nil, "A name is at most 63 characters" end
  if not name:match("^[%w][%w%-]*$") or name:sub(-1) == "-" then
    return nil, "Letters, digits and dashes only"
  end
  return name
end

--- `done(list, err)`: the locales this system has built.
function M.locales(done)
  host.read({ "localectl", "list-locales" }, function(text, why)
    if not text then return done(nil, why) end
    local out = {}
    for line in text:gmatch("[^\n]+") do out[#out + 1] = line end
    done(out)
  end)
end

--- `LANG=x` and the like, as a table by name.
function M.parse_locale(list)
  local out = {}
  for _, entry in ipairs(list or {}) do
    local key, value = tostring(entry):match("^([%w_]+)=(.*)$")
    if key then out[key] = value end
  end
  return out
end

function M.timezone_declared() return host.declared("/etc/localtime") end
function M.locale_declared() return host.declared("/etc/locale.conf") end
function M.hostname_declared() return host.declared("/etc/hostname") end

return M
