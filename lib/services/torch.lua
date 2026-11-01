-- The flashlight: an LED under /sys/class/leds named `*:torch` or `*:flash`,
-- read with `morf.fs` and written with logind's `Session.SetBrightness`,
-- which an active session may do without privileges (as lib.services.logind
-- does for the backlight).
--
--   local torch = require("lib.services.torch").new()
--   if torch.device() then torch.set(true) end
local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local M = {}

local LOGIND = "org.freedesktop.login1"
local SESSION = LOGIND .. ".Session"
local AUTO_SESSION = "/org/freedesktop/login1/session/auto"
local TIMEOUT = 5000

local function number(text)
  if type(text) ~= "string" then return nil end
  return tonumber((text:gsub("%s+", "")))
end

--- The torch under `dir` (a `:torch` before a `:flash`): `{ name, value,
--- max }`, or nil.
function M.find(dir)
  local entries = morf.fs.list(dir)
  local best
  for _, entry in ipairs(type(entries) == "table" and entries or {}) do
    local name = entry.name
    local kind = name and (name:match(":(torch)$") or name:match(":(flash)$"))
    if kind and (not best or kind == "torch") then
      local max = number(morf.fs.read(dir .. "/" .. name .. "/max_brightness"))
      if max and max > 0 then
        best = { name = name, max = max, kind = kind,
          value = number(morf.fs.read(dir .. "/" .. name .. "/brightness")) or 0 }
        if kind == "torch" then break end
      end
    end
  end
  return best
end

--- `options`: `dir` (/sys/class/leds), `dbus` (the bus seam).
function M.new(options)
  options = options or {}
  local dir = options.dir or "/sys/class/leds"
  local client = dbus_client.new({ dbus = options.dbus, bus = "system" })
  local torch = {}
  local device = M.find(dir)
  local lit = morf.signal("eva.torch.on." .. tostring(torch), device ~= nil and device.value > 0)

  --- The LED, or nil on a machine without one.
  function torch.device() return device end

  --- Whether it is lit.
  function torch.on() return lit:get() end

  --- Lights it or puts it out. `done(ok, err)`.
  function torch.set(on, done)
    if not device then return nil, "no torch" end
    return client.call_async(LOGIND, AUTO_SESSION, SESSION, "SetBrightness",
      { "leds", device.name, dbus_client.u(on and device.max or 0) }, TIMEOUT, function(reply, err)
        if reply ~= nil then lit:set(on == true) end
        if done then done(reply ~= nil, err) end
      end)
  end

  return torch
end

return M
