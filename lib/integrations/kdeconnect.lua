-- KDE Connect through `kdeconnect-cli`, and its daemon's bus for what the CLI
-- does not print: the battery. Names are those of KDE Connect 26.04.
local morf = require("morf")
local poll = require("lib.util.poll")
local M = { TIMEOUT_MS = 6000, SEND_MS = 120000, BUS = "org.kde.kdeconnect.daemon",
  BATTERY = "org.kde.kdeconnect.device.battery" }

--- The program, or nil.
function M.program() return poll.which("kdeconnect-cli") end

--- Runs `kdeconnect-cli ...`.
function M.run(words, done, timeout)
  local program = M.program()
  if not program then done { ok = false, error = "kdeconnect-cli is not installed" } return end
  local argv = { program }
  for _, word in ipairs(words) do argv[#argv + 1] = word end
  local ok, why = pcall(morf.process.run, argv, { timeout_ms = timeout or M.TIMEOUT_MS }, done)
  if not ok then done { ok = false, error = tostring(why) } end
end

--- `--id-name-only` lines as `{ { id, name } }`.
function M.parse_devices(text)
  local out = {}
  for line in tostring(text):gmatch("[^\n]+") do
    local id, name = line:match("^(%S+)%s+(.+)$")
    if id then out[#out + 1] = { id = id, name = name } end
  end
  return out
end

--- `--list-notifications` lines, each shown as a person reads it.
function M.parse_notifications(text)
  local out = {}
  for line in tostring(text):gmatch("[^\n]+") do
    local said = line:gsub("^%-%s*", ""):gsub("%s+$", "")
    if said ~= "" then out[#out + 1] = said end
  end
  return out
end

--- Every known device: `done(devices)` with `{ id, name, reachable }`, or
--- `done(nil, why)`.
function M.devices(done)
  M.run({ "--list-devices", "--id-name-only" }, function(all)
    if not all.ok then
      done(nil, tostring(all.error or all.stderr or ""):gsub("%s+$", ""):sub(1, 200))
      return
    end
    local devices = M.parse_devices(all.stdout)
    M.run({ "--list-available", "--id-name-only" }, function(available)
      local reachable = {}
      for _, device in ipairs(M.parse_devices(available.ok and available.stdout or "")) do reachable[device.id] = true end
      for _, device in ipairs(devices) do device.reachable = reachable[device.id] == true end
      done(devices)
    end)
  end)
end

-- One property of the battery, read off `busctl`'s `TYPE VALUE`.
local function battery_property(id, name, done)
  local program = poll.which("busctl")
  if not program then done(nil) return end
  local path = "/modules/kdeconnect/devices/" .. id .. "/battery"
  morf.process.run({ program, "--user", "get-property", M.BUS, path, M.BATTERY, name }, { timeout_ms = 3000 }, function(result)
    done(result.ok and tostring(result.stdout):match("^%S+%s+(%S+)") or nil)
  end)
end

--- `done(percent, charging)`, nil when the phone has not said.
function M.battery(id, done)
  battery_property(id, "charge", function(charge)
    battery_property(id, "isCharging", function(charging)
      local percent = tonumber(charge)
      done(percent and percent >= 0 and percent or nil, charging == "true")
    end)
  end)
end

return M
