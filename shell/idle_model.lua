-- Idle: the staged timers, what keeps the session awake, and the hooks around
-- sleep. State and actions only; the warning and the page are drawn elsewhere.
--
-- A stage the system's configuration fixes (models/idle_config.lua) wins over
-- Settings, and runs under the system's idle daemon: here it only shows.
--
-- Stages run on every output's runtime so each can draw its warning. Only the
-- primary one acts.
local morf = require("morf")
local config = require("config")
local kept = require("themes.session")
local idle_config = require("models.idle_config")
local reason_file = require("models.lock_reason")
local M = {}

M.STAGES = {
  { id = "lock", name = "Lock", icon = "lock", choices = { 0, 60, 300, 600, 1800 } },
  { id = "blank", name = "Screen off", icon = "monitor", choices = { 0, 60, 300, 600, 1800 } },
  { id = "suspend", name = "Suspend", icon = "bedtime", choices = { 0, 900, 1800, 3600, 7200 } },
}
M.DIM_CHOICES = { 0, 5, 10, 30 }
M.AWAKE_CHOICES = { { label = "15 m", seconds = 900 }, { label = "1 h", seconds = 3600 }, { label = "4 h", seconds = 14400 } }

M.awake = kept.keep("eva.utilities.awake", false)
local awake_until = kept.keep("eva.utilities.awake_until", 0)
-- "" or "warning": the warning is showing, for this many milliseconds.
M.phase = morf.signal("eva.idle.phase", "")
M.warning_ms = morf.signal("eva.idle.warning_ms", 0)
-- Who asked over D-Bus, kept here to be listed.
M.holders = morf.signal("eva.idle.holders", {})

local function dry()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end
local function primary() return not morf.window.primary or morf.window.primary() end
local function services() return require("services") end
local function login() return require("models.logind").connect() end

--- What the system fixes. Read once: /etc does not move under a session.
M.system = idle_config.load()

function M.managed(stage) return M.system.managed[stage] end

local function on_battery()
  local ok, value = pcall(function()
    local power = services().upower
    return power and power.state.on_battery == true
  end)
  return ok and value
end

--- The seconds a stage waits now; 0 for never.
function M.seconds(stage)
  local fixed = M.managed(stage)
  if fixed ~= nil then return tonumber(fixed) or 0 end
  if on_battery() then
    local short = tonumber(config.get("idle.battery." .. stage)) or 0
    if short > 0 then return short end
  end
  return tonumber(config.get("idle." .. stage)) or 0
end

-- ------------------------------------------------------------- keep awake --

--- Keeps the session awake: for `seconds`, or until turned off without them.
local ending
function M.set_awake(on, seconds)
  if ending then ending:cancel() ending = nil end
  awake_until:set(on and seconds and morf.time.now() + seconds or 0)
  M.awake:set(on and true or false)
  if on and seconds then
    ending = morf.time.timer(seconds * 1000, function() ending = nil M.set_awake(false) end, false)
  end
end

--- When a timed keep-awake ends, as wall seconds, or 0.
function M.awake_until() return awake_until:get() end

-- A timed keep-awake carried through a reload picks up its timer.
do
  local left = awake_until:get() - morf.time.now()
  if M.awake:get() and awake_until:get() > 0 then
    if left > 0 then M.set_awake(true, left) else M.set_awake(false) end
  end
end

local function open_classes()
  local out, seen = {}, {}
  local ok = pcall(function()
    local model = services().hyprland.state.clients
    for i = 1, model and model:len() or 0 do
      local class = model:get(i).class
      if class and class ~= "" and not seen[class] then
        seen[class] = true
        out[#out + 1] = class
      end
    end
  end)
  table.sort(out)
  return ok and out or {}
end
M.open_classes = open_classes

--- What keeps the session awake now: `{ kind, name, why }`, a tracked read.
function M.reasons()
  local out = {}
  if M.awake:get() then out[#out + 1] = { kind = "awake", name = "Keep awake", why = "Turned on by you" } end
  local wanted = {}
  for _, class in ipairs(config.get("idle.apps") or {}) do wanted[class] = true end
  for _, class in ipairs(open_classes()) do
    if wanted[class] then out[#out + 1] = { kind = "app", name = class, why = "Keeps the screen on" } end
  end
  if config.get("idle.fullscreen") then
    local ok, full = pcall(function() return services().hyprland.state.fullscreen end)
    if ok and full then out[#out + 1] = { kind = "fullscreen", name = "Fullscreen window", why = "A window fills the screen" } end
  end
  if config.get("idle.media") then
    local ok, playing = pcall(function() return services().media.state.active.playing == true end)
    if ok and playing then out[#out + 1] = { kind = "media", name = "Media", why = "Something is playing" } end
  end
  if config.get("idle.charging") then
    local ok, battery = pcall(on_battery)
    if ok and battery == false and services().upower then
      out[#out + 1] = { kind = "charging", name = "On mains", why = "Stays on while plugged in" }
    end
  end
  for _, row in ipairs(M.holders:get()) do
    out[#out + 1] = { kind = "bus", name = row.app, why = row.reason }
  end
  return out
end

--- Whether anything holds the session awake, inhibitors of logind's included.
function M.held()
  if #M.reasons() > 0 then return true end
  local bus = login()
  if not bus or not bus.available() then return false end
  local ok, rows = pcall(bus.inhibitors)
  for _, row in ipairs(ok and rows or {}) do
    if row.mode == "block" and tostring(row.what):find("idle", 1, true) then return true end
  end
  return false
end

--- The inhibitors logind holds that bear on idle or sleep: `{ what, who, why }`.
function M.inhibitors()
  local bus = login()
  if not bus or not bus.available() then return {} end
  local ok, rows = pcall(bus.inhibitors)
  local out = {}
  for _, row in ipairs(ok and rows or {}) do
    if row.mode == "block" and (tostring(row.what):find("idle", 1, true) or tostring(row.what):find("sleep", 1, true)) then
      out[#out + 1] = row
    end
  end
  return out
end

morf.effect("eva.utilities.inhibit", function()
  local on = #M.reasons() > 0
  if dry() then
    morf.log("info", "eva: keep awake " .. (on and "on" or "off") .. " (dry run)")
  elseif morf.idle and morf.idle.inhibit then
    morf.idle.inhibit(on)
  end
end)

-- ----------------------------------------------------------------- stages --

local function run(argv, what)
  if type(argv) ~= "table" or #argv == 0 then return false end
  if dry() then
    morf.log("info", "eva: idle " .. what .. " (dry run)")
    return true
  end
  morf.process.run(argv, { timeout_ms = 15000, max_output = 512 }, function() end)
  return true
end

local function locked()
  local bus = login()
  return bus ~= nil and bus.available() and bus.state.session.locked == true
end

--- Asks for the lock, saying it comes from idle: the window after it is for this.
function M.lock_now(reason)
  if reason then reason_file.mark(reason) end
  local argv = M.system.commands.lock
  if type(argv) ~= "table" or #argv == 0 then argv = config.get("session.commands.lock") end
  return run(argv, "lock")
end

local blanked = false
local ACT = {
  lock = function()
    if not locked() then M.lock_now("idle") end
  end,
  blank = function()
    blanked = true
    idle_config.dpms("off")
  end,
  suspend = function() run(config.get("session.commands.suspend"), "suspend") end,
}

--- A stage has come due.
function M.fire(stage)
  if M.held() then return false end
  if stage == "warning" then
    M.phase:set("warning")
    return true
  end
  M.phase:set("")
  if M.managed(stage) ~= nil or not primary() or not ACT[stage] then return false end
  ACT[stage]()
  return true
end

--- Input is back.
function M.resume()
  M.phase:set("")
  if not primary() then return end
  if blanked then
    blanked = false
    idle_config.dpms("on")
  end
  local words = config.get("idle.resume_command")
  if type(words) == "table" and #words > 0 and M.fired then run(words, "resume") end
  M.fired = false
end

--- The timers wanted now: `{ stage, seconds }`, soonest first.
function M.plan()
  if not config.get("idle.enabled") then return {} end
  local list = {}
  for _, stage in ipairs(M.STAGES) do
    local seconds = M.seconds(stage.id)
    if seconds > 0 then list[#list + 1] = { stage = stage.id, seconds = seconds } end
  end
  local lock, dim = M.seconds("lock"), tonumber(config.get("idle.dim")) or 0
  if lock > 0 and dim > 0 and lock > dim then
    list[#list + 1] = { stage = "warning", seconds = lock - dim }
    M.warning_ms:set(dim * 1000)
  end
  table.sort(list, function(a, b) return a.seconds < b.seconds end)
  return list
end

--- Starts the timers. `options.subscribe` stands for morf.idle.subscribe.
function M.start(options)
  options = options or {}
  local subscribe = options.subscribe or (morf.idle and morf.idle.subscribe)
  if not subscribe then return end
  if require("themes.phone_wake").present() then return end
  -- The name browsers ask on. A client's request becomes this session's own
  -- inhibitor, which any idle timer honours.
  if primary() and morf.dbus and not options.subscribe then
    pcall(function()
      require("lib.services.screensaver").serve {
        on_change = function(holders)
          local copy = {}
          for i, row in ipairs(holders) do copy[i] = row end
          M.holders:set(copy)
        end,
      }
    end)
  end
  local subscriptions = {}
  morf.effect("eva.idle.timers", function()
    local plan = M.plan()
    for _, sub in ipairs(subscriptions) do sub:cancel() end
    subscriptions = {}
    for _, item in ipairs(plan) do
      subscriptions[#subscriptions + 1] = subscribe(math.floor(item.seconds * 1000), function(idle)
        if idle then
          M.fired = true
          M.fire(item.stage)
        else
          M.resume()
        end
      end)
    end
  end)
end

-- ------------------------------------------------------------ around sleep --

local hold
local function take_hold(bus)
  if hold then return end
  local ok, handle = pcall(bus.inhibit, "sleep", "eva", "Running the sleep hooks", "delay")
  if ok then hold = handle end
end
local function let_go()
  if hold then pcall(hold.release) hold = nil end
end

--- Runs the hooks, and locks where the system's idle daemon does not.
function M.watch_sleep()
  local bus = login()
  if not bus or not primary() then return end
  local locks_itself = not M.system.sleep_lock
  local function wanted() return #(config.get("idle.before_sleep") or {}) > 0 or locks_itself end
  if wanted() then take_hold(bus) end
  bus.on_prepare_for_sleep(function(going)
    reason_file.clear()
    if going then
      if locks_itself and config.get("lock.on_suspend") and not locked() then M.lock_now() end
      local before = config.get("idle.before_sleep")
      if type(before) == "table" and #before > 0 then
        if dry() then
          morf.log("info", "eva: idle before sleep (dry run)")
        else
          morf.process.run(before, { timeout_ms = 3000, max_output = 512 }, function() let_go() end)
          return
        end
      end
      morf.time.timer(locks_itself and 800 or 0, let_go, false)
    else
      run(config.get("idle.after_sleep"), "after sleep")
      if wanted() then take_hold(bus) end
    end
  end)
end

--- A closed lid locks, where it does not already sleep the machine.
function M.watch_lid()
  morf.effect("eva.idle.lid", function()
    if not primary() or not config.get("lock.on_lid") then return end
    local ok, closed = pcall(function() return services().upower.state.lid_is_closed end)
    if ok and closed == true and not locked() then M.lock_now() end
  end)
end

--- Locks once as the session starts, if chosen.
function M.lock_at_start()
  if not config.get("lock.at_startup") or not primary() then return end
  local run_dir = morf.env("XDG_RUNTIME_DIR")
  local marker = run_dir and (run_dir .. "/eva/locked-at-start")
  if not marker or morf.fs.exists(marker) then return end
  pcall(morf.fs.write, marker, "", { parents = true, mode = 384 })
  M.lock_now()
end

return M
