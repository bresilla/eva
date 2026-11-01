-- UPower's charge threshold, the one client behind the Power page and
-- eva-battery: its Charge* properties read and EnableChargeThreshold called. What
-- the kernel's own files hold, and writing them, is lib/services/charger.lua's.
--
--   local limit = require("lib.services.charge_limit").new()
--   limit.refresh()
--   limit.state:get()     -- { supported, enabled, start, stop, percentage }
--   limit.set(true, function(ok, why) end)
--
-- EVA_DRY_RUN holds a change back, EVA_FAKE_CHARGE_LIMIT stands in for a
-- battery that has one, EVA_POWER_SUPPLY is read for /sys/class/power_supply.
local morf = require("morf")
local charger = require("lib.services.charger")

local M = {}

local SERVICE = "org.freedesktop.UPower"
local DEVICE = "org.freedesktop.UPower.Device"

local function flag(name)
  local value = morf.env(name)
  return value ~= nil and value ~= "" and value ~= "0"
end

local function busctl(words, done)
  local argv = { "busctl", "--system" }
  for _, word in ipairs(words) do argv[#argv + 1] = word end
  morf.process.run(argv, { timeout_ms = 3000 }, done)
end

-- A property's value alone: busctl prints its type first.
local function value_of(result)
  if not (result and result.ok) then return nil end
  return (result.stdout or ""):gsub("%s+$", ""):match("^%S+%s+(.*)$")
end

local function property(device, name, done)
  busctl({ "get-property", SERVICE, device, DEVICE, name }, function(result) done(value_of(result)) end)
end

local function battery(done)
  busctl({ "call", SERVICE, "/org/freedesktop/UPower", SERVICE, "EnumerateDevices" }, function(result)
    if not (result and result.ok) then done(nil) return end
    done((result.stdout or ""):match('"([^"]*/battery_[^"]*)"'))
  end)
end

function M.new()
  local limit = {
    state = morf.signal("eva.charge_limit", { supported = false, enabled = false }),
    message = morf.signal("eva.charge_limit.message", ""),
  }
  local device
  local fake = flag("EVA_FAKE_CHARGE_LIMIT")

  --- Reads what the battery says into `state`: `done(state)` after it.
  function limit.refresh(done)
    if fake then
      local kept = limit.state:get()
      local now = { supported = true, enabled = kept.enabled == true, start = 40, stop = 80, percentage = 73 }
      limit.state:set(now)
      if done then done(now) end
      return
    end
    battery(function(path)
      device = path
      if not path then
        limit.state:set { supported = false, enabled = false }
        if done then done(limit.state:get()) end
        return
      end
      local now, names = { supported = false, enabled = false }, {
        { "supported", "ChargeThresholdSupported" }, { "enabled", "ChargeThresholdEnabled" },
        { "start", "ChargeStartThreshold" }, { "stop", "ChargeEndThreshold" }, { "percentage", "Percentage" },
      }
      local function step(index)
        local name = names[index]
        if not name then
          -- A battery switched by a charge type alone has no numbers: UPower says 0.
          if now.stop == 0 then now.start, now.stop = nil, nil end
          limit.state:set(now)
          if done then done(now) end
          return
        end
        property(path, name[2], function(value)
          if value == "true" then now[name[1]] = true
          elseif value == "false" then now[name[1]] = false
          elseif value then now[name[1]] = tonumber(value) end
          step(index + 1)
        end)
      end
      step(1)
    end)
  end

  --- Turns the limit on or off: `done(ok, why)`.
  function limit.set(on, done)
    local function answer(ok, why)
      limit.message:set(ok and "" or tostring(why))
      if done then done(ok, why) end
    end
    if not limit.state:get().supported then answer(false, "This battery has no charge limit") return end
    if fake then
      local now = {}
      for key, value in pairs(limit.state:get()) do now[key] = value end
      now.enabled = on == true
      limit.state:set(now)
      answer(true)
      return
    end
    if flag("EVA_DRY_RUN") then
      morf.log("info", "eva: EnableChargeThreshold " .. tostring(on) .. " on " .. tostring(device) .. " (dry run)")
      answer(true, "dry run")
      return
    end
    busctl({ "call", SERVICE, device, DEVICE, "EnableChargeThreshold", "b", on and "true" or "false" }, function(result)
      if result and result.ok then limit.refresh(function() answer(true) end)
      else answer(false, (result and result.stderr ~= "" and result.stderr) or "UPower refused") end
    end)
  end

  return limit
end

local INPUTS = { usb = "USB", wireless = "Wireless", mains = "Mains" }

local function supplies()
  local dir = morf.env("EVA_POWER_SUPPLY")
  return dir ~= nil and dir ~= "" and dir or nil
end

-- What feeds the battery, in lines; nil without one in the kernel's folder.
local function feed_lines(lines)
  local feed = charger.read(supplies())
  if not feed.present then return nil end
  lines[#lines + 1] = "status " .. feed.status
  if feed.kind then
    lines[#lines + 1] = "input " .. INPUTS[feed.kind] .. (feed.protocol and (" " .. feed.protocol) or "")
  end
  if feed.watts then lines[#lines + 1] = ("power %.1f W"):format(feed.watts) end
  if feed.limit then lines[#lines + 1] = ("stops at %d"):format(feed.limit) end
  return true
end

-- Charging stops at `wanted` percent, in the kernel's own file.
local function level(wanted, done)
  local value = wanted and wanted:match("^%d+$") and tonumber(wanted)
  if not value then done(nil, "limit takes on, off or a percentage") return end
  if value < charger.LOWEST or value > 100 then done(nil, "a limit is from 50 to 100") return end
  local dir = supplies()
  if not charger.limit_file(dir) then done(nil, "this battery has no charge limit") return end
  if flag("EVA_DRY_RUN") then done("dry run: charge limit " .. value) return end
  charger.writable(function(can)
    if not can then done(nil, "this session may not write the limit; programs.eva.hardware.chargeLimit grants it") return end
    local ok, why = charger.set_limit(value, dir)
    if ok then done("limit " .. value) else done(nil, why) end
  end, dir)
end

--- `eva-battery`'s command as a job: `done(text, why)`.
function M.job(args, done)
  local how, wanted = args[1] or "status", args[2]
  if how == "limit" and wanted ~= "on" and wanted ~= "off" then return level(wanted, done) end
  local limit = M.new()
  limit.refresh(function(state)
    if how == "status" then
      local lines = {}
      if state.percentage then lines[1] = ("charge %d%%"):format(math.floor(state.percentage + 0.5)) end
      local fed = feed_lines(lines)
      if not state.percentage and not fed then done(nil, "no battery") return end
      if state.supported then
        lines[#lines + 1] = "limit " .. tostring(state.enabled)
        if state.stop then lines[#lines + 1] = ("between %d and %d"):format(state.start or 0, state.stop) end
      end
      done(table.concat(lines, "\n"))
    elseif how == "limit" then
      if state.percentage == nil then done(nil, "no battery") return end
      if not state.supported then done(nil, "this battery has no charge limit") return end
      limit.set(wanted == "on", function(ok, why)
        if ok then done(why == "dry run" and "dry run" or ("limit " .. wanted)) else done(nil, why) end
      end)
    else
      done(nil, "unknown command: " .. tostring(how))
    end
  end)
end

return M
