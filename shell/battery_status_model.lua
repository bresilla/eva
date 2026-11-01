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
--   wireless   charging without a cable
--   fast       charging at a fast charger's rate
--   slow       charging at less than a phone needs
--   watts      what reaches the cell, 0 when that cannot be told
--   mark       what the glyph draws inside: bolt, shield, plug, alert or ""
--   tone       which colour role it takes: ok, extra, warn, alert or ink
--
-- `M.read` is a tracked read for an effect or a binding that is on show;
-- nothing here polls or keeps a reader running.
local morf = require("morf")

local M = { LOW = 20, CRITICAL = 10 }

M.NONE = { present = false, level = 0, charging = false, plugged = false, full = false, saver = false,
  limited = false, low = false, critical = false, wireless = false, fast = false, slow = false, watts = 0,
  remaining = 0, mark = "", tone = "ink" }

local MAINS = { charging = true, pending_charge = true, fully_charged = true }

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

-- What feeds the battery: a stand-in's `charger()`, else the kernel's. A stand-in
-- with thresholds of its own and no `charger` has no feed.
local function feed_of(upower)
  if upower.charger then return upower.charger() end
  if upower.charge_limit then return {} end
  local ok, feed = pcall(function() return require("lib.services.charger").read() end)
  return ok and feed or {}
end

--- The status from `upower`, `services.upower` when none is given. A
--- stand-in may answer the thresholds with its own `charge_limit()` and the
--- feed with its own `charger()`.
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
    if upower.charge_limit then stop, start = upower.charge_limit()
    else stop, start = require("lib.services.charger").thresholds() end
    limited = stop ~= nil and stop < 100 and level >= (start or stop) - 1
  end
  local feed = plugged and feed_of(upower) or {}
  local profiles = state.profiles
  return classify {
    present = true, level = level, charging = charging, plugged = plugged,
    full = name == "fully_charged", limited = limited,
    saver = profiles ~= nil and profiles.available == true and profiles.active == "power-saver",
    low = not plugged and level <= M.LOW, critical = not plugged and level <= M.CRITICAL,
    wireless = charging and feed.wireless == true, fast = charging and feed.fast == true,
    slow = charging and feed.slow == true, watts = charging and feed.watts or 0,
    remaining = (charging and d.time_to_full or d.time_to_empty) or 0,
  }
end

--- What is happening to the charge, in a word or two: "fast wireless charging".
function M.charging_words(s)
  local words = {}
  if s.fast then words[#words + 1] = "fast" end
  if s.wireless then words[#words + 1] = "wireless" end
  words[#words + 1] = s.slow and "slow charging" or "charging"
  return table.concat(words, " ")
end

--- The status in words, for a tile and a screen reader.
function M.describe(s)
  if not s.present then return "On mains power" end
  local words = { ("%d%%"):format(s.level) }
  if s.charging then words[#words + 1] = M.charging_words(s)
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
  local text = tostring(spec)
  local level = tonumber(text:match("^%s*(%d+)")) or 64
  local name = "discharging"
  if words.charging then name = "charging"
  elseif words.full then name = "fully_charged"
  elseif words.limited then name = "pending_charge"
  elseif words.plugged then name = "pending_discharge" end
  local limit = tonumber(text:match("limit=(%d+)")) or (words.limited and level or nil)
  return { level = level, name = name, saver = words.saver == true, limited = words.limited == true,
    on_battery = name == "discharging", wireless = words.wireless == true, fast = words.fast == true,
    slow = words.slow == true, watts = tonumber(text:match("watts=(%d+)")), limit = limit }
end

-- The power-supply tree a stand-in stands for.
local KERNEL = { charging = "Charging", fully_charged = "Full", pending_charge = "Not charging",
  pending_discharge = "Not charging", discharging = "Discharging" }
local function fake_tree(v)
  local input
  if not v.on_battery then
    if v.wireless then input = { type = "Wireless", volts = 9, amps = v.fast and 2 or 1.11 }
    elseif v.slow then input = { type = "USB", usb_type = "[SDP] DCP PD", volts = 5, amps = 0.5 }
    elseif v.fast then input = { type = "USB", usb_type = "SDP DCP [PD] PD_PPS", volts = 9, amps = 3 }
    else input = { type = "USB", usb_type = "SDP [DCP] PD", volts = 5, amps = 2 } end
  end
  local watts = v.watts or (input and input.volts * input.amps * 0.9) or 4.2
  if v.on_battery == false and v.name ~= "charging" then watts = 0 end
  return { level = v.level, status = KERNEL[v.name], input = input, watts = watts, limit = v.limit, capacity = 18.2 }
end

--- A UPower in name only, for a machine without a bus. `spec` is a level and
--- any of charging, plugged, full, limited, saver, wireless, fast, slow,
--- watts=N and limit=N: "57,charging,fast,limit=80". Its power supplies are a
--- tree of real files in the cache, read and written as the kernel's are.
--- `morf ipc call fake-battery SPEC` moves it.
function M.stand_in(spec)
  local charger = require("lib.services.charger")
  local dir = morf.paths.cache("fake-power-supply")
  local first = fake_values(spec)
  charger.fixture(dir, fake_tree(first))
  local revision = morf.signal("eva.battery.stand-in", 0)
  local state = morf.state { available = true, on_battery = first.on_battery,
    lid_is_closed = false, lid_is_present = false, devices = {}, peripherals = {},
    display = { present = true, percentage = first.level, state = first.name, time_to_empty = 0, time_to_full = 0,
      charging = first.name == "charging" or first.name == "pending_charge", icon_name = "", energy_rate = 0,
      kind = "battery", warning_level = "none" },
    profiles = { available = true, service = "", degraded = "", active = first.saver and "power-saver" or "balanced",
      list = { { name = "power-saver", driver = "" }, { name = "balanced", driver = "" },
        { name = "performance", driver = "" } } } }
  local stand_in = { state = state, power_supply = dir,
    charge_limit = function()
      revision:get()
      local feed = charger.read(dir)
      return feed.limit, feed.start
    end,
    charger = function() revision:get() return charger.read(dir) end,
    set_profile = function(id) state.profiles.active = id end }
  local cached, cached_at
  function stand_in.sysinfo()
    local now = revision:get()
    if cached_at ~= now then cached, cached_at = charger.sysinfo(dir), now end
    return cached
  end
  --- A limit written into the tree shows at once.
  function stand_in.moved() revision:set(revision:get() + 1) end
  morf.ipc["fake-battery"] = function(next_spec)
    local v = fake_values(next_spec)
    charger.fixture(dir, fake_tree(v))
    state.on_battery = v.on_battery
    state.display.percentage = v.level
    state.display.state = v.name
    state.display.charging = v.name == "charging" or v.name == "pending_charge"
    state.profiles.active = v.saver and "power-saver" or "balanced"
    stand_in.moved()
    return true
  end
  return stand_in
end

return M
