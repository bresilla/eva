-- What the Updates page checks: on NixOS the age of a flake's inputs and a
-- rebuild with its live log, elsewhere how many packages wait in each package
-- manager; and `eva-update --check`, that count. A rebuild is a machine
-- action: dry, a canned log plays and nothing runs. No nodes.
local morf = require("morf")
local host = require("lib.services.host")

-- A package manager, asked: it only reads, so it runs even in a dry run.
local sys = { dry = host.dry, run = function(argv, options, done)
  local own = {}
  for key, value in pairs(options or {}) do if key ~= "read" then own[key] = value end end
  morf.process.run(argv, own, function(result) done(result or {}) end)
end }

local M = {
  nixos = morf.signal("update.nixos", false),
  flake = morf.signal("update.flake", ""),
  inputs = morf.signal("update.inputs", {}),
  managers = morf.signal("update.managers", {}),
  checking = morf.signal("update.checking", 0),
  state = morf.signal("update.state", "idle"),
  message = morf.signal("update.message", ""),
  rows = morf.list_model({}),
  lines = morf.signal("update.lines", 0),
}

-- Days after which an input counts as behind, and shows as such past `OLD`.
M.STALE = 30
M.OLD = 90
-- The most lines of a rebuild kept, and how long they wait to land together.
M.LIMIT = 5000
M.FLUSH = 150
-- How long a dry log waits between its lines.
M.CANNED_PACE = 400
M.CANNED = {
  "building the system configuration...",
  "these 3 derivations will be built:",
  "  /nix/store/aaaa-etc.drv",
  "  /nix/store/bbbb-system-path.drv",
  "  /nix/store/cccc-nixos-system-canned-26.05.drv",
  "copying path '/nix/store/dddd-linux-6.18' from 'https://cache.nixos.org'...",
  "building '/nix/store/aaaa-etc.drv'...",
  "building '/nix/store/bbbb-system-path.drv'...",
  "building '/nix/store/cccc-nixos-system-canned-26.05.drv'...",
  "activating the configuration...",
  "setting up /etc...",
  "reloading user units for ada...",
  "restarting sysinit-reactivation.target",
  "the following new units were started: canned.service",
  "Done. The new configuration is the current one.",
}

M.root = morf.env("EVA_UPDATE_ROOT") or ""

-- ----------------------------------------------------------- the flake lock --

local function setting()
  local ok, config = pcall(require, "config")
  if not ok then return nil end
  local found, value = pcall(config.get, "update.flake")
  return found and type(value) == "string" and value ~= "" and value or nil
end

local function exists(path)
  local ok, there = pcall(morf.fs.exists, path)
  return ok and there
end

--- The flake.lock to read, or nil: EVA_UPDATE_FLAKE, /etc/nixos/flake.lock, the
--- setting `update.flake`. A folder stands for the lock in it.
function M.locate()
  local function lock_in(path)
    if not path or path == "" then return nil end
    return path:match("flake%.lock$") and path or (path:gsub("/$", "") .. "/flake.lock")
  end
  local chosen = lock_in(morf.env("EVA_UPDATE_FLAKE"))
  if chosen then return chosen end
  local system = M.root .. "/etc/nixos/flake.lock"
  if exists(system) then return system end
  return lock_in(setting())
end

--- The flake's folder.
function M.folder(lock) return (lock:gsub("/?flake%.lock$", "")) end

local function source_of(locked)
  local kind = locked.type or ""
  if locked.owner and locked.repo then return ("%s:%s/%s"):format(kind, locked.owner, locked.repo) end
  return locked.url or locked.path or kind
end

--- The root's inputs from the text of a flake.lock, the oldest first:
--- `{ name, source, rev, modified }`. nil and why, for a file that is no lock.
function M.parse(text)
  local ok, data = pcall(morf.json.decode, text or "")
  if not ok or type(data) ~= "table" or type(data.nodes) ~= "table" then return nil, "This is no flake.lock" end
  local root = data.nodes[data.root or "root"]
  if type(root) ~= "table" then return nil, "This flake.lock has no root" end
  local out = {}
  for name, target in pairs(root.inputs or {}) do
    local node = type(target) == "string" and data.nodes[target] or nil
    if node and type(node.locked) == "table" then
      out[#out + 1] = { name = name, source = source_of(node.locked), modified = node.locked.lastModified or 0,
        rev = tostring(node.locked.rev or ""):sub(1, 7) }
    end
  end
  table.sort(out, function(a, b)
    if a.modified == b.modified then return a.name < b.name end
    return a.modified < b.modified
  end)
  return out
end

local function now() return tonumber(morf.env("EVA_NOW")) or morf.time.now() end

--- Whole days since `modified`.
function M.days(modified) return math.floor((now() - modified) / 86400) end

--- How old an input is, in words.
function M.age(modified)
  if not modified or modified <= 0 then return "No date" end
  local days = M.days(modified)
  if days < 1 then return "Today" end
  if days == 1 then return "Yesterday" end
  if days < 60 then return days .. " days" end
  if days < 730 then return math.floor(days / 30) .. " months" end
  return math.floor(days / 365) .. " years"
end

--- How many inputs are behind.
function M.behind(list)
  local count = 0
  for _, input in ipairs(list) do
    if input.modified > 0 and M.days(input.modified) >= M.STALE then count = count + 1 end
  end
  return count
end

--- Reads the lock again.
function M.read_flake()
  local lock = M.locate()
  M.flake:set(lock or "")
  if not lock then
    M.inputs:set({})
    M.message:set("No flake.lock found")
    return false
  end
  local ok, text = pcall(morf.fs.read, lock)
  if not ok or type(text) ~= "string" then
    M.inputs:set({})
    M.message:set("Cannot read " .. lock)
    return false
  end
  local list, why = M.parse(text)
  M.inputs:set(list or {})
  M.message:set(why or "")
  return list ~= nil
end

-- -------------------------------------------------------- the other systems --

local function lines_after(text, first)
  local out, skip = {}, first
  for line in tostring(text or ""):gmatch("[^\n]+") do
    if skip then skip = false else out[#out + 1] = line end
  end
  return out
end

local function names(lines)
  local out = {}
  for _, line in ipairs(lines) do
    local name = line:match("^%s*([^%s/]+)")
    if name then out[#out + 1] = name end
  end
  return out
end

-- Each manager: how it is asked, which exits mean it answered, and its answer's
-- package names.
M.MANAGERS = {
  { name = "pacman", argv = { "checkupdates" }, codes = { [0] = true, [2] = true }, read = function(text) return names(lines_after(text)) end },
  { name = "apt", argv = { "apt", "list", "--upgradable" }, codes = { [0] = true },
    read = function(text) return names(lines_after(text, true)) end },
  { name = "dnf", argv = { "dnf", "check-update", "--quiet" }, codes = { [0] = true, [100] = true }, read = function(text) return names(lines_after(text)) end },
  { name = "flatpak", argv = { "flatpak", "remote-ls", "--updates", "--columns=application" }, codes = { [0] = true },
    read = function(text) return names(lines_after(text)) end },
}

--- Asks every manager the machine has. `done(found)` after the last one:
--- `{ { name, count, packages } }`.
function M.check_managers(done)
  local found, waiting = {}, #M.MANAGERS
  M.checking:set(waiting)
  for _, manager in ipairs(M.MANAGERS) do
    sys.run(manager.argv, { read = true, timeout_ms = 120000 }, function(result)
      if result.code and manager.codes[result.code] then
        local packages = manager.read(result.stdout)
        found[#found + 1] = { name = manager.name, count = #packages, packages = packages }
      end
      waiting = waiting - 1
      M.checking:set(waiting)
      if waiting > 0 then return end
      table.sort(found, function(a, b) return a.name < b.name end)
      M.managers:set(found)
      if done then done(found) end
    end)
  end
end

--- What waits, as one number: inputs behind on NixOS, plus packages everywhere.
function M.pending()
  local count = M.nixos:get() and M.behind(M.inputs:get()) or 0
  for _, manager in ipairs(M.managers:get()) do count = count + manager.count end
  return count
end

-- ------------------------------------------------------------- the rebuild --

local lines, waiting = {}, {}
local child, flush_timer, canned_timer
local serial = 0
local generation = 0

local function flush()
  flush_timer = nil
  if #waiting == 0 then return end
  for _, line in ipairs(waiting) do
    serial = serial + 1
    lines[#lines + 1] = { key = serial, text = line }
  end
  waiting = {}
  local over = #lines - M.LIMIT
  if over > 0 then table.move(lines, over + 1, #lines + over, 1) end
  M.rows:replace(lines, "key")
  M.lines:set(#lines)
end

--- Takes a line of the log; the list hears of it a moment later.
function M.feed(line)
  waiting[#waiting + 1] = line
  if not flush_timer then flush_timer = morf.time.timer(M.FLUSH, flush, false) end
end

local function finish(code)
  child = nil
  if canned_timer then canned_timer:cancel() end
  canned_timer = nil
  if flush_timer then flush_timer:cancel() end
  flush()
  M.state:set(code == 0 and "done" or "failed")
  M.message:set(code == 0 and "The rebuild finished" or ("The rebuild failed with " .. tostring(code)))
end

--- The command of a rebuild of this flake.
function M.argv()
  local program = morf.env("EVA_PKEXEC") or "pkexec"
  return { program, "nixos-rebuild", "switch", "--flake", M.folder(M.flake:get()) }
end

local function play_canned()
  local index = 0
  canned_timer = morf.time.timer(M.CANNED_PACE, function()
    index = index + 1
    if M.CANNED[index] then
      M.feed(M.CANNED[index])
    else
      finish(0)
    end
  end, true)
end

--- Starts the rebuild, unless one runs. Dry, a canned log stands in for it.
function M.rebuild()
  if M.state:get() == "running" or M.flake:get() == "" then return false end
  generation = generation + 1
  local own = generation
  lines, waiting = {}, {}
  M.rows:replace({}, "key")
  M.lines:set(0)
  M.state:set("running")
  M.message:set("Rebuilding")
  if sys.dry() then
    morf.log("info", "eva: " .. table.concat(M.argv(), " ") .. " (dry run)")
    M.feed("(dry run: this log is canned, nothing is being built)")
    play_canned()
    return true
  end
  local started, why = morf.process.spawn {
    command = M.argv(),
    on_stdout = function(line) if own == generation then M.feed(line) end end,
    on_stderr = function(line) if own == generation then M.feed(line) end end,
    on_exit = function(code) if own == generation then finish(code) end end,
  }
  if not started then
    M.state:set("failed")
    M.message:set(tostring(why))
    return false
  end
  child = started
  return true
end

--- Stops the rebuild, as far as it has come.
function M.cancel()
  if M.state:get() ~= "running" then return false end
  generation = generation + 1
  if child then child:kill("TERM") end
  child = nil
  if canned_timer then canned_timer:cancel() end
  canned_timer = nil
  M.feed("(stopped)")
  M.state:set("failed")
  M.message:set("The rebuild was stopped")
  return true
end

--- Reads what there is to read: `done()` once the managers have answered.
function M.start(done)
  M.nixos:set(exists(M.root .. "/run/current-system") or exists(M.root .. "/etc/NIXOS"))
  if M.nixos:get() then M.read_flake() end
  M.check_managers(done)
end

--- `eva-update --check`: how many wait, as a number. `done(text, why)`.
function M.job(args, done)
  if args[1] ~= "--check" then done(nil, "no such option: " .. tostring(args[1])) return end
  M.start(function() done(tostring(M.pending())) end)
end

return M
