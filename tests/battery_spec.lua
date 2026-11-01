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
