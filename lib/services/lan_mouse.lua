-- lan-mouse, one mouse and keyboard across machines, through its daemon's
-- socket ($XDG_RUNTIME_DIR/lan-mouse-socket.sock, a JSON object a line each
-- way): this machine's fingerprint, the machines it reaches, those allowed to
-- reach it and those asking to, and the changes to make. The daemon saves its
-- own configuration after each change. Its user service is started and
-- stopped with systemctl. Under EVA_FAKE_SYSTEM a stand-in daemon answers
-- (lib/services/lan_mouse_fake.lua); under EVA_DRY_RUN nothing is sent.
--
--   local mouse = require("lib.services.lan_mouse")
--   mouse.watch(active)               -- connected while `active()` holds
--   mouse.get().clients               -- { handle, hostname, pos, active, alive, ips }
--   mouse.add("laptop", "right")
local morf = require("morf")
local host = require("lib.services.host")

local M = {}

local SERVICE = "lan-mouse.service"
-- Handles past this are the daemon's own, for machines that came in.
local OWN = 2 ^ 53

local now = { service = "", up = false, port = 4242, fingerprint = "", clients = {}, allowed = {}, asking = {},
  capture = true, emulation = true, error = "" }
local revision = morf.signal("eva.lan_mouse.revision", 0)
local count = 0
local function changed() count = count + 1 revision:set(count) end

--- What the daemon holds, read like a signal.
function M.get()
  revision:get()
  return now
end

--- Whether lan-mouse is on this machine at all.
function M.installed() return host.installed("lan-mouse") end

-- ------------------------------------------------------------------ events --

local pending = {}

local function client(handle, config, state)
  return { handle = handle, hostname = config.hostname or "", port = config.port or 4242, pos = config.pos or "left",
    ips = state.ips or {}, active = state.active == true, alive = state.alive == true }
end

local function put(handle, config, state)
  if type(handle) ~= "number" or handle >= OWN then return end
  local row = client(handle, config or {}, state or {})
  for i, c in ipairs(now.clients) do
    if c.handle == handle then now.clients[i] = row return end
  end
  now.clients[#now.clients + 1] = row
  table.sort(now.clients, function(a, b) return a.handle < b.handle end)
end

local send

--- One event from the daemon, decoded.
function M.apply(event)
  if type(event) ~= "table" then return end
  local name, body = next(event)
  if name == "Enumerate" then
    now.clients = {}
    for _, row in ipairs(body or {}) do put(row[1], row[2], row[3]) end
  elseif name == "Created" or name == "State" then
    put(body[1], body[2], body[3])
    local wanted = name == "Created" and table.remove(pending, 1)
    if wanted then
      send { UpdateHostname = { body[1], wanted.hostname } }
      send { UpdatePosition = { body[1], wanted.pos } }
      send { Activate = { body[1], true } }
    end
  elseif name == "Deleted" then
    for i, c in ipairs(now.clients) do if c.handle == body then table.remove(now.clients, i) break end end
  elseif name == "PortChanged" then
    now.port = body[1] or now.port
    now.error = body[2] or ""
  elseif name == "PublicKeyFingerprint" then
    now.fingerprint = body or ""
  elseif name == "AuthorizedUpdated" then
    now.allowed = {}
    for fingerprint, said in pairs(body or {}) do now.allowed[#now.allowed + 1] = { fingerprint = fingerprint, name = said } end
    table.sort(now.allowed, function(a, b) return a.name < b.name end)
    local asking = {}
    for _, fingerprint in ipairs(now.asking) do if not (body or {})[fingerprint] then asking[#asking + 1] = fingerprint end end
    now.asking = asking
  elseif name == "ConnectionAttempt" then
    local fingerprint = body and body.fingerprint
    if fingerprint then
      for _, seen in ipairs(now.asking) do if seen == fingerprint then return end end
      now.asking[#now.asking + 1] = fingerprint
    end
  elseif name == "CaptureStatus" then
    now.capture = body == "Enabled"
  elseif name == "EmulationStatus" then
    now.emulation = body == "Enabled"
  elseif name == "Error" then
    now.error = tostring(body or "")
  end
  changed()
end

-- -------------------------------------------------------------- the socket --

local link, watching, retry

local function path() return (morf.env("XDG_RUNTIME_DIR") or "") .. "/lan-mouse-socket.sock" end

local function closed()
  link = nil
  if now.up then now.up = false changed() end
end

local function connect()
  if link then return end
  local on_line = function(line)
    local ok, event = pcall(morf.json.decode, line)
    if ok then M.apply(event) end
  end
  if host.fake() then
    link = require("lib.services.lan_mouse_fake").connect(on_line)
    now.up = true
    changed()
    link:send(morf.json.encode("Sync") .. "\n")
    return
  end
  link = morf.socket.connect { path = path(), connect_timeout_ms = 1500, max_line = 1024 * 1024,
    on_connect = function()
      now.up = true
      changed()
      link:send(morf.json.encode("Sync") .. "\n")
    end,
    on_line = on_line,
    on_close = closed }
end

--- A request to the daemon, a table as its JSON takes it. Gives whether it went.
function send(request)
  if not link then return false end
  if host.dry() and not host.fake() then
    morf.log("info", "eva: lan-mouse " .. morf.json.encode(request) .. " (dry run)")
    return true
  end
  link:send(morf.json.encode(request) .. "\n")
  return true
end
M.send = send

-- --------------------------------------------------------------- service --

local function read_service(done)
  if host.fake() then
    now.service = require("lib.services.lan_mouse_fake").running() and "active" or "inactive"
    changed()
    if done then done() end
    return
  end
  host.read({ "systemctl", "--user", "is-active", SERVICE }, function(text)
    now.service = (text or "inactive"):match("^%s*(%S+)") or "inactive"
    changed()
    if done then done() end
  end)
end

local function follow()
  if not watching then return end
  read_service(function()
    if now.service == "active" then connect() elseif link then link:close() closed() end
  end)
end

--- Keeps to the daemon while `active()` holds: its service read, its socket
--- held, a try every two seconds while it does not answer.
function M.watch(active)
  morf.effect("eva.lan_mouse.watch", function()
    watching = active() == true
    if retry then retry:cancel() retry = nil end
    if not watching then
      if link then link:close() closed() end
      return
    end
    morf.time.timer(1, follow, false)
    retry = morf.time.timer(2000, function() if not now.up then follow() end end, true)
  end)
end

--- Starts or stops the daemon's user service; `done(ok, why)`.
function M.run(on, done)
  local function after(ok, why)
    morf.time.timer(400, follow, false)
    if done then done(ok, why) end
  end
  if host.fake() then
    require("lib.services.lan_mouse_fake").set_running(on)
    if not on and link then link:close() closed() end
    return after(true)
  end
  host.act({ "systemctl", "--user", on and "start" or "stop", SERVICE }, function(ok, why) after(ok ~= nil, why) end)
end

-- -------------------------------------------------------------- changes --

--- A machine to reach by `hostname` (or address), standing at `pos` (left,
--- right, top or bottom): made, named, placed and turned on.
function M.add(hostname, pos)
  if not link then return false end
  pending[#pending + 1] = { hostname = hostname, pos = pos }
  return send("Create")
end

function M.activate(handle, on) return send { Activate = { handle, on == true } } end
function M.remove(handle) return send { Delete = handle } end
function M.place(handle, pos) return send { UpdatePosition = { handle, pos } } end
function M.allow(fingerprint, name) return send { AuthorizeKey = { name, fingerprint } } end
function M.forget(fingerprint) return send { RemoveAuthorizedKey = fingerprint } end
function M.retake() return send("EnableCapture") and send("EnableEmulation") end

--- Leaves a machine that asked unanswered, and out of the list.
function M.dismiss(fingerprint)
  for i, seen in ipairs(now.asking) do
    if seen == fingerprint then table.remove(now.asking, i) changed() return end
  end
end

-- ------------------------------------------------------------ release keys --

local KEYS = { KeyLeftCtrl = "Ctrl", KeyRightCtrl = "Ctrl", KeyLeftShift = "Shift", KeyRightShift = "Shift",
  KeyLeftMeta = "Super", KeyRightMeta = "Super", KeyLeftAlt = "Alt", KeyRightAlt = "AltGr" }

--- The keys that bring the pointer back here, in words: "Ctrl, Shift, Super
--- and Alt" unless the configuration names others.
function M.release_keys()
  local home = morf.env("XDG_CONFIG_HOME")
  if not home or home == "" then home = (morf.env("HOME") or "") .. "/.config" end
  local ok, text = pcall(morf.fs.read, home .. "/lan-mouse/config.toml")
  local list = ok and type(text) == "string" and text:match("release_bind%s*=%s*(%b[])")
  local names = {}
  for key in (list or "[ \"KeyLeftCtrl\", \"KeyLeftShift\", \"KeyLeftMeta\", \"KeyLeftAlt\" ]"):gmatch("\"(%w+)\"") do
    names[#names + 1] = KEYS[key] or key:gsub("^Key", "")
  end
  if #names < 2 then return names[1] or "" end
  return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

return M
