-- What the Power page changes beyond the profile: logind's lid and button
-- defaults as read, the shell's own idle timeouts and the graphics mode.
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

--- `CanSuspend` and its siblings: `done({ suspend, hibernate, ... })`, each
--- "yes", "no", "challenge" or "na".
function M.can(done)
  local names = { suspend = "CanSuspend", hibernate = "CanHibernate", reboot = "CanReboot", shutdown = "CanPowerOff" }
  local out, waiting = {}, 0
  for _ in pairs(names) do waiting = waiting + 1 end
  for key, method in pairs(names) do
    local function answer(reply)
      out[key] = type(reply) == "string" and reply or ""
      waiting = waiting - 1
      if waiting == 0 then done(out) end
    end
    if not host.bus("system").call1_async(LOGIN, MANAGER_PATH, MANAGER, method, nil, 5000, answer) then answer(nil) end
  end
end

--- Whether a logind answer lets a person try: an unknown answer does.
function M.allowed(answer) return answer == "" or answer == nil or answer == "yes" or answer == "challenge" end

-- The session actions logind has a question for.
local CAN = { suspend = "CanSuspend", hibernate = "CanHibernate", reboot = "CanReboot", shutdown = "CanPowerOff" }

--- Whether session action `id` is possible here, asked at once. An action
--- logind has no say in, or a logind that does not answer, stays offered.
function M.can_now(id)
  local method = CAN[id]
  if not method then return true end
  local client = host.bus("system")
  if not client.has_owner(LOGIN) then return true end
  return M.allowed(client.call1(LOGIN, MANAGER_PATH, MANAGER, method))
end

-- ------------------------------------------------------------------- idle --

M.IDLE_FILE = "/etc/eva/idle.json"

--- What the system configuration set up, or nil where nothing did:
--- `{ lockTimeout, screenOffTimeout, suspendTimeout, commands }`.
function M.idle_system(path)
  local fake = host.fake() and require("lib.services.host_fake")
  if fake then return fake.idle_system() end
  path = path or M.IDLE_FILE
  if not morf.fs.exists(path) then return nil end
  local ok, value = pcall(function() return morf.json.decode(morf.fs.read(path)) end)
  return ok and type(value) == "table" and value or nil
end

--- The override file a session's hypridle prefers.
function M.idle_path() return morf.paths.state("eva/idle/hypridle.conf") end

--- hypridle's configuration for `seconds` ({ lock, screen, suspend }), over
--- the commands of `system`.
function M.idle_text(seconds, system)
  local c = system.commands or {}
  local parts = { "general {", "  lock_cmd = " .. tostring(c.lock_session or ""),
    "  before_sleep_cmd = " .. tostring(c.before_sleep or ""), "  after_sleep_cmd = " .. tostring(c.after_sleep or ""),
    "  inhibit_sleep = 3", "}", "" }
  local function listener(timeout, on_timeout, on_resume)
    if (tonumber(timeout) or 0) <= 0 then return end
    parts[#parts + 1] = "listener {"
    parts[#parts + 1] = "  timeout = " .. math.floor(timeout)
    parts[#parts + 1] = "  on-timeout = " .. tostring(on_timeout or "")
    if on_resume then parts[#parts + 1] = "  on-resume = " .. tostring(on_resume) end
    parts[#parts + 1] = "}"
    parts[#parts + 1] = ""
  end
  listener(seconds.lock, c.lock)
  listener(seconds.screen, c.screen_off, c.screen_on)
  listener(seconds.suspend, c.suspend)
  return table.concat(parts, "\n")
end

--- Writes the override and restarts hypridle on it. `done(ok, why)`.
function M.idle_apply(seconds, system, done)
  if host.held("idle timeouts") then return done(true) end
  local path = M.idle_path()
  morf.fs.mkdir((path:gsub("/[^/]+$", "")))
  local wrote, why = pcall(morf.fs.write, path, M.idle_text(seconds, system))
  if not wrote then return done(nil, tostring(why)) end
  host.act({ "systemctl", "--user", "restart", "hypridle.service" }, done)
end

--- Takes the override away, back to the system's timeouts.
function M.idle_reset(done)
  if host.held("idle timeouts reset") then return done(true) end
  pcall(morf.fs.remove, M.idle_path())
  host.act({ "systemctl", "--user", "restart", "hypridle.service" }, done)
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
