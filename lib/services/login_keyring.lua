-- Once a session, for an account with a pattern: a locked default keyring is
-- asked to unlock, and gnome-keyring's prompt comes to eva's keyring dialog.
local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local M = { NAME = "org.freedesktop.secrets", ROOT = "/org/freedesktop/secrets",
  SERVICE = "org.freedesktop.Secret.Service" }

local first = dbus_client.first

--- Over `bus`: `done("open" | "asked")`, or `done(nil, why)`.
function M.unlock(bus, done)
  done = done or function() end
  local function fail(why) done(nil, tostring(why or "no answer")) end
  bus.call_async(M.NAME, M.ROOT, M.SERVICE, "ReadAlias", { "default" }, 5000, function(reply, why)
    local path = first(reply)
    if type(path) ~= "string" or path == "" or path == "/" then return fail(why or "no default keyring") end
    bus.call_async(M.NAME, path, "org.freedesktop.DBus.Properties", "Get",
      { "org.freedesktop.Secret.Collection", "Locked" }, 5000, function(locked, why_locked)
        locked = first(locked)
        if locked == false then return done("open") end
        if locked ~= true then return fail(why_locked) end
        bus.call_async(M.NAME, M.ROOT, M.SERVICE, "Unlock", { dbus_client.typed("ao", { path }) }, 5000,
          function(answer, why_unlock)
            if type(answer) ~= "table" then return fail(why_unlock) end
            local prompt = answer[2]
            if type(prompt) ~= "string" or prompt == "/" then return done("open") end
            bus.call_async(M.NAME, prompt, "org.freedesktop.Secret.Prompt", "Prompt", { "" }, 5000,
              function(sent, why_prompt) if sent then done("asked") else fail(why_prompt) end end)
          end)
      end)
  end)
end

--- `options.user`, `bus`, `marker` and `done`; true when it asked.
function M.ask_once(options)
  local marker = options.marker or ((morf.env("XDG_RUNTIME_DIR") or "") .. "/eva/keyring-asked")
  if morf.fs.exists(marker) then return false end
  if not require("lib.shell.auth.patty").kind(options.user) then return false end
  pcall(morf.fs.write, marker, "", { parents = true })
  M.unlock(options.bus, options.done)
  return true
end

return M
