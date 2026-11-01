-- Who is using the microphone, the camera, the screen and the location. No
-- nodes.
--
-- A user is `{ app, pid, via }`. The microphone is read from the sound server's
-- streams. The camera and the screen come from PipeWire's graph: a video stream
-- reading a camera node is a camera in use, one reading any other video source
-- is the screen being shared (a portal's stream has no device). A program that
-- opens /dev/video itself is found through /proc, which shows the person's own
-- processes without root; a kernel module's use count says when that is worth
-- a look. Hyprland's screencast event and GeoClue's InUse cover the rest.
--
-- EVA_FAKE_PRIVACY="mic:Firefox,camera:Zoom,screen:OBS,location:Maps" stands in
-- for all of it, and `morf ipc call fake-privacy SPEC` moves it.
local morf = require("morf")

local M = { KINDS = { "mic", "camera", "screen", "location" } }

M.NAMES = { mic = "Microphone", camera = "Camera", screen = "Screen sharing", location = "Location" }
M.ICONS = { mic = "mic", camera = "videocam", screen = "screen_share", location = "location_on" }

-- Brokers that hold a camera on behalf of the programs PipeWire names.
local BROKERS = { pipewire = true, wireplumber = true, ["pipewire-media-session"] = true }
local CAMERA_APIS = { v4l2 = true, libcamera = true, ["libcamera.client"] = true }
local HISTORY = 20
local USE_COUNT = "/sys/module/uvcvideo/refcnt"
local SCAN_MS, SETTLE_MS = 4000, 250

local function props_of(object) return ((object or {}).info or {}).props or {} end

local function is_camera(props)
  return CAMERA_APIS[props["device.api"]] == true or props["media.role"] == "Camera"
    or tostring(props["node.name"] or ""):match("^v4l2_") ~= nil
    or tostring(props["node.name"] or ""):match("^libcamera") ~= nil
end

local function app_of(props)
  for _, key in ipairs { "application.name", "node.description", "application.process.binary", "media.name", "node.name" } do
    local value = props[key]
    if type(value) == "string" and value ~= "" then return value end
  end
  return "An app"
end

--- A `pw-dump` as `{ camera, screen }`, each a list of users.
function M.parse_pipewire(objects)
  local nodes, links = {}, {}
  for _, object in ipairs(type(objects) == "table" and objects or {}) do
    if object.type == "PipeWire:Interface:Node" then nodes[object.id] = object
    elseif object.type == "PipeWire:Interface:Link" then links[#links + 1] = object.info or {} end
  end
  local out = { camera = {}, screen = {} }
  for id, node in pairs(nodes) do
    local props = props_of(node)
    if props["media.class"] == "Stream/Input/Video" then
      local source
      for _, link in ipairs(links) do
        if link["input-node-id"] == id then source = nodes[link["output-node-id"]] end
      end
      -- Unlinked, a stream is a program that is not reading anything yet.
      if source then
        local kind = is_camera(props_of(source)) and "camera" or "screen"
        out[kind][#out[kind] + 1] = { app = app_of(props), pid = props["application.process.id"], via = "pipewire" }
      end
    end
  end
  for _, kind in ipairs { "camera", "screen" } do
    table.sort(out[kind], function(a, b) return a.app < b.app end)
  end
  return out
end

--- `.../PID/fd/N` paths as a list of pids, each once.
function M.parse_holders(text)
  local out, seen = {}, {}
  for pid in tostring(text or ""):gmatch("/(%d+)/fd/%d+") do
    if not seen[pid] then seen[pid] = true out[#out + 1] = tonumber(pid) end
  end
  return out
end

--- A process's name, from `/proc/PID/comm`.
function M.process_name(pid, proc)
  local ok, text = pcall(morf.fs.read, (proc or "/proc") .. "/" .. pid .. "/comm")
  return ok and type(text) == "string" and text:match("^%s*(.-)%s*$") or nil
end

-- The stand-in's words as users: "mic:Firefox,camera:Zoom".
local function fake_users(spec)
  local out = { mic = {}, camera = {}, screen = {}, location = {} }
  for kind, app in tostring(spec or ""):gmatch("(%a+):([^,]+)") do
    if out[kind] then out[kind][#out[kind] + 1] = { app = app, via = "stand-in" } end
  end
  return out
end

-- The sound server's recording streams, the shell's own monitors aside.
local function microphone()
  local out = {}
  pcall(function()
    local audio = morf.audio
    if not (audio and audio.available() and audio.streams) then return end
    for i = 1, audio.streams:len() do
      local row = audio.streams:get(i)
      if row.direction == "record" and not (row.app_id or ""):match("^morf%.") then
        out[#out + 1] = { app = row.app_name ~= "" and row.app_name or row.binary or "An app", pid = row.pid, id = row.id,
          via = "pipewire" }
      end
    end
  end)
  return out
end

--- The model. `opts` are its seams: `run` (for `morf.process.run`), `spawn`
--- (for `morf.process.spawn`), `proc`, `pattern` (what a held device's path
--- looks like, for `find -lname`), `use_count` (a path), `client` (a D-Bus
--- client on the system bus), `hyprland`, `mic` (the microphone's users).
function M.new(opts)
  opts = opts or {}
  local run = opts.run or morf.process.run
  local spawn = opts.spawn or morf.process.spawn
  local proc = opts.proc or "/proc"
  local pattern = opts.pattern or "/dev/video*"
  local use_count = opts.use_count or USE_COUNT
  local stand_in = opts.fake or (morf.env and morf.env("EVA_FAKE_PRIVACY")) or nil
  if stand_in == "" or stand_in == "0" then stand_in = nil end

  local model = {}
  local graph = morf.signal("eva.privacy.graph", { camera = {}, screen = {} })
  local held = morf.signal("eva.privacy.held", {})
  local casting = morf.signal("eva.privacy.casting", false)
  local located = morf.signal("eva.privacy.located", false)
  local faked = morf.signal("eva.privacy.fake", fake_users(stand_in))
  local history = morf.signal("eva.privacy.history", {})

  --- What the graph says now, asked of `pw-dump`.
  function model.refresh(done)
    if stand_in then return end
    run({ "pw-dump" }, { timeout_ms = 3000 }, function(result)
      if result and result.ok then
        local ok, objects = pcall(morf.json.decode, result.stdout or "")
        if ok then graph:set(M.parse_pipewire(objects)) end
      end
      if done then done() end
    end)
  end

  --- Who holds a camera node open, asked of `find`.
  function model.scan(done)
    if stand_in then return end
    run({ "find", proc, "-mindepth", "3", "-maxdepth", "3", "-path", proc .. "/[0-9]*/fd/*", "-lname", pattern },
      { timeout_ms = 3000 }, function(result)
        local rows = {}
        for _, pid in ipairs(M.parse_holders(result and result.stdout)) do
          local name = M.process_name(pid, proc)
          if name and not BROKERS[name] then rows[#rows + 1] = { app = name, pid = pid, via = "device" } end
        end
        held:set(rows)
        if done then done() end
      end)
  end

  -- The kernel's use count of the camera driver moves on any open, so /proc
  -- is walked only then; without the module a walk comes round on the timer.
  local last_count
  local function look()
    local ok, text = pcall(morf.fs.read, use_count)
    local count = ok and type(text) == "string" and tonumber(text:match("%d+")) or nil
    if count == nil or count ~= last_count then
      last_count = count
      model.scan()
    end
  end

  --- `users(kind)`: a tracked read of who is using it.
  function model.users(kind)
    local fake = faked:get()
    if stand_in then return fake[kind] or {} end
    if kind == "mic" then return (opts.mic or microphone)() end
    if kind == "location" then return located:get() and { { app = "An app", via = "geoclue" } } or {} end
    local out, seen = {}, {}
    for _, user in ipairs(graph:get()[kind] or {}) do
      out[#out + 1] = user
      if user.pid then seen[user.pid] = true end
    end
    if kind == "camera" then
      for _, user in ipairs(held:get()) do
        if not seen[user.pid] then out[#out + 1] = user end
      end
    end
    if kind == "screen" and #out == 0 and casting:get() then
      out[1] = { app = "A program", via = "compositor" }
    end
    return out
  end

  --- Whether `kind` is in use.
  function model.in_use(kind) return #model.users(kind) > 0 end

  --- Every kind in use, as `{ kind, name, icon, users }`.
  function model.rows()
    local out = {}
    for _, kind in ipairs(M.KINDS) do
      local users = model.users(kind)
      if #users > 0 then
        out[#out + 1] = { kind = kind, name = M.NAMES[kind], icon = M.ICONS[kind], users = users }
      end
    end
    return out
  end

  --- `Camera: Zoom, Firefox`, for each kind in use.
  function model.summary()
    local lines = {}
    for _, row in ipairs(model.rows()) do
      local apps = {}
      for i, user in ipairs(row.users) do apps[i] = user.app end
      lines[#lines + 1] = row.name .. ": " .. table.concat(apps, ", ")
    end
    return lines
  end

  --- What was in use and has stopped, latest first: `{ kind, app, ended }`.
  function model.history() return history:get() end

  -- A user that goes is written down.
  local before = {}
  local function record()
    local now = {}
    for _, kind in ipairs(M.KINDS) do
      for _, user in ipairs(model.users(kind)) do now[kind .. ":" .. user.app] = { kind = kind, app = user.app } end
    end
    local log
    for key, user in pairs(before) do
      if not now[key] then
        log = log or { table.unpack(history:get()) }
        table.insert(log, 1, { kind = user.kind, app = user.app, ended = morf.time.now() })
        log[HISTORY + 1] = nil
      end
    end
    before = now
    if log then morf.time.timer(1, function() history:set(log) end, false) end
  end

  local watcher, ticker, settle, started

  local function changed()
    if settle then return end
    settle = morf.time.timer(SETTLE_MS, function() settle = nil model.refresh() end, false)
  end

  local function follow_graph()
    local child = spawn { command = { "pw-dump", "--monitor", "--no-colors" },
      on_stdout = changed, on_exit = function() watcher = nil end }
    watcher = child or nil
  end

  local function follow_compositor()
    local h = opts.hyprland or require("lib.compositor.hyprland")
    if not (h and h.available and h.available() and h.on) then return end
    pcall(h.on, "screencast", function(data)
      casting:set(tostring(data or ""):match("^1") ~= nil)
      changed()
    end)
  end

  local function follow_location()
    local ok, client = pcall(function()
      return opts.client or require("lib.services.dbus").new { bus = "system" }
    end)
    if not ok or not client then return end
    local NAME, PATH, IFACE = "org.freedesktop.GeoClue2", "/org/freedesktop/GeoClue2/Manager", "org.freedesktop.GeoClue2.Manager"
    local listening = false
    local function read()
      local up, value = pcall(client.get, NAME, PATH, IFACE, "InUse")
      located:set(up and value == true)
      if listening then return end
      listening = true
      pcall(client.on_properties, NAME, PATH, function(interface, changes)
        if interface == IFACE and type(changes) == "table" and changes.InUse ~= nil then located:set(changes.InUse == true) end
      end)
    end
    -- Only a GeoClue that is running: asking would start one.
    pcall(client.watch_name, NAME, function(present)
      if present then read() else located:set(false) end
    end)
    if select(2, pcall(client.has_owner, NAME)) == true then read() end
  end

  --- Starts following the machine. Once only, outside an effect.
  function model.start()
    if started then return end
    started = true
    if stand_in then
      morf.ipc["fake-privacy"] = function(spec) faked:set(fake_users(spec)) return true end
    else
      model.refresh()
      look()
      pcall(follow_graph)
      pcall(follow_compositor)
      pcall(follow_location)
      ticker = morf.time.timer(SCAN_MS, look, true)
    end
    morf.effect("eva.privacy.history", record)
  end

  --- Stops following it.
  function model.stop()
    if ticker then ticker:cancel() ticker = nil end
    if watcher and watcher.kill then pcall(watcher.kill, watcher) watcher = nil end
    started = false
  end

  return model
end

local shared

--- The shell's one model, built the first time it is asked for.
function M.shared()
  if not shared then shared = M.new() end
  return shared
end

return M
