-- The machine's people: the accounts a login screen lists, and the picture
-- each keeps of itself.
--
--   local accounts = require("lib.services.accounts")
--   for _, a in ipairs(accounts.list()) do print(a.name, a.label, a.face) end
--   local me = accounts.me()          -- whoever runs this, listed or not
--
-- Read straight out of /etc/passwd: the file is world-readable and the
-- authority, and a login screen that cannot list anybody because a daemon is
-- not running is worse than one that reads a file. Below uid 1000 is the
-- system's own, 65534 is `nobody`, and a shell that cannot be logged into is
-- an account that cannot log in.

local morf = require("morf")
local unicase = require("lib.util.unicase")

local accounts = {}

--- The picture an account keeps of itself, if it keeps one: what
--- AccountsService holds for it, else the `.face` in its home.
function accounts.face(name, home)
  home = home or ("/home/" .. name)
  for _, path in ipairs {
    "/var/lib/AccountsService/icons/" .. name,
    home .. "/.face",
    home .. "/.face.icon",
  } do
    if morf.fs.exists(path) then return path end
  end
  return nil
end

local function entry(name, gecos, home)
  local label = (gecos and gecos ~= "" and gecos:match("^[^,]*")) or name
  if label == "" then label = name end
  return {
    name = name,
    label = label,
    initial = unicase.upper(unicase.first(label)),
    home = home or ("/home/" .. name),
    face = accounts.face(name, home),
  }
end

--- Ordinary human accounts, by name: `{ name, label, initial, home, face }`.
function accounts.list(path)
  local found = {}
  local ok, text = pcall(morf.fs.read, path or "/etc/passwd")
  if not ok or type(text) ~= "string" then return found end
  for line in text:gmatch("[^\n]+") do
    local name, uid, gecos, home, shell = line:match("^([^:]+):[^:]*:(%d+):[^:]*:([^:]*):([^:]*):([^:]*)$")
    local id = tonumber(uid or "")
    if name and id and id >= 1000 and id < 65534
      and not (shell:match("nologin$") or shell:match("/false$")) then
      found[#found + 1] = entry(name, gecos, home)
    end
  end
  table.sort(found, function(a, b) return a.name < b.name end)
  return found
end

--- Whoever runs this: from the list when there, made up from `$USER`
--- otherwise -- a lock asks exactly this person.
function accounts.me()
  local me = morf.env("USER") or morf.env("LOGNAME") or ""
  for _, a in ipairs(accounts.list()) do
    if a.name == me then return a end
  end
  if me == "" then return nil end
  return entry(me, nil, morf.fs.home())
end

--- The names in a group file's `wheel`, `sudo` and `admin` lines, as a set.
function accounts.administrators(path)
  local out = {}
  local ok, text = pcall(morf.fs.read, path or "/etc/group")
  if not ok or type(text) ~= "string" then return out end
  for line in text:gmatch("[^\n]+") do
    local group, members = line:match("^([^:]+):[^:]*:%d+:(.*)$")
    if group == "wheel" or group == "sudo" or group == "admin" then
      for name in members:gmatch("[^,]+") do out[name] = true end
    end
  end
  return out
end

local ACCOUNTS, ACCOUNTS_PATH = "org.freedesktop.Accounts", "/org/freedesktop/Accounts"
local USER = ACCOUNTS .. ".User"

--- The picture `source` as `<home>/.face`, square, which the lock screen and
--- the greeter read; AccountsService told too where it runs. `done(path, why)`.
function accounts.set_face(me, source, done)
  local host = require("lib.services.host")
  local target = me.home .. "/.face"
  if host.held("set face from " .. source) then return done(target) end
  local client = host.bus("system")
  local function tell_service()
    if not client.has_owner(ACCOUNTS) then return done(target) end
    client.call1_async(ACCOUNTS, ACCOUNTS_PATH, ACCOUNTS, "FindUserByName", { me.name }, 5000, function(path)
      if type(path) ~= "string" then return done(target) end
      client.call_async(ACCOUNTS, path, USER, "SetIconFile", { target }, 25000, function() done(target) end)
    end)
  end
  local ok, info = pcall(morf.image.info, source)
  local width, height = ok and type(info) == "table" and info.width, ok and type(info) == "table" and info.height
  if not (width and height) then
    local copied, why = pcall(morf.fs.copy, source, target)
    if not copied then return done(nil, tostring(why)) end
    return tell_service()
  end
  local side = math.min(width, height)
  local queued, failed = pcall(morf.image.process, { source = source, output = target .. ".png",
    ops = { { "crop", (width - side) // 2, (height - side) // 2, side, side }, { "resize", 256, 256 } },
    on_done = function(done_ok, result)
      if not done_ok then return done(nil, tostring(type(result) == "table" and result.error or result)) end
      local moved, why = pcall(morf.fs.rename, target .. ".png", target)
      if not moved then return done(nil, tostring(why)) end
      tell_service()
    end })
  if not queued then done(nil, tostring(failed)) end
end

--- Changes the name shown for this account, where AccountsService runs.
--- `done(ok, why)`.
function accounts.set_label(me, label, done)
  local host = require("lib.services.host")
  if host.held("set real name") then return done(true) end
  local client = host.bus("system")
  if not client.has_owner(ACCOUNTS) then return done(nil, "AccountsService is not running here") end
  client.call1_async(ACCOUNTS, ACCOUNTS_PATH, ACCOUNTS, "FindUserByName", { me.name }, 5000, function(path, why)
    if type(path) ~= "string" then return done(nil, why) end
    client.call_async(ACCOUNTS, path, USER, "SetRealName", { label }, 25000, done)
  end)
end

return accounts
