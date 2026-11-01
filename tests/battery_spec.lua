-- eva-battery: UPower's charge limit, against a stand-in busctl; no real bus.
--
--     morf test --no-dbus tests/battery_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"

local function host()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
end

local function battery(args, env)
  local log = morf.env("XDG_STATE_HOME") .. "/battery-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "STUB_LOG=" .. log, "HOME=" .. morf.env("XDG_STATE_HOME") }
  for _, word in ipairs(env or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/bin/eva-battery"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.ipc("run", table.unpack(argv))
  local result = test.wait(function() return test.ipc("result") end, 5000, "the tool answered")
  return result, morf.fs.read(log) or ""
end

test.it("reports the charge and the limit", function()
  host()
  local result = battery { "status" }
  test.truthy(result.ok)
  test.contains(result.stdout, "charge 73%")
  test.contains(result.stdout, "limit false")
  test.contains(result.stdout, "between 40 and 80")
end)

test.it("leaves the limit out where the battery has none", function()
  host()
  local result = battery({ "status" }, { "STUB_LIMIT=false" })
  test.contains(result.stdout, "charge 73%")
  test.falsy(result.stdout:find("limit", 1, true))
end)

test.it("turns the limit on through UPower", function()
  host()
  local result, calls = battery { "limit", "on" }
  test.truthy(result.ok)
  test.contains(calls, "EnableChargeThreshold b true")
  test.contains(calls, "battery_BAT0")
end)

test.it("holds back under EVA_DRY_RUN", function()
  host()
  local result, calls = battery({ "limit", "off" }, { "EVA_DRY_RUN=1" })
  test.truthy(result.ok)
  test.contains(result.stderr, "dry run: EnableChargeThreshold false")
  test.falsy(calls:find("EnableChargeThreshold", 1, true))
end)

test.it("says so where the battery cannot", function()
  host()
  local result, calls = battery({ "limit", "on" }, { "STUB_LIMIT=false" })
  test.falsy(result.ok)
  test.contains(result.stderr, "no charge limit")
  test.falsy(calls:find("EnableChargeThreshold", 1, true))
end)

-- A power-supply folder, as the kernel lays it out.
local function tree(name, files)
  local dir = morf.env("XDG_STATE_HOME") .. "/supplies-" .. name
  morf.fs.remove(dir, { recursive = true })
  for path, value in pairs(files) do morf.fs.write(dir .. "/" .. path, value .. "\n") end
  return dir
end
local CHARGING = { ["BAT0/type"] = "Battery", ["BAT0/status"] = "Charging", ["BAT0/power_now"] = "18200000",
  ["BAT0/charge_control_end_threshold"] = "100", ["usb/type"] = "USB", ["usb/online"] = "1",
  ["usb/usb_type"] = "SDP DCP [PD] PD_PPS" }

test.it("says what feeds the battery and how fast", function()
  host()
  local result = battery({ "status" }, { "EVA_POWER_SUPPLY=" .. tree("pd", CHARGING) })
  test.contains(result.stdout, "status Charging")
  test.contains(result.stdout, "input USB PD")
  test.contains(result.stdout, "power 18.2 W")
  test.contains(result.stdout, "stops at 100")
end)

test.it("works the rate out from current and voltage", function()
  host()
  local files = { ["BAT0/type"] = "Battery", ["BAT0/status"] = "Charging", ["BAT0/current_now"] = "-2000000",
    ["BAT0/voltage_now"] = "4000000", ["coil/type"] = "Wireless", ["coil/online"] = "1" }
  local result = battery({ "status" }, { "EVA_POWER_SUPPLY=" .. tree("coil", files) })
  test.contains(result.stdout, "input Wireless")
  test.contains(result.stdout, "power 8.0 W")
end)

test.it("skips an input that is off, and a battery that is a peripheral's", function()
  host()
  local files = { ["AAA/type"] = "Battery", ["AAA/scope"] = "Device", ["AAA/status"] = "Full",
    ["BAT0/type"] = "Battery", ["BAT0/status"] = "Discharging", ["usb/type"] = "USB", ["usb/online"] = "0" }
  local result = battery({ "status" }, { "EVA_POWER_SUPPLY=" .. tree("off", files) })
  test.contains(result.stdout, "status Discharging")
  test.falsy(result.stdout:find("input", 1, true))
  test.falsy(result.stdout:find("power", 1, true))
end)

test.it("writes a level of the person's into the kernel's file", function()
  host()
  local dir = tree("level", CHARGING)
  local result = battery({ "limit", "80" }, { "EVA_POWER_SUPPLY=" .. dir })
  test.truthy(result.ok, result.stderr)
  test.eq(morf.fs.read(dir .. "/BAT0/charge_control_end_threshold"), "80")
end)

test.it("holds a level back under EVA_DRY_RUN", function()
  host()
  local dir = tree("dry", CHARGING)
  local result = battery({ "limit", "80" }, { "EVA_DRY_RUN=1", "EVA_POWER_SUPPLY=" .. dir })
  test.truthy(result.ok)
  test.contains(result.stderr, "dry run: charge limit 80")
  test.eq(morf.fs.read(dir .. "/BAT0/charge_control_end_threshold"), "100\n")
end)

test.it("refuses a level out of range or nonsense, and a battery with no file", function()
  host()
  test.contains(battery({ "limit", "20" }).stderr, "from 50 to 100")
  test.contains(battery({ "limit", "lots" }).stderr, "on, off or a percentage")
  local dir = tree("bare", { ["BAT0/type"] = "Battery", ["BAT0/status"] = "Charging" })
  test.contains(battery({ "limit", "80" }, { "EVA_POWER_SUPPLY=" .. dir }).stderr, "no charge limit")
end)
