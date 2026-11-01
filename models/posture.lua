-- Whether a convertible is folded into a tablet: the kernel's SW_TABLET_MODE,
-- through `evtest`. Its events come as a stream of
-- lines; the state is asked outright (`--query`) at the start, after a resume,
-- after each event, and every RECHECK while folded. A hint (`eva tablet on`,
-- what Hyprland's switch binds send) starts the same question; with no answer
-- to be had the hint stands once SETTLE has passed without another.
--
-- libinput ignores the keyboard and the touchpad while the switch is on: that
-- part is not done here.
--
--   local posture = require("models.posture")
--   posture.start()
--   ui.Text { text = function() return posture.folded() and "Tablet" or "Laptop" end }
--
-- EVA_FAKE_TABLET=on or off stands in for the switch; `tablet on|off` moves it.
local morf = require("morf")

local M = { SETTLE = 700, RECHECK = 20000, RETRY = 30000, LONGEST = 600000, EVTEST = "evtest" }

local function fake_switch()
  local spec = morf.env and morf.env("EVA_FAKE_TABLET")
  if spec == "on" then return true end
  if spec == "off" then return false end
end

--- The input device with a tablet switch: `{ name, node }`, or nil.
function M.find(path)
  for _, device in ipairs(require("lib.services.input_devices").list(path)) do
    if device.tablet_switch and device.event then
      return { name = device.name or "", node = "/dev/input/" .. device.event }
    end
  end
end

--- The switch as the kernel has it: `done(true)`, `done(false)`, or `done(nil)`
--- without evtest or the right to read the device.
function M.ask(device, done)
  local ok = pcall(morf.process.run, { M.EVTEST, "--query", device.node, "EV_SW", "SW_TABLET_MODE" },
    { timeout_ms = 3000 }, function(result)
      local code = result and result.code
      if code == 10 then done(true) elseif code == 0 then done(false) else done(nil) end
    end)
  if not ok then done(nil) end
end

--- Hears the switch: `changed(on)` per event, `ended()` when the stream stops.
function M.listen(device, changed, ended)
  local ok, child = pcall(morf.process.spawn, {
    command = { M.EVTEST, device.node },
    on_stdout = function(line)
      local value = line:match("%(SW_TABLET_MODE%), value (%d)")
      if value then changed(value == "1") end
    end,
    on_stderr = function() end,
    on_exit = function() ended() end,
  })
  if not ok or not child then ended() return nil end
  return child
end

-- The logind signal a resume ends with: `heard()` after each one.
local function resumes(heard)
  local ok, client = pcall(function() return require("lib.services.dbus").new({ bus = "system" }) end)
  if not ok then return end
  pcall(client.on_signal, "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager",
    "PrepareForSleep", function(body)
      if require("lib.services.dbus").first(body) == false then heard() end
    end)
end

-- Where a folded machine is written down for the lock screen, which runs apart.
local function runtime_file()
  local dir = morf.env and morf.env("XDG_RUNTIME_DIR")
  return dir and dir ~= "" and (dir .. "/eva/posture") or nil
end

local function remembered()
  local path = runtime_file()
  if not path then return false end
  local ok, text = pcall(morf.fs.read, path)
  return ok and type(text) == "string" and text:match("^folded") ~= nil
end

--- A posture. `options`, each a seam: `find()`, `ask(device, done)`,
--- `listen(device, changed, ended)`, `resumed(heard)`, `moved(on)` (a hint,
--- for a stand-in's switch), `changed(folded)`, `initial`.
function M.new(options)
  options = options or {}
  local find, ask = options.find or M.find, options.ask or M.ask
  local listen, resumed = options.listen or M.listen, options.resumed or resumes
  local folded = morf.signal("eva.posture.folded." .. tostring(options), options.initial == true)
  local fitted = morf.signal("eva.posture.fitted." .. tostring(options), false)
  local p = {}
  local device, settle, recheck, pinned, started, hint
  local wait = M.RETRY

  local function follow()
    local want = folded:get() and device ~= nil and pinned == nil
    if want and not recheck then
      recheck = morf.time.timer(M.RECHECK, function() p.check() end, true)
    elseif not want and recheck then
      recheck:cancel()
      recheck = nil
    end
  end

  local function take(value)
    if pinned ~= nil then value = pinned end
    if value ~= folded:get() then
      folded:set(value)
      if options.changed then options.changed(value) end
    end
    follow()
  end

  --- Whether it is folded.
  function p.folded() return folded:get() end

  --- Whether the machine has a tablet switch.
  function p.present() return fitted:get() end

  --- The device, or nil.
  function p.device() return device end

  --- Asks the kernel now.
  function p.check()
    if not device or pinned ~= nil then return end
    ask(device, function(value) if value ~= nil then take(value) end end)
  end

  --- A hint that the switch moved: settled, then asked.
  function p.report(on)
    hint = on == true
    if options.moved then options.moved(hint) end
    if settle then settle:cancel() end
    settle = morf.time.timer(M.SETTLE, function()
      settle = nil
      if not device then return take(hint) end
      ask(device, function(value)
        if value == nil then value = hint end
        take(value)
      end)
    end, false)
  end

  --- Holds the posture at `on` whatever the switch says; nil lets it go.
  function p.pin(on)
    pinned = on
    if on ~= nil then return take(on) end
    follow()
    p.check()
  end

  --- Whether the posture is held by hand.
  function p.pinned() return pinned end

  -- The event stream, started again after a wait that doubles to LONGEST.
  local function stream()
    listen(device, function(on) p.report(on) end, function()
      morf.time.timer(wait, function() if device then stream() end end, false)
      wait = math.min(wait * 2, M.LONGEST)
    end)
  end

  --- Looks for the switch again: a device can come with a dock.
  function p.refresh()
    local was = device
    device = find()
    fitted:set(device ~= nil)
    if device and not was then
      p.check()
      stream()
    end
    follow()
  end

  --- Starts following the switch; idempotent. Nothing runs on a machine
  --- without one.
  function p.start()
    if started then return end
    started = true
    p.refresh()
    resumed(function() p.check() end)
  end

  return p
end

local shared

local function instance()
  if shared then return shared end
  local bank = morf.reloadable("eva.posture", {})
  local kept = bank:get().folded
  local switch = fake_switch()
  if switch ~= nil and kept ~= nil then switch = kept end
  local stand_in = switch ~= nil
  local options = { initial = switch, changed = function(value)
    bank:set({ folded = value })
    local path = runtime_file()
    if path and not stand_in then
      pcall(morf.fs.write, path, value and "folded\n" or "open\n", { atomic = true, parents = true })
    end
  end }
  if stand_in then
    options.find = function() return { name = "Stand-in tablet switch", node = "" } end
    options.ask = function(_, done) done(switch) end
    options.listen = function() end
    options.resumed = function() end
    options.moved = function(on) switch = on end
  else
    options.initial = kept
    if options.initial == nil then options.initial = remembered() end
  end
  shared = M.new(options)
  return shared
end

--- Whether the machine is folded: a tracked read.
function M.folded() return instance().folded() end

--- Whether it has a tablet switch: a tracked read.
function M.present() return instance().present() end

--- Starts following the switch.
function M.start() return instance().start() end

--- Looks for the switch again.
function M.refresh() return instance().refresh() end

--- A hint from outside: the switch went on or off.
function M.report(on) return instance().report(on) end

--- The posture held at `on`, or let go with nil.
function M.pin(on) return instance().pin(on) end

--- What `tablet state` says.
function M.state()
  local p = instance()
  local device = p.device()
  return { folded = p.folded(), present = p.present(), pinned = p.pinned(), device = device and device.name or "" }
end

return M
