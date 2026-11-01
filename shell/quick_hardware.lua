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
  local state = morf.state { accelerometer = true, orientation = "normal" }
  local sensors = { state = state, claim = function() end, release = function() end }
  if not fake() then
    local ok, lib = pcall(require, "lib.services.sensors")
    local connected, reader = false, nil
    if ok then connected, reader = pcall(lib.connect) end
    sensors = connected and reader or { state = morf.state { accelerometer = false, orientation = "undefined" },
      claim = function() end, release = function() end }
  end
  local r = { sensors = sensors }
  function r.present() return sensors.state.accelerometer == true end
  --- Whether the screen keeps its rotation.
  function r.on()
    local lock = config.get("rotation.lock")
    if lock == "auto" then return require("responsive").form_factor() == "desk" end
    return lock == "on"
  end
  function r.set(now) config.set("rotation.lock", now and "on" or "off") end
  function r.status() return r.on() and "Locked" or "Auto" end
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
  local t = {}
  function t.present() return fake() or real ~= nil end
  function t.on() if real and not dry() then return real.on() end return lit:get() end
  function t.set(now)
    if real and not dry() then return real.set(now) end
    log("flashlight " .. (now and "on" or "off"))
    lit:set(now == true)
  end
  function t.status() return t.on() and "On" or "Off" end
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

return M
