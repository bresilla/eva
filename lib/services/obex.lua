-- Sending a file over Bluetooth, through BlueZ's obexd on the session bus.
local host = require("lib.services.host")
local dbus_client = require("lib.services.dbus")

local M = {}

local NAME = "org.bluez.obex"
local ROOT = "/org/bluez/obex"
local CLIENT, PUSH, TRANSFER = NAME .. ".Client1", NAME .. ".ObjectPush1", NAME .. ".Transfer1"
local TIMEOUT = 30000

local typed = dbus_client.typed

--- Sends `path` to the device at `address`. `progress(status, sent, size)`
--- hears it go; `done(ok, why)` hears how it ended.
function M.send(address, path, progress, done)
  if host.held("send " .. path .. " to " .. address) then return done(true) end
  local client = host.bus("session")
  local session
  local function finish(ok, why)
    if session then client.call_async(NAME, ROOT, CLIENT, "RemoveSession", { dbus_client.o(session) }, TIMEOUT) end
    done(ok, why)
  end
  local function watch(transfer)
    client.call_async(NAME, transfer, "org.freedesktop.DBus.Properties", "GetAll", { TRANSFER }, TIMEOUT, function(reply)
      local state = type(reply) == "table" and dbus_client.first(reply) or nil
      if type(state) ~= "table" then return finish(true) end
      progress(state.Status or "", state.Transferred or 0, state.Size or 0)
      if state.Status == "complete" then return finish(true) end
      if state.Status == "error" then return finish(nil, "The device did not take it") end
      require("morf").time.timer(500, function() watch(transfer) end, false)
    end)
  end
  local sent, why = client.call1_async(NAME, ROOT, CLIENT, "CreateSession",
    { address, typed("a{sv}", { Target = "opp" }) }, TIMEOUT, function(reply, failed)
      if type(reply) ~= "string" then return done(nil, failed or "Sending needs BlueZ's obexd") end
      session = reply
      client.call_async(NAME, session, PUSH, "SendFile", { path }, TIMEOUT, function(answer, refused)
        if type(answer) ~= "table" or type(answer[1]) ~= "string" then
          return finish(nil, refused or "The device did not answer")
        end
        watch(answer[1])
      end)
    end)
  if not sent then done(nil, why) end
end

return M
