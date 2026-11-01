-- What the hardware tiles drive, each device with one face: `present()`,
-- `on()`, `set(on)` and `status()`. Each connects the first time it is asked
-- for. Dry (EVA_DRY_RUN) nothing reaches the machine: an action is logged and
-- only the tile's own state moves. EVA_FAKE_HARDWARE=1 stands in for every
-- device, to see them where the machine or the session has none.
local morf = require("morf")
local config = require("config")
local M = {}

local function flag(name)
  local v = morf.env and morf.env(name)
  return v ~= nil and v ~= false and v ~= "" and v ~= "0"
end
local function dry() return flag("EVA_DRY_RUN") end
local function fake() return flag("EVA_FAKE_HARDWARE") end
local function primary() return not morf.window.primary or morf.window.primary() end
local function log(what) morf.log("info", "eva: " .. what .. " (dry run)") end
local function lazily(build)
  local made
  return function()
    if made == nil then made = build() end
    return made
  end
end
local function services() return require("services") end
local function installed(program)
  local check = services().installed
  return check ~= nil and check(program) == true
end
-- A command for the machine: dry or faked, logged and taken as done.
local function run(argv, done)
  done = done or function() end
  if dry() or fake() then
    log(table.concat(argv, " "))
    done({ ok = true, stdout = "" })
    return
  end
  local ok = pcall(morf.process.run, argv, { timeout_ms = 60000 }, done)
  if not ok then done({ ok = false }) end
end
-- What a device looks at again each time the tiles come on show.
local checks = {}
--- Looks again at what is read rather than watched.
function M.refresh()
  for _, check in ipairs(checks) do pcall(check) end
end

-- ---------------------------------------------------------------- hotspot --

M.hotspot = lazily(function()
  local lib = require("lib.services.hotspot")
  local net = services().net
  local real = not fake() and net and net.snapshot and lib.new(net) or nil
  local standing = morf.signal("eva.hotspot.standing", false)
  local name = morf.signal("eva.hotspot.name", "")
  local h = { message = morf.signal("eva.hotspot.message", ""), MIN_PASSWORD = lib.MIN_PASSWORD }

  local function active() return real and real.active() end

  function h.present()
    if fake() then return true end
    if not (real and net.state.available) then return false end
    net.state.devices:len()
    return real.device() ~= nil
  end

  --- The profile's network name, or the machine's.
  function h.ssid()
    local row = real and real.profile()
    if row and (row.ssid or "") ~= "" then return row.ssid end
    if name:get() ~= "" then return name:get() end
    local ok, host = pcall(morf.fs.read, "/proc/sys/kernel/hostname")
    return ok and type(host) == "string" and host:gsub("%s+", "") or "eva"
  end

  --- Whether a profile with its secret is saved.
  function h.saved()
    if real then net.state.devices:len() return real.profile() ~= nil end
    return name:get() ~= ""
  end

  function h.on()
    if not real or dry() then return standing:get() end
    local row = active()
    return row ~= nil and (row.state == "activated" or row.state == "activating")
  end

  function h.status()
    if not real or dry() then return standing:get() and h.ssid() or "Off" end
    local row = active()
    if row and row.state == "activating" then return "Starting…" end
    if row and row.state == "activated" then return h.ssid() end
    if not net.state.wifi_enabled then return "Wi-Fi is off" end
    return "Off"
  end

  local function said(result, why)
    if result == nil then h.message:set(tostring(why or "It did not start")) end
  end

  function h.set(now)
    h.message:set("")
    if not real or dry() then
      log("hotspot " .. (now and "on" or "off"))
      standing:set(now == true)
      return
    end
    if not now then return real.stop(said) end
    local function start() local ok, why = real.start(said) if not ok then said(nil, why) end end
    if net.state.wifi_enabled then return start() end
    net.set_wifi(true, function(ok, why)
      if not ok then return said(nil, why) end
      morf.time.timer(1500, start, false)
    end)
  end

  --- Saves the name and, when given, the password. `done(ok, why)`.
  function h.save(ssid, password, done)
    h.message:set("")
    local why = lib.check(ssid, password, h.saved())
    if why then done(false, why) return false end
    if not real or dry() then
      log("hotspot saved")
      name:set(ssid)
      done(true)
      return true
    end
    local running = h.on()
    local ok, failed = real.save(ssid, password, function(path, err)
      if not path then return done(false, err) end
      done(true)
      if running then real.stop(function() real.start(said) end) end
    end)
    if not ok then done(false, failed) end
    return ok
  end

  return h
end)

-- --------------------------------------------------------------- rotation --

M.rotation = lazily(function()
  local function nothing() end
  local state = morf.state { accelerometer = true, orientation = "normal", light = true, lux = 180 }
  local sensors = { state = state, claim = nothing, release = nothing, claim_light = nothing, release_light = nothing }
  if not fake() then
    local ok, lib = pcall(require, "lib.services.sensors")
    local connected, reader = false, nil
    if ok then connected, reader = pcall(lib.connect) end
    sensors = connected and reader or { state = morf.state { accelerometer = false, orientation = "undefined",
      light = false, lux = 0 }, claim = nothing, release = nothing, claim_light = nothing, release_light = nothing }
  end
  local r = { sensors = sensors }
  function r.present() return sensors.state.accelerometer == true end
  --- Whether the hinge holds the screen: a convertible open as a laptop.
  function r.hinged()
    return require("models.posture").present() and require("responsive").form_factor() == "desk"
  end
  --- Whether the screen keeps its rotation.
  function r.on()
    local lock = config.get("rotation.lock")
    if lock == "auto" then return require("responsive").form_factor() == "desk" end
    return lock == "on" or r.hinged()
  end
  function r.set(now) config.set("rotation.lock", now and "on" or "off") end
  function r.status()
    if r.hinged() and config.get("rotation.lock") ~= "on" then return "Held by the hinge" end
    return r.on() and "Locked" or "Auto"
  end
  return r
end)

-- ------------------------------------------------------------ night light --

M.nightlight = lazily(function()
  local lib = require("lib.services.nightlight")
  local hyprland = require("lib.compositor.hyprland")
  local night = lib.new {
    run = function(argv, done)
      if dry() or fake() then log(table.concat(argv, " ")) return end
      morf.process.run(argv, {}, done)
    end,
    start = function(temperature)
      hyprland.dispatch("exec", "hyprsunset -t " .. tostring(temperature))
    end,
  }
  local n = { COOLEST = lib.COOLEST, WARMEST = lib.WARMEST, STEP = lib.STEP }
  function n.present()
    if fake() then return true end
    local installed = services().installed
    return hyprland.available() and installed ~= nil and installed("hyprctl") and installed("hyprsunset")
  end
  function n.on() return config.get("nightlight.on") == true end
  function n.set(now) config.set("nightlight.on", now == true) end
  function n.temperature() return tonumber(config.get("nightlight.temperature")) or 4500 end
  function n.set_temperature(value) config.set("nightlight.temperature", lib.clamp(value)) end
  function n.status() return n.on() and ("%d K"):format(n.temperature()) or "Off" end
  --- Whether it follows the sun at the weather's place.
  function n.follow() return config.get("nightlight.follow") == true end
  function n.set_follow(now) config.set("nightlight.follow", now == true) end
  --- Whether there is a place to follow the sun at.
  function n.placed() return lib.where(config) ~= "" end
  --- A command of the tile's and eva-nightlight's, in words.
  function n.command(how, value) return lib.command(n, how, value) end
  morf.effect("eva.nightlight", function()
    local on, temperature = n.on(), n.temperature()
    if primary() and n.present() then night.apply(on, temperature) end
  end)
  -- The sun: looked at on the turn it is asked for, then every few minutes.
  local following
  morf.effect("eva.nightlight.follow", function()
    local follow = n.follow() and primary()
    if following then following:cancel() following = nil end
    if not follow then return end
    local function look()
      lib.decide(n, lib.where(config), function(_, why)
        if why then morf.log("warn", "eva: night light: " .. tostring(why)) end
      end)
    end
    look()
    following = morf.time.timer(lib.EVERY, look, true)
  end)
  return n
end)

-- --------------------------------------------------------------- the torch --

M.torch = lazily(function()
  local lit = morf.signal("eva.torch.standing", false)
  local real
  if not fake() then
    local ok, lib = pcall(require, "lib.services.torch")
    local made, torch = false, nil
    if ok then made, torch = pcall(lib.new) end
    real = made and torch or nil
    if real and not real.device() then real = nil end
  end
  local function level() return math.max(0.05, math.min(1, tonumber(config.get("flashlight.level")) or 1)) end
  if real then real.set_level(level()) end
  local t = {}
  function t.present() return fake() or real ~= nil end
  function t.on() if real and not dry() then return real.on() end return lit:get() end
  function t.set(now)
    if real and not dry() then return real.set(now) end
    log("flashlight " .. (now and "on" or "off"))
    lit:set(now == true)
  end
  --- Whether the LED has a strength to set.
  function t.dims() return fake() or (real ~= nil and real.device().max > 1) end
  --- Its strength, 0 to 1.
  function t.level() return level() end
  function t.set_level(value)
    config.set("flashlight.level", math.max(0.05, math.min(1, tonumber(value) or 1)))
    if real and not dry() then real.set_level(level()) else log(("flashlight at %.2f"):format(level())) end
  end
  function t.status()
    if not t.on() then return "Off" end
    return t.dims() and ("%d%%"):format(math.floor(level() * 100 + 0.5)) or "On"
  end
  return t
end)

-- ------------------------------------------------------------- power saver --

M.power = lazily(function()
  local chosen = morf.signal("eva.powersaver.standing", false)
  local before = "balanced"
  local function profiles()
    local u = services().upower
    local p = u and u.state and u.state.available and u.state.profiles
    return p and p.available and p or nil
  end
  local s = {}
  function s.present()
    if fake() then return true end
    local p = profiles()
    if not (p and p.list) then return false end
    for i = 1, p.list:len() do
      if p.list:get(i).name == "power-saver" then return true end
    end
    return false
  end
  function s.on()
    if fake() or dry() then return chosen:get() end
    local p = profiles()
    return p ~= nil and p.active == "power-saver"
  end
  function s.set(now)
    if fake() or dry() then
      log("power saver " .. (now and "on" or "off"))
      chosen:set(now == true)
      return
    end
    local p, u = profiles(), services().upower
    if not p then return end
    if now and p.active ~= "power-saver" then before = p.active end
    pcall(u.set_profile, now and "power-saver" or before)
  end
  function s.status() return s.on() and "On" or "Off" end
  return s
end)

-- --------------------------------------------------------------------- NFC --

M.nfc = lazily(function()
  local lit = morf.signal("eva.nfc.standing", false)
  local real
  if not fake() then
    local ok, lib = pcall(require, "lib.services.nfc")
    local made, nfc = false, nil
    if ok then made, nfc = pcall(lib.connect) end
    real = made and nfc or nil
  end
  local n = {}
  function n.present() return fake() or (real ~= nil and real.state.available == true) end
  function n.on() if real and not dry() then return real.state.powered == true end return lit:get() end
  function n.set(now)
    if real and not dry() then return real.set(now) end
    log("nfc " .. (now and "on" or "off"))
    lit:set(now == true)
  end
  function n.status() return n.on() and "On" or "Off" end
  return n
end)

-- ------------------------------------------------------------ USB tethering --

M.tether = lazily(function()
  local lib = require("lib.services.hotspot")
  local net = services().net
  local real = not fake() and net and net.snapshot and lib.usb(net) or nil
  local standing = morf.signal("eva.tether.standing", false)
  local t = { message = morf.signal("eva.tether.message", "") }
  local function said(result, why)
    if result == nil then t.message:set(tostring(why or "It did not start")) end
  end
  function t.present()
    if fake() then return true end
    if not (real and net.state.available) then return false end
    net.state.devices:len()
    return real.device() ~= nil
  end
  function t.on()
    if not real or dry() then return standing:get() end
    local row = real.active()
    return row ~= nil and (row.state == "activated" or row.state == "activating")
  end
  function t.set(now)
    t.message:set("")
    if not real or dry() then
      log("usb tethering " .. (now and "on" or "off"))
      standing:set(now == true)
      return
    end
    if not now then return real.stop(said) end
    local ok, why = real.start(said)
    if not ok then said(nil, why) end
  end
  function t.status()
    local message = t.message:get()
    if message ~= "" then return message end
    if not t.on() then return "Off" end
    local row = real and not dry() and real.active()
    return row and row.state == "activating" and "Starting…" or "Sharing"
  end
  return t
end)

-- --------------------------------------------------------------- data saver --

M.datasaver = lazily(function()
  local lib = require("lib.services.datasaver")
  local net = services().net
  local saver = lib.new { run = run, marked = config.get("datasaver.marked"),
    remember = function(list) config.set("datasaver.marked", list) end }
  local d = {}
  -- The connection in use, as an active row.
  local function in_use()
    if not (net and net.state.available) then return nil end
    local path = net.state.primary and net.state.primary.path
    local rows = net.state.active_connections
    for i = 1, path and rows and rows:len() or 0 do
      local row = rows:get(i)
      if row.path == path then return row end
    end
  end
  function d.present() return fake() or (net ~= nil and net.state.available == true and installed("nmcli")) end
  function d.on() return config.get("datasaver.on") == true end
  function d.set(now) config.set("datasaver.on", now == true) end
  function d.status()
    if not d.on() then return "Off" end
    local row = in_use()
    return row and row.id ~= "" and row.id or "On"
  end
  morf.effect("eva.datasaver", function()
    local on = d.on()
    if not on and not saver.marking() then return end
    if primary() and d.present() then saver.follow(on, in_use()) end
  end)
  return d
end)

-- ------------------------------------------------------------ colour filters --

M.filters = lazily(function()
  local lib = require("lib.services.screen_filter")
  local hyprland = require("lib.compositor.hyprland")
  local runtime = morf.env and morf.env("XDG_RUNTIME_DIR") or ""
  local filter = lib.new { hyprland = hyprland, dir = runtime .. "/eva",
    write = function(path, text) morf.fs.write(path, text, { mode = 420, parents = true }) end }
  local f = { ORDER = lib.ORDER, CORRECTIONS = lib.CORRECTIONS }
  local timer
  local function set_now()
    local set = { dim = f.dim(), correction_kind = f.correction() }
    for _, id in ipairs(lib.ORDER) do set[id] = config.get("filters." .. id) == true end
    return set
  end
  function f.present() return fake() or hyprland.available() end
  function f.on(id) return config.get("filters." .. id) == true end
  function f.set(id, now) config.set("filters." .. id, now == true) end
  function f.dim() return math.max(0.1, math.min(0.9, tonumber(config.get("filters.dim")) or 0.4)) end
  function f.set_dim(value) config.set("filters.dim", value) end
  function f.correction() return config.get("filters.correction_kind") or "deuteranopia" end
  function f.set_correction(kind) config.set("filters.correction_kind", kind) end
  function f.status(id) return f.on(id) and "On" or "Off" end
  morf.effect("eva.filters", function()
    local set = set_now()
    if not primary() then return end
    if timer then timer:cancel() end
    timer = morf.time.timer(120, function()
      timer = nil
      if dry() or fake() then return log("screen filter " .. lib.key(set)) end
      if hyprland.available() then filter.apply(set) end
    end, false)
  end)
  if hyprland.on then
    pcall(hyprland.on, "configreloaded", function()
      if primary() and not dry() and not fake() then filter.again(set_now()) end
    end)
  end
  return f
end)

-- --------------------------------------------------------- automatic brightness --

M.autobrightness = lazily(function()
  local sensors = M.rotation().sensors
  local lib = require("lib.services.sensors")
  local a = {}
  local claimed, shown, timer = false, nil, nil
  function a.present() return fake() or sensors.state.light == true end
  function a.on() return config.get("autobrightness.on") == true end
  function a.set(now) config.set("autobrightness.on", now == true) end
  function a.status()
    if not a.on() then return "Off" end
    return ("%d lx"):format(math.floor((tonumber(sensors.state.lux) or 0) + 0.5))
  end
  -- A level is carried out once the light has held still a moment.
  local function follow(lux)
    local level = lib.brightness_for(lux)
    if shown and math.abs(level - shown) < lib.BRIGHTNESS_STEP then
      if timer then timer:cancel() timer = nil end
      return
    end
    if timer then timer:cancel() end
    timer = morf.time.timer(lib.BRIGHTNESS_SETTLE, function()
      timer = nil
      shown = level
      require("osd").adjust("brightness", level)
    end, false)
  end
  morf.effect("eva.autobrightness", function()
    local wanted = a.present() and a.on() and primary()
    if wanted ~= claimed then
      claimed = wanted
      if wanted then sensors.claim_light() else
        sensors.release_light()
        shown = nil
      end
    end
    if wanted then follow(sensors.state.lux) end
  end)
  return a
end)

-- ------------------------------------------------------------ the voice note --

M.voice = lazily(function()
  local folder = morf.fs.home() .. "/Recordings"
  local recorder = require("lib.services.voice_recorder").new { folder = folder,
    spawn = (dry() or fake()) and function(argv, ended)
      log(table.concat(argv, " "))
      return { kill = function() ended() end }
    end or nil,
    saved = function(path) require("notifs").push { summary = "Voice note saved", body = path, app = "eva" } end }
  local v = { seconds = recorder.seconds }
  function v.present() return fake() or installed("pw-record") end
  function v.on() return recorder.running:get() end
  function v.set(now) recorder.set(now == true) end
  function v.status()
    if not v.on() then return "Off" end
    return services().duration(recorder.seconds:get())
  end
  return v
end)

-- ---------------------------------------------------------- background sounds --

M.sounds = lazily(function()
  local lib = require("lib.services.background_sounds")
  local player = lib.new { spawn = (dry() or fake()) and function(argv)
    log(table.concat(argv, " "))
    return { write = function() return true end, kill = function() end }
  end or nil }
  local s = { KINDS = lib.KINDS }
  local timer
  function s.present() return fake() or installed("pw-cat") end
  function s.on() return player.running:get() end
  function s.kind() return config.get("sounds.kind") or "rain" end
  function s.level() return math.max(0.05, math.min(1, tonumber(config.get("sounds.level")) or 0.4)) end
  local function start() player.play(s.kind(), s.level()) end
  function s.set(now) if now then start() else player.stop() end end
  --- Plays `kind` from now on.
  function s.set_kind(kind)
    config.set("sounds.kind", kind)
    if s.on() then start() end
  end
  --- The volume it plays at; a change restarts it once the hand rests.
  function s.set_level(value)
    config.set("sounds.level", value)
    if not s.on() then return end
    if timer then timer:cancel() end
    timer = morf.time.timer(300, function()
      timer = nil
      if s.on() then start() end
    end, false)
  end
  function s.status()
    if not s.on() then return "Off" end
    for _, kind in ipairs(lib.KINDS) do if kind.id == s.kind() then return kind.name end end
    return "On"
  end
  return s
end)

-- --------------------------------------------------------------- the services --

-- A systemd unit as a device: `present` while it exists on this machine.
local function unit_device(name, tag)
  return lazily(function()
    local unit = require("lib.services.unit").new { unit = name, run = run }
    local standing = morf.signal("eva." .. tag .. ".standing", false)
    local u = {}
    function u.present() return fake() or unit.found:get() end
    function u.on() if dry() or fake() then return standing:get() end return unit.on() end
    function u.set(now)
      if dry() or fake() then
        log(tag .. " " .. (now and "on" or "off"))
        standing:set(now == true)
        return
      end
      unit.set(now)
    end
    function u.status()
      if dry() or fake() then return standing:get() and "On" or "Off" end
      return unit.status()
    end
    if not fake() and not dry() then
      unit.find()
      checks[#checks + 1] = unit.check
    end
    return u
  end)
end

M.syncthing = unit_device("syncthing.service", "syncthing")
M.ssh = unit_device("sshd.service", "ssh")
-- GeoClue answers a program only through the session's agent: with the agent
-- stopped no program gets a location.
M.location = unit_device("geoclue-agent.service", "location")

M.waydroid = lazily(function()
  local droid = require("lib.services.waydroid").new { run = run,
    spawn = (dry() or fake()) and function(argv) log(table.concat(argv, " ")) end or nil }
  local w = {}
  function w.present() return fake() or installed("waydroid") end
  function w.on() return droid.on() end
  function w.set(now) droid.set(now == true) end
  function w.status() return droid.status() end
  if w.present() then
    droid.check()
    checks[#checks + 1] = droid.check
  end
  return w
end)

-- ----------------------------------------------------------- one-handed reach --

M.onehanded = lazily(function()
  local hyprland = require("lib.compositor.hyprland")
  local held = require("themes.session").keep("eva.onehanded", false)
  local o = { SHARE = 0.38 }
  local function output() return (morf.screens and morf.screens[1] and morf.screens[1].name) or "" end
  local function tell(top)
    if dry() or fake() then return log(("windows start %d down"):format(top)) end
    local name = output()
    hyprland.eval(("hl.monitor({output=%q, reserved={top=%d}})"):format(name, top), function(reply)
      if not (type(reply) == "string" and reply:match("^%s*ok%s*$")) then
        hyprland.keyword("monitor", ("%s,addreserved,%d,0,0,0"):format(name, top))
      end
    end)
  end
  function o.present()
    if fake() then return true end
    return hyprland.available() and require("responsive").form_factor() == "phone"
      and require("auto_rotate").built_in(output())
  end
  function o.on() return held:get() end
  function o.set(now)
    local _, height = require("responsive").size()
    held:set(now == true)
    tell(now and math.floor(height * o.SHARE) or 0)
  end
  function o.status() return o.on() and "Windows lowered" or "Off" end
  return o
end)

--- Builds what must run whether or not its tile is on show, and what makes
--- signals of its own, outside any effect.
function M.start()
  for _, name in ipairs { "filters", "autobrightness", "datasaver", "nfc", "tether", "voice", "sounds", "syncthing", "ssh",
    "location", "waydroid", "onehanded" } do
    M[name]()
  end
end

return M
