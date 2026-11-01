-- Which firewall this machine has and whether it is up. firewalld and ufw are
-- started and stopped through polkit; NixOS builds its firewall from the
-- system configuration, so there it is read and never changed.
local host = require("lib.services.host")

local M = {}

--- `done(state)`: `backend` (firewalld, ufw, nixos, or "" for none), `on`
--- (true, false, or nil when it cannot be told), `declarative`.
function M.read(done)
  if host.installed("firewall-cmd") then
    return host.read({ "firewall-cmd", "--state" }, function(text)
      done { backend = "firewalld", on = text ~= nil and text:find("running", 1, true) ~= nil, declarative = false }
    end)
  end
  if host.installed("ufw") then
    return host.read({ "systemctl", "is-active", "ufw.service" }, function(text)
      done { backend = "ufw", on = text ~= nil and text:find("active", 1, true) == 1, declarative = false }
    end)
  end
  if host.nixos() then
    return host.read({ "systemctl", "is-active", "firewall.service" }, function(text)
      done { backend = "nixos", on = text ~= nil and text:find("active", 1, true) == 1, declarative = true }
    end)
  end
  done { backend = "", on = nil, declarative = false }
end

--- Turns the firewall on or off. `done(ok, why)`.
function M.set(backend, on, done)
  if backend == "firewalld" then
    return host.act({ "pkexec", "systemctl", on and "enable" or "disable", "--now", "firewalld.service" }, done)
  end
  if backend == "ufw" then return host.act({ "pkexec", "ufw", on and "enable" or "disable" }, done) end
  done(nil, "This firewall is not changed from here")
end

return M
