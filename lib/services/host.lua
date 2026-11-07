-- The machine as the Settings pages reach it: commands, the two buses, and
-- what kind of system this is.
--
--   local host = require("lib.services.host")
--   host.read({ "lpstat", "-p" }, function(text, why) end)   -- asks, changes nothing
--   host.act({ "lpadmin", "-x", "office" }, function(ok, why) end)
--   host.bus("system")                                       -- a lib.services.dbus client
--
-- `act` changes the machine: under EVA_DRY_RUN it logs and answers yes. Under
-- EVA_FAKE_SYSTEM commands and buses are lib/services/host_fake.lua's, and the
-- service code above them runs unchanged. A secret goes in `options.stdin` or
-- over a bus, and neither is ever logged.
local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local M = {}

local function flag(name)
  local value = morf.env and morf.env(name)
  return value ~= nil and value ~= false and value ~= "" and value ~= "0"
end

function M.dry() return flag("EVA_DRY_RUN") end
function M.fake() return flag("EVA_FAKE_SYSTEM") end

local function stand_in() return M.fake() and require("lib.services.host_fake") or nil end

local clients = {}

--- A client for "system" or "session".
function M.bus(kind)
  if not clients[kind] then
    local fake = stand_in()
    clients[kind] = dbus_client.new { bus = kind, dbus = fake and fake.dbus or nil }
  end
  return clients[kind]
end

--- Whether `program` is on PATH, or `/sbin` and the like.
function M.installed(program)
  local fake = stand_in()
  if fake then return fake.installed(program) end
  for dir in ((morf.env("PATH") or "") .. ":/usr/bin:/usr/local/bin:/usr/sbin:/sbin"):gmatch("[^:]+") do
    if morf.fs.exists(dir .. "/" .. program) then return true end
  end
  return false
end

--- Whether this is NixOS, where much of /etc is built from a configuration.
function M.nixos()
  local fake = stand_in()
  if fake then return fake.nixos() end
  return morf.fs.exists("/etc/NIXOS")
end

--- Where the symlink at `path` points, or nil.
local function link(path)
  local ok, target = pcall(morf.fs.read_link, path)
  return ok and type(target) == "string" and target or nil
end

--- Whether the file at `path` is the system configuration's to write: on
--- NixOS, a link into the store or /etc/static.
function M.declared(path)
  local fake = stand_in()
  if fake then return fake.declared(path) end
  if not M.nixos() then return false end
  local target = link(path)
  return target ~= nil and (target:find("^/nix/store/") ~= nil or target:find("^/etc/static/") ~= nil
    or target:find("^/etc/zoneinfo/") ~= nil)
end

--- Whether a user file is a Home Manager link: a change to it would be lost.
function M.managed(path)
  local fake = stand_in()
  if fake then return fake.managed(path) end
  local target = link(path)
  return target ~= nil and target:find("^/nix/store/") ~= nil
end

local function finish(result, done)
  if result and result.ok then return done(result.stdout or "") end
  local why = result and (result.error or (result.stderr ~= "" and result.stderr) or result.code) or "no answer"
  done(nil, (tostring(why):gsub("%s+$", "")))
end

local function run(argv, done, options)
  local fake = stand_in()
  if fake then
    local result = fake.run(argv, options)
    return morf.time.timer(1, function() finish(result, done) end, false)
  end
  morf.process.run(argv, options or {}, function(result) finish(result, done) end)
end

--- Runs a command that only asks: `done(stdout)` or `done(nil, why)`.
function M.read(argv, done, options) return run(argv, done or function() end, options) end

--- Runs a command that changes the machine: `done(stdout)` or `done(nil, why)`.
function M.act(argv, done, options)
  done = done or function() end
  if M.dry() then
    morf.log("info", "eva: " .. table.concat(argv, " ") .. " (dry run)")
    return morf.time.timer(1, function() done("") end, false)
  end
  return run(argv, done, options)
end

--- Asks a server: `spec` as morf.http.request takes it, `done(response)`. Gives
--- what `cancel` stops it. The stand-in machine answers for itself, and a
--- headless run reaches no network at all.
function M.http(spec, done)
  local fake = stand_in()
  local answer = fake and fake.http(spec)
  if not answer and morf.capabilities and morf.capabilities.headless then
    answer = { ok = false, status = 0, error = "No network in a headless run" }
  end
  if answer then return morf.time.timer(1, function() done(answer) end, false) end
  spec.on_done = done
  return morf.http.request(spec)
end

--- Whether a change should stop short of the machine: logs when it does.
function M.held(what)
  if not M.dry() then return false end
  morf.log("info", "eva: " .. what .. " (dry run)")
  return true
end

--- Where the shell's tools are: `apps/` beside the shell, or nil when
--- installed only on PATH.
local function apps_dir()
  local ok, root = pcall(morf.paths.shell, "../apps")
  return ok and root and morf.fs.is_dir(root) and root or nil
end

--- How to start the tool `name` of apps/ (`displays`, `update`, `info`), or
--- nil when this install does not have it: its command, else its program.
function M.tool(name)
  local fake = stand_in()
  if fake then return fake.tool(name) end
  local root = apps_dir()
  if root and morf.fs.exists(root .. "/" .. name .. "/cli") then return { "sh", root .. "/" .. name .. "/cli" } end
  if root and morf.fs.exists(root .. "/" .. name .. "/app.lua") then return { "sh", root .. "/launch", name } end
  if M.installed("eva-" .. name) then return { "eva-" .. name } end
  return nil
end

--- Where the running shell shows a tool itself, on a page of its own windows:
--- `(name, args)`, true when it did. The shell sets it; nil elsewhere.
M.in_shell = nil

--- Opens a tool, with `args` if any: on its page where the shell shows it,
--- else started on its own. True once it is on its way.
function M.open_tool(name, args)
  if M.in_shell and M.in_shell(name, args) then return true end
  return M.start_tool(name, args)
end

--- Starts a tool's own program with `args`, past any page of it: an overlay
--- that draws over the whole screen. True once it is on its way.
function M.start_tool(name, args)
  local argv = M.tool(name)
  if not argv then return false end
  if M.held(table.concat({ "open", name, table.unpack(args or {}) }, " ")) or M.fake() then return true end
  local command = {}
  for _, word in ipairs(argv) do command[#command + 1] = word end
  for _, word in ipairs(args or {}) do command[#command + 1] = word end
  local child = morf.process.spawn { command = command, detached = true }
  return child ~= nil and child ~= false
end

return M
