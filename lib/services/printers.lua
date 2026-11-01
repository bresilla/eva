-- CUPS through its own commands: the queues, their jobs, adding one, and the
-- scanners SANE sees. Pure parsers over what the commands print, and the
-- commands themselves through lib.services.host.
local host = require("lib.services.host")

local M = {}

-- CUPS answers in the person's language, and these parsers read its English.
local ENGLISH = { env = { LC_ALL = "C" } }

--- `lpstat -p`: `{ name, state, enabled, reason }`. `state` is idle, printing or
--- stopped. What follows a printing printer's line is its filters' progress.
function M.parse_printers(text)
  local out, current = {}, nil
  for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    local name, rest = line:match("^printer (%S+)%s+(.*)$")
    if name then
      local state = rest:match("^is (%a+)") or (rest:find("^disabled") and "stopped")
        or (rest:find("^now printing") and "printing") or "idle"
      current = { name = name, state = state, enabled = not rest:find("disabled", 1, true), reason = "" }
      out[#out + 1] = current
    elseif current and current.state ~= "printing" and line:match("^%s+%S") then
      current.reason = line:gsub("^%s+", "")
    end
  end
  return out
end

--- `lpstat -d`: the default's name, or "".
function M.parse_default(text) return tostring(text or ""):match("destination:%s*(%S+)") or "" end

--- `lpstat -v`: a table of device URIs by printer.
function M.parse_devices(text)
  local out = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local name, uri = line:match("^device for ([^:]+):%s*(%S+)")
    if name then out[name] = uri end
  end
  return out
end

--- `lpstat -o`: `{ id, printer, user, size }`.
function M.parse_jobs(text)
  local out = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local id, user, size = line:match("^(%S+)%s+(%S+)%s+(%d+)")
    if id then
      out[#out + 1] = { id = id, printer = id:match("^(.*)%-%d+$") or id, user = user, size = tonumber(size) or 0 }
    end
  end
  return out
end

--- `driverless` or `lpinfo -v`: `{ uri, name }` for what can be added.
function M.parse_discovered(text)
  local out, seen = {}, {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local uri = line:match("(%a[%w+]*://%S+)")
    if uri and not seen[uri] then
      seen[uri] = true
      local name = uri:match("^%a[%w+]*://([^/:]+)") or uri
      out[#out + 1] = { key = uri, uri = uri, name = (name:gsub("%.local%.?$", ""):gsub("%%20", " ")), words = uri }
    end
  end
  return out
end

--- `scanimage -L`: `{ device, name }`.
function M.parse_scanners(text)
  local out = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local device, name = line:match("^device [`'](.-)' is an? (.+)$")
    if device then out[#out + 1] = { device = device, name = name } end
  end
  return out
end

--- What CUPS has now, all at once. `done(snapshot)`; `snapshot.available` is
--- whether its commands are here and the scheduler answers.
function M.read(done)
  if not host.installed("lpstat") then return done { available = false, printers = {}, jobs = {}, scanners = {} } end
  local snapshot = { available = true, printers = {}, jobs = {}, default = "", devices = {}, scanners = {} }
  local waiting = 4
  local function one()
    waiting = waiting - 1
    if waiting > 0 then return end
    for _, row in ipairs(snapshot.printers) do
      row.default, row.uri = row.name == snapshot.default, snapshot.devices[row.name] or ""
    end
    done(snapshot)
  end
  host.read({ "lpstat", "-p" }, function(text, why)
    if text == nil and tostring(why):lower():find("scheduler is not running", 1, true) then
      snapshot.available = false
    end
    snapshot.printers = M.parse_printers(text)
    one()
  end, ENGLISH)
  host.read({ "lpstat", "-d" }, function(text) snapshot.default = M.parse_default(text) one() end, ENGLISH)
  host.read({ "lpstat", "-v" }, function(text) snapshot.devices = M.parse_devices(text) one() end, ENGLISH)
  host.read({ "lpstat", "-o" }, function(text)
    snapshot.jobs = M.parse_jobs(text)
    if host.installed("scanimage") then
      return host.read({ "scanimage", "-L" }, function(found) snapshot.scanners = M.parse_scanners(found) one() end,
        { timeout_ms = 8000 })
    end
    one()
  end, ENGLISH)
end

--- `done(list)`: printers the network offers.
function M.discover(done)
  local argv = host.installed("driverless") and { "driverless" } or { "lpinfo", "-v" }
  host.read(argv, function(text) done(M.parse_discovered(text)) end, { timeout_ms = 12000 })
end

--- A queue name CUPS takes, made from `name`.
function M.queue_name(name)
  local out = tostring(name or ""):gsub("[^%w_%-]", "_"):gsub("^_+", ""):gsub("_+$", "")
  return out ~= "" and out or "printer"
end

--- Adds a driverless queue. `done(ok, why)`.
function M.add(name, uri, done)
  if not tostring(uri):match("^%a[%w+]*://%S+$") then return done(nil, "That is not a printer address") end
  host.act({ "lpadmin", "-p", M.queue_name(name), "-E", "-v", uri, "-m", "everywhere" }, done)
end

function M.remove(name, done) host.act({ "lpadmin", "-x", name }, done) end
function M.set_default(name, done) host.act({ "lpadmin", "-d", name }, done) end
function M.set_enabled(name, on, done) host.act({ on and "cupsenable" or "cupsdisable", name }, done) end
function M.cancel(id, done) host.act({ "cancel", id }, done) end

return M
