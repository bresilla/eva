-- What feeds the battery: /sys/class/power_supply, read with `morf.fs`. Which
-- input is online and of what kind, how much flows into the cell, and the
-- kernel's charge thresholds where the driver has them.
--
--   local charger = require("lib.services.charger")
--   local feed = charger.read()      -- { kind, protocol, watts, fast, ... }
--   charger.set_limit(80)            -- true, or nil and why
--
-- Reading needs nothing. The threshold files are root's unless a udev rule
-- hands them over (nix/nixos/convertible.nix does, for its group): `writable`
-- says which, and `set_limit` answers why not. UPower's own switch over its
-- fixed thresholds is `supported`, `enabled` and `enable`; polkit lets an
-- active session use it. `dir` is the fixture seam, as for lib.services.torch.
local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local M = { DIR = "/sys/class/power_supply", FAST = 15, SLOW = 7.5, LOWEST = 50 }

local UPOWER, DEVICE = "org.freedesktop.UPower", "org.freedesktop.UPower.Device"
local END_FILE, START_FILE = "charge_control_end_threshold", "charge_control_start_threshold"
local INPUTS = { USB = "usb", Wireless = "wireless", Mains = "mains" }
-- The kernel's micro-units, as whole units of the product of two of them.
local MICRO, MICRO2 = 1e6, 1e12

local function text_at(path)
  local ok, text = pcall(morf.fs.read, path)
  return ok and type(text) == "string" and text or nil
end
local function word_at(path)
  local text = text_at(path)
  return text and text:match("%S+") or nil
end
local function number_at(path)
  local text = text_at(path)
  return text and tonumber(text:match("%-?%d+")) or nil
end

-- The chosen word of a list such as "SDP DCP [PD_PPS] PD", or a lone word.
local function chosen(text)
  if not text then return nil end
  return text:match("%[([^%]]+)%]") or text:match("^%s*(%S+)%s*$")
end

local function own_battery(dir)
  local ok, entries = pcall(morf.fs.list, dir, { follow = true })
  for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
    local base = dir .. "/" .. entry.name
    if word_at(base .. "/type") == "Battery" and word_at(base .. "/scope") ~= "Device" then
      return base, entry.name
    end
  end
end

-- The online input offering the most: `{ kind, protocol, offered, volts, amps }`.
local function best_input(dir)
  local ok, entries = pcall(morf.fs.list, dir, { follow = true })
  local best
  for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
    local base = dir .. "/" .. entry.name
    local kind = INPUTS[word_at(base .. "/type") or ""]
    if kind and number_at(base .. "/online") == 1 then
      local volts = number_at(base .. "/voltage_max") or number_at(base .. "/voltage_now")
      local amps = number_at(base .. "/current_max") or number_at(base .. "/input_current_limit")
      local offered = volts and amps and math.abs(volts * amps) / MICRO2 or 0
      if not best or offered > best.offered then
        best = { kind = kind, protocol = chosen(text_at(base .. "/usb_type")), offered = offered,
          volts = volts and volts / MICRO or nil, amps = amps and amps / MICRO or nil }
      end
    end
  end
  return best
end

-- What flows into or out of the cell, in watts.
local function flow(base)
  local power = number_at(base .. "/power_now")
  if power then return math.abs(power) / MICRO end
  local current, voltage = number_at(base .. "/current_now"), number_at(base .. "/voltage_now")
  if current and voltage then return math.abs(current * voltage) / MICRO2 end
end

-- The cell's size in watt-hours.
local function capacity(base)
  local energy = number_at(base .. "/energy_full")
  if energy then return energy / MICRO end
  local charge, voltage = number_at(base .. "/charge_full"), number_at(base .. "/voltage_now")
  if charge and voltage then return charge * voltage / MICRO2 end
end

--- The present feed: `present` (a battery), `status`, `level`, `kind` (usb,
--- wireless, mains or nil), `protocol` (PD, DCP and so on), `offered` and
--- `watts` (what the input can give and what reaches the cell), `volts`,
--- `amps`, `capacity`, `limit`, `start`, `fast`, `slow` and `wireless`.
function M.read(dir)
  dir = dir or M.DIR
  local base, name = own_battery(dir)
  if not base then return { present = false, fast = false, slow = false, wireless = false } end
  local input = best_input(dir) or {}
  local status = (text_at(base .. "/status") or "Unknown"):match("^%s*(.-)%s*$")
  local charging = status == "Charging"
  local watts = charging and flow(base) or nil
  if watts == 0 then watts = nil end
  local rate = watts or (charging and input.offered and input.offered > 0 and input.offered) or nil
  local portable = input.kind == "usb" or input.kind == "wireless"
  return {
    present = true, name = name, status = status, level = number_at(base .. "/capacity"),
    kind = input.kind, protocol = input.protocol, offered = input.offered, volts = input.volts, amps = input.amps,
    watts = watts, capacity = capacity(base),
    limit = number_at(base .. "/" .. END_FILE), start = number_at(base .. "/" .. START_FILE),
    fast = portable and rate ~= nil and rate >= M.FAST,
    slow = portable and rate ~= nil and rate < M.SLOW,
    wireless = input.kind == "wireless",
  }
end

--- Seconds to bring the cell from `level` to `target` percent at `watts`, or 0
--- where that cannot be told.
function M.seconds_to(level, target, size, watts)
  if not (level and target and size and watts) or watts <= 0 or level >= target then return 0 end
  return (target - level) / 100 * size / watts * 3600
end

--- The file the charge limit is written to, or nil on a driver without one.
function M.limit_file(dir)
  local base = own_battery(dir or M.DIR)
  local path = base and base .. "/" .. END_FILE
  return path and morf.fs.exists(path) and path or nil
end

--- `done(true)` when this session may write the limit.
function M.writable(done, dir)
  local path = M.limit_file(dir)
  if not path then done(false) return end
  local ok = pcall(morf.process.run, { "test", "-w", path }, { timeout_ms = 2000 }, function(result)
    done(result ~= nil and result.ok == true)
  end)
  if not ok then done(false) end
end

-- One sysfs attribute, written in place. True, or nil and why.
local function write(path, value)
  local ok, written, why = pcall(morf.fs.write, path, tostring(value), { atomic = false })
  if not ok then return nil, tostring(written) end
  if not written then return nil, tostring(why or "the kernel refused it") end
  return true
end

--- Charging stops at `value` percent. True, or nil and why.
function M.set_limit(value, dir)
  dir = dir or M.DIR
  local base = own_battery(dir)
  if not base or not morf.fs.exists(base .. "/" .. END_FILE) then return nil, "this battery has no charge limit" end
  value = math.max(M.LOWEST, math.min(100, math.floor((tonumber(value) or 100) + 0.5)))
  -- The start threshold goes below the new end first.
  local start = number_at(base .. "/" .. START_FILE)
  if start and start >= value then
    local done, why = write(base .. "/" .. START_FILE, value - 5)
    if not done then return nil, why end
  end
  return write(base .. "/" .. END_FILE, value)
end

-- ---------------------------------------------------------------- UPower --

--- UPower's own threshold switch on the battery at `path`. `options.dbus` is
--- the bus seam. `get()` answers `{ supported, enabled, start, stop }`.
function M.upower(path, options)
  options = options or {}
  local client = dbus_client.new({ dbus = options.dbus, bus = "system" })
  local u = {}
  function u.get()
    if not path or not client.has_owner(UPOWER) then return { supported = false } end
    local p = client.get_all(UPOWER, path, DEVICE) or {}
    return { supported = p.ChargeThresholdSupported == true, enabled = p.ChargeThresholdEnabled == true,
      start = p.ChargeStartThreshold, stop = p.ChargeEndThreshold }
  end
  --- Turns it on or off. `done(ok, err)`.
  function u.enable(on, done)
    return client.call_async(UPOWER, path, DEVICE, "EnableChargeThreshold", { on == true }, 25000, function(reply, err)
      if done then done(reply ~= nil, err) end
    end)
  end
  return u
end

-- ------------------------------------------------------------ the stand-in --

local function put(path, value) morf.fs.write(path, tostring(value) .. "\n", { parents = true }) end

--- A power-supply tree under `dir`, for the specs and EVA_FAKE_BATTERY. `spec`:
--- `level`, `status`, `watts`, `input` (`{ type, usb_type, volts, amps }`),
--- `limit`, `start`.
function M.fixture(dir, spec)
  morf.fs.remove(dir, { recursive = true })
  local bat = dir .. "/BAT0"
  local size = spec.capacity or 18
  local volts = 3.9
  put(bat .. "/type", "Battery")
  put(bat .. "/status", spec.status or "Discharging")
  put(bat .. "/capacity", spec.level or 50)
  put(bat .. "/energy_full", math.floor(size * MICRO))
  put(bat .. "/energy_full_design", math.floor(size * 1.08 * MICRO))
  put(bat .. "/energy_now", math.floor(size * (spec.level or 50) / 100 * MICRO))
  put(bat .. "/power_now", math.floor((spec.watts or 0) * MICRO))
  put(bat .. "/voltage_now", math.floor(volts * MICRO))
  put(bat .. "/cycle_count", 212)
  put(bat .. "/temp", 312)
  put(bat .. "/manufacturer", "Stand-in")
  put(bat .. "/model_name", "BAT0")
  put(bat .. "/technology", "Li-ion")
  if spec.limit then put(bat .. "/" .. END_FILE, spec.limit) end
  if spec.start then put(bat .. "/" .. START_FILE, spec.start) end
  if spec.input then
    local input = dir .. "/" .. spec.input.type:lower()
    put(input .. "/type", spec.input.type)
    put(input .. "/online", 1)
    if spec.input.usb_type then put(input .. "/usb_type", spec.input.usb_type) end
    put(input .. "/voltage_max", math.floor(spec.input.volts * MICRO))
    put(input .. "/current_max", math.floor(spec.input.amps * MICRO))
  end
end

--- The tree under `dir` as lib.services.sysinfo's `battery()` has it.
function M.sysinfo(dir)
  local base, name = own_battery(dir)
  if not base then return { batteries = {}, present = false } end
  local feed = M.read(dir)
  local size = feed.capacity or 0
  local now = (number_at(base .. "/energy_now") or 0) / MICRO
  local full, design = size, (number_at(base .. "/energy_full_design") or 0) / MICRO
  local watts = flow(base)
  local battery = {
    name = name, status = feed.status, capacity = feed.level, power = watts, voltage = number_at(base .. "/voltage_now") / MICRO,
    energy = now, energy_full = full, energy_design = design, cycles = number_at(base .. "/cycle_count"),
    temperature = (number_at(base .. "/temp") or 0) / 10, vendor = word_at(base .. "/manufacturer") or "",
    model = word_at(base .. "/model_name") or "", technology = word_at(base .. "/technology") or "",
    charge_limit = feed.limit, charge_start = feed.start, health = design > 0 and 100 * full / design or nil,
  }
  local charging = feed.status == "Charging"
  return { batteries = { battery }, present = true, ac = feed.kind ~= nil, status = feed.status,
    time_to_full = charging and watts and watts > 0 and M.seconds_to(feed.level, 100, size, watts) or nil,
    time_left = feed.status == "Discharging" and watts and watts > 0 and 3600 * now / watts or nil }
end

return M
