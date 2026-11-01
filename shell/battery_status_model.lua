-- One battery status for everything that shows it: UPower's display device,
-- its root and the power profile, normalised. No nodes.
--
--   level      0..100, a whole number
--   charging   current is going into the battery
--   plugged    on mains, charging or not
--   full       UPower says it is done
--   saver      the power-saver profile is on
--   limited    on mains and held at a charge limit
--   low        on battery at 20% or less
--   critical   on battery at 10% or less
--   mark       what the glyph draws inside: bolt, shield, plug, alert or ""
--   tone       which colour role it takes: ok, extra, warn, alert or ink
--
-- `M.read` is a tracked read for an effect or a binding that is on show;
-- nothing here polls or keeps a reader running.
local morf = require("morf")

local M = { LOW = 20, CRITICAL = 10 }

M.NONE = { present = false, level = 0, charging = false, plugged = false, full = false, saver = false,
  limited = false, low = false, critical = false, remaining = 0, mark = "", tone = "ink" }

local MAINS = { charging = true, pending_charge = true, fully_charged = true }
local SUPPLIES = "/sys/class/power_supply"

local function number_at(path)
  local ok, text = pcall(morf.fs.read, path)
  return ok and type(text) == "string" and tonumber(text:match("%d+")) or nil
end

local function word_at(path)
  local ok, text = pcall(morf.fs.read, path)
  return ok and type(text) == "string" and text:match("%S+") or nil
end

-- The kernel's charge thresholds of the machine's own battery: end, start.
local function sysfs_thresholds()
  local ok, entries = pcall(morf.fs.list, SUPPLIES, { follow = true })
  for _, entry in ipairs(ok and entries or {}) do
    local base = SUPPLIES .. "/" .. entry.name
    if word_at(base .. "/type") == "Battery" and word_at(base .. "/scope") ~= "Device" then
      return number_at(base .. "/charge_control_end_threshold"), number_at(base .. "/charge_control_start_threshold")
    end
  end
end

-- UPower's display device; a present battery row when that reads absent.
local function device(state)
  local display = state.display
  if display and display.present then return display end
  local rows = state.devices
  if not rows then return nil end
  for i = 1, rows:len() do
    local row = rows:get(i)
    if row.kind == "battery" and row.present then return row end
  end
end

local function classify(s)
  if s.charging then s.mark = "bolt"
  elseif s.limited then s.mark = "shield"
  elseif s.plugged then s.mark = "plug"
  elseif s.critical then s.mark = "alert"
  else s.mark = "" end
  if s.critical then s.tone = "alert"
  elseif s.low then s.tone = "warn"
  elseif s.charging then s.tone = "ok"
  elseif s.saver then s.tone = "extra"
  else s.tone = "ink" end
  return s
end

--- The status from `upower`, `services.upower` when none is given. A
--- stand-in may answer the thresholds with its own `charge_limit()`.
function M.read(upower)
  upower = upower or require("services").upower
  local state = upower and upower.state
  if not (state and state.available) then return M.NONE end
  local d = device(state)
  if not d then return M.NONE end
  local name = d.state
  local level = math.max(0, math.min(100, math.floor((d.percentage or 0) + 0.5)))
  local charging = name == "charging" or (name == nil and d.charging == true)
  local plugged = charging or MAINS[name] == true or state.on_battery == false
  local limited = false
  if plugged and not charging then
    local stop, start
    if upower.charge_limit then stop, start = upower.charge_limit() else stop, start = sysfs_thresholds() end
    limited = stop ~= nil and stop < 100 and level >= (start or stop) - 1
  end
  local profiles = state.profiles
  return classify {
    present = true, level = level, charging = charging, plugged = plugged,
    full = name == "fully_charged", limited = limited,
    saver = profiles ~= nil and profiles.available == true and profiles.active == "power-saver",
    low = not plugged and level <= M.LOW, critical = not plugged and level <= M.CRITICAL,
    remaining = (charging and d.time_to_full or d.time_to_empty) or 0,
  }
end

--- The status in words, for a tile and a screen reader.
function M.describe(s)
  if not s.present then return "On mains power" end
  local words = { ("%d%%"):format(s.level) }
  if s.charging then words[#words + 1] = "charging"
  elseif s.limited then words[#words + 1] = "limit reached"
  elseif s.full then words[#words + 1] = "full"
  elseif s.plugged then words[#words + 1] = "plugged in" end
  if s.saver then words[#words + 1] = "power saver" end
  return table.concat(words, ", ")
end

-- ---------------------------------------------------------- the stand-in --

local function fake_values(spec)
  local words = {}
  for word in tostring(spec):gmatch("[^,%s]+") do words[word] = true end
  local level = tonumber(tostring(spec):match("%d+")) or 64
  local name = "discharging"
  if words.charging then name = "charging"
  elseif words.full then name = "fully_charged"
  elseif words.limited then name = "pending_charge"
  elseif words.plugged then name = "pending_discharge" end
  return { level = level, name = name, saver = words.saver == true, limited = words.limited == true,
    on_battery = name == "discharging" }
end

--- A UPower in name only, for a machine without a bus. `spec` is a level and
--- any of charging, plugged, full, limited and saver: "57,charging,saver".
--- `morf ipc call fake-battery SPEC` moves it.
function M.stand_in(spec)
  local first = fake_values(spec)
  local state = morf.state { available = true, on_battery = first.on_battery,
    display = { present = true, percentage = first.level, state = first.name, time_to_empty = 0, time_to_full = 0,
      charging = first.name == "charging" or first.name == "pending_charge" },
    profiles = { available = true, active = first.saver and "power-saver" or "balanced" } }
  local limit = first.limited and first.level or nil
  local stand_in = { state = state, charge_limit = function() return limit end,
    set_profile = function(id) state.profiles.active = id end }
  morf.ipc["fake-battery"] = function(next_spec)
    local v = fake_values(next_spec)
    limit = v.limited and v.level or nil
    state.on_battery = v.on_battery
    state.display.percentage = v.level
    state.display.state = v.name
    state.display.charging = v.name == "charging" or v.name == "pending_charge"
    state.profiles.active = v.saver and "power-saver" or "balanced"
    return true
  end
  return stand_in
end

return M
