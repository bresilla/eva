-- The NFC radio: neard, `org.neard` on the system bus, over the kernel's
-- /sys/class/nfc. An adapter's `Powered` is the switch. A machine with no
-- adapter, or no neard, has no NFC to offer; the service is never started by
-- looking.
--
--   local nfc = require("lib.services.nfc").connect()
--   if nfc.state.available then nfc.set(true) end
local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local M = {}

local NAME, ADAPTER = "org.neard", "org.neard.Adapter"
local TIMEOUT = 5000

--- The first adapter the kernel has under `dir`, by name, or nil.
function M.adapter(dir)
  local ok, entries = pcall(morf.fs.list, dir or "/sys/class/nfc", { follow = true })
  for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
    if entry.name:match("^nfc%d+$") then return entry.name end
  end
end

--- Starts watching. `options`: `dbus` (the bus seam), `dir` (/sys/class/nfc).
function M.connect(options)
  options = options or {}
  local client = dbus_client.new({ dbus = options.dbus, bus = "system" })
  local state = morf.state({ available = false, powered = false })
  local nfc = { state = state }
  local path

  local function read()
    local name = M.adapter(options.dir)
    path = name and "/org/neard/" .. name or nil
    local p = path and client.has_owner(NAME) and client.get_all(NAME, path, ADAPTER) or nil
    state.available = p ~= nil
    state.powered = p ~= nil and p.Powered == true
  end

  --- Turns the radio on or off. `done(ok, err)`.
  function nfc.set(on, done)
    if not path then return nil, "no NFC adapter" end
    return client.set_async(NAME, path, ADAPTER, "Powered", on == true, TIMEOUT, function(reply, err)
      if reply ~= nil then state.powered = on == true end
      if done then done(reply ~= nil, err) end
    end)
  end

  client.watch_name(NAME, function() read() end)
  read()
  if path then
    client.on_properties(NAME, path, function(_, changed)
      if changed.Powered ~= nil then state.powered = changed.Powered == true end
    end)
  end
  return nfc
end

return M
