-- The session's notification server: morf's library, with the parts of the
-- protocol it does not reach.
--
--   local server = require("lib.services.notification_server").serve {
--     on_change = fn, on_inhibit = fn, capabilities = { ... },
--   }
--   server.dismiss(id)  server.expire(id)  server.invoke(id, key)  server.open(id)
--   server.reply(id, text)        -- NotificationReplied, then closed
--   server.set_capabilities(list)
--
-- The clocks are the shell's: every entry reaches `on_change` with
-- `timeout_ms` as sent, -1 meaning "the server decides". `on_inhibit(count)`
-- hears how many clients hold an Inhibit cookie.
local morf = require("morf")

local M = {}

local PATH = "/org/freedesktop/Notifications"
local INTERFACE = "org.freedesktop.Notifications"
local function u(value) return { signature = "u", value = value } end

M.CAPABILITIES = { "body", "actions", "persistence", "body-markup", "body-hyperlinks", "body-images",
  "icon-static", "action-icons", "inline-reply" }

-- Forwards the service the library holds, answering the methods it refuses.
local function wrap(service, methods)
  local proxy = {}
  function proxy:on_call(handler)
    return service:on_call(function(call)
      local extra = methods[call.member]
      if extra then return extra(call, service) end
      return handler(call)
    end)
  end
  function proxy:reply(...) return service:reply(...) end
  function proxy:reply_error(...) return service:reply_error(...) end
  function proxy:emit(...) return service:emit(...) end
  function proxy:close() return service:close() end
  return proxy
end

--- Starts serving; nil and a reason when the name stays with another daemon.
function M.serve(options)
  options = options or {}
  local lib = require("lib.services.notifications")
  local cookies, next_cookie, service = {}, 1, nil
  local function held()
    local count = 0
    for _ in pairs(cookies) do count = count + 1 end
    if options.on_inhibit then options.on_inhibit(count) end
  end
  local methods = {
    Inhibit = function(call, s)
      local cookie = next_cookie
      next_cookie = next_cookie + 1
      cookies[cookie] = call.arguments[1] or ""
      s:reply(call.id, u(cookie))
      held()
    end,
    UnInhibit = function(call, s)
      cookies[call.arguments[1]] = nil
      s:reply(call.id, nil)
      held()
    end,
  }
  local library_serve = morf.dbus and morf.dbus.serve
  if library_serve then
    morf.dbus.serve = function(...)
      local real, outcome = library_serve(...)
      if not real then return real, outcome end
      service = real
      return wrap(real, methods), outcome
    end
  end
  local ok, server, why = pcall(lib.serve, {
    on_change = options.on_change, replace = options.replace, expire = false, default_timeout_ms = -1,
    capabilities = options.capabilities or M.CAPABILITIES,
  })
  if library_serve then morf.dbus.serve = library_serve end
  if not ok then return nil, server end
  if not server then return nil, why end

  --- Tells the sender what was typed, then closes unless it stays resident.
  function server.reply(id, text)
    if not (server.open and server.open(id)) then return false end
    if service then service:emit(PATH, INTERFACE, "NotificationReplied", { u(id), tostring(text) }) end
    return true
  end

  --- What GetCapabilities answers from now on.
  function server.set_capabilities(list) server.capabilities = list end
  return server
end

return M
