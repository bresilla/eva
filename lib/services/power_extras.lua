-- What the Power page changes beyond the profile: logind's lid and button
-- defaults as read, and the graphics mode.
local morf = require("morf")
local host = require("lib.services.host")

local M = {}

local LOGIN, MANAGER_PATH = "org.freedesktop.login1", "/org/freedesktop/login1"
local MANAGER = LOGIN .. ".Manager"
local PROPERTIES = "org.freedesktop.DBus.Properties"

--- `done(properties)`: logind's manager, `{}` without it.
function M.logind(done)
  local sent = host.bus("system").call1_async(LOGIN, MANAGER_PATH, PROPERTIES, "GetAll", { MANAGER }, 5000,
    function(reply) done(type(reply) == "table" and reply or {}) end)
  if not sent then done {} end
end

-- -------------------------------------------------------------------- GPU --

M.GPU_MODES = { Integrated = "Battery first, the discrete GPU off", Hybrid = "Both, the discrete GPU on demand",
  AsusMuxDgpu = "The discrete GPU drives the screen", Vfio = "The discrete GPU kept for a virtual machine",
  integrated = "Battery first, the discrete GPU off", hybrid = "Both, the discrete GPU on demand",
  nvidia = "The discrete GPU drives the screen" }

--- `done(state)`: `tool` ("" for none), `mode`, `modes` ({ { key, name, hint } }).
function M.gpu(done)
  local function rows(list)
    local out = {}
    for index, word in ipairs(list) do
      out[index] = { key = word, name = word:sub(1, 1):upper() .. word:sub(2), hint = M.GPU_MODES[word] or "" }
    end
    return out
  end
  if host.installed("supergfxctl") then
    return host.read({ "supergfxctl", "-g" }, function(mode)
      host.read({ "supergfxctl", "-s" }, function(supported)
        local list = {}
        for word in tostring(supported or ""):gmatch("%a+") do list[#list + 1] = word end
        done { tool = "supergfxctl", mode = (tostring(mode or ""):gsub("%s+", "")), modes = rows(list) }
      end)
    end)
  end
  if host.installed("envycontrol") then
    return host.read({ "envycontrol", "--query" }, function(mode)
      done { tool = "envycontrol", mode = tostring(mode or ""):match("%a+") or "",
        modes = rows { "integrated", "hybrid", "nvidia" } }
    end)
  end
  done { tool = "", mode = "", modes = {} }
end

--- Asks for a mode: `done(ok, why)`. It lands at the next login or restart.
function M.set_gpu(tool, mode, done)
  if not tostring(mode):match("^%a+$") then return done(nil, "That is not a mode") end
  if tool == "supergfxctl" then return host.act({ "supergfxctl", "-m", mode }, done) end
  if tool == "envycontrol" then return host.act({ "pkexec", "envycontrol", "-s", mode }, done) end
  done(nil, "No graphics tool")
end

return M
