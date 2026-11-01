-- Eva's own services against what is really on the VM, for system.py: each verb
-- runs the code the shell runs and answers in JSON, through lib.util.job.
local morf = require("morf")
local job = require("lib.util.job")

job.quiet()

local function answer(value) job.finish(morf.json.encode(value)) end

-- Asks `ready()` every 200 ms for ten seconds, then `done(value)` with what it said.
local function when(ready, done)
  local tries = 0
  local function ask()
    local value = ready()
    tries = tries + 1
    if value or tries >= 50 then return done(value) end
    morf.time.timer(200, ask, false)
  end
  ask()
end

local function network()
  local net = require("lib.services.networkmanager").connect()
  return net, require("lib.services.hotspot").new(net)
end

local VERBS = {}

function VERBS.printers()
  require("lib.services.printers").read(answer)
end

function VERBS.readings()
  local input = require("lib.services.input_config")
  local hyprland = require("lib.compositor.hyprland")
  morf.time.timer(500, function()
    hyprland.options(input.read_names(), function(replies) answer(input.readings(replies)) end)
  end, false)
end

function VERBS.rotate(orientation, output)
  local rotate = require("auto_rotate")
  morf.time.timer(500, function()
    local ok = rotate.apply(orientation, output)
    morf.time.timer(1500, function() answer { ok = ok } end, false)
  end, false)
end

function VERBS.battery()
  local upower = require("lib.services.upower").connect()
  local status = require("battery_status_model")
  when(function()
    local now = status.read(upower)
    return now.present and now or nil
  end, function(now) answer(now or status.NONE) end)
end

function VERBS.hotspot_save(ssid)
  local password = (job.input() or ""):gsub("%s+$", "")
  local net, hotspot = network()
  when(function() return net.state.available and hotspot.device() end, function(device)
    if not device then return job.finish(nil, "no radio can be an access point") end
    local sent, why = hotspot.save(ssid, password, function(path, failed)
      if path then answer { path = path } else job.finish(nil, tostring(failed)) end
    end)
    if not sent then job.finish(nil, tostring(why)) end
  end)
end

function VERBS.hotspot_start()
  local net, hotspot = network()
  when(function() return net.state.available and hotspot.device() and hotspot.profile() end, function(profile)
    if not profile then return job.finish(nil, "no profile") end
    local sent, why = hotspot.start(function(path, failed)
      if path then answer { path = path } else job.finish(nil, tostring(failed)) end
    end)
    if not sent then job.finish(nil, tostring(why)) end
  end)
end

function VERBS.hotspot_stop()
  local net, hotspot = network()
  when(function() return net.state.available and hotspot.active() end, function()
    hotspot.stop(function(ok, failed)
      if ok then answer { ok = true } else job.finish(nil, tostring(failed)) end
    end)
  end)
end

local verb = VERBS[morf.operands[1]]
if verb then
  verb(table.unpack(morf.operands, 2))
else
  job.finish(nil, "no verb " .. tostring(morf.operands[1]))
end
