-- The charge limit: lib/services/charge_limit.lua against a stand-in busctl, no
-- real bus; eva-battery reaching that module; the Power page setting it.
--
--     morf test --no-dbus tests/battery_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"

local function log_file()
  local log = morf.env("XDG_STATE_HOME") .. "/battery-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  return log
end

-- A host running the module's job as eva-battery would, its programs the
-- stand-ins.
local HOST = [[
  local morf = require("morf")
  local ui = require("morf.ui")
  ui.Item { width = 1, height = 1 }
  local run = morf.process.run
  morf.process.run = function(argv, options, done)
    local wrapped = { "env", "PATH=" .. morf.env("STUB_PATH"), "STUB_LOG=" .. morf.env("STUB_LOG"),
      "STUB_LIMIT=" .. (morf.env("STUB_LIMIT") or "true") }
    for _, word in ipairs(argv) do wrapped[#wrapped + 1] = word end
    return run(wrapped, options, done)
  end
  local answer
  morf.ipc.job = function(...)
    answer = nil
    require("lib.services.charge_limit").job({ ... }, function(text, why) answer = { text = text, why = why } end)
    return true
  end
  morf.ipc.answer = function() return answer end
]]

local function job(args, env)
  local log = log_file()
  local full = { STUB_PATH = BIN .. ":" .. morf.env("PATH"), STUB_LOG = log }
  for key, value in pairs(env or {}) do full[key] = value end
  test.load("../shell/init.lua", { source = HOST, env = full })
  test.ipc("job", table.unpack(args))
  local answer = test.wait(function() return test.ipc("answer") end, 5000, "the job answered")
  return answer, morf.fs.read(log) or ""
end

test.it("reports the charge and the limit", function()
  local answer = job { "status" }
  test.contains(answer.text, "charge 73%")
  test.contains(answer.text, "limit false")
  test.contains(answer.text, "between 40 and 80")
end)

test.it("leaves the limit out where the battery has none", function()
  local answer = job({ "status" }, { STUB_LIMIT = "false" })
  test.contains(answer.text, "charge 73%")
  test.falsy(answer.text:find("limit", 1, true))
end)

test.it("turns the limit on through UPower", function()
  local answer, calls = job { "limit", "on" }
  test.eq(answer.text, "limit on")
  test.contains(calls, "EnableChargeThreshold b true")
  test.contains(calls, "battery_BAT0")
end)

test.it("holds back under EVA_DRY_RUN", function()
  local answer, calls = job({ "limit", "off" }, { EVA_DRY_RUN = "1" })
  test.eq(answer.text, "dry run")
  test.falsy(calls:find("EnableChargeThreshold", 1, true))
end)

test.it("says so where the battery cannot", function()
  local answer, calls = job({ "limit", "on" }, { STUB_LIMIT = "false" })
  test.falsy(answer.text)
  test.contains(answer.why, "no charge limit")
  test.falsy(calls:find("EnableChargeThreshold", 1, true))
end)

test.it("takes on, off or a percentage and nothing else", function()
  test.contains(job({ "limit", "sideways" }).why, "on, off or a percentage")
  test.contains(job({ "limit", "20" }).why, "from 50 to 100")
end)

-- A power-supply folder, as the kernel lays it out.
local function tree(name, files)
  local dir = morf.env("XDG_STATE_HOME") .. "/supplies-" .. name
  morf.fs.remove(dir, { recursive = true })
  for path, value in pairs(files) do morf.fs.write(dir .. "/" .. path, value .. "\n", { parents = true }) end
  return dir
end
local CHARGING = { ["BAT0/type"] = "Battery", ["BAT0/status"] = "Charging", ["BAT0/power_now"] = "18200000",
  ["BAT0/charge_control_end_threshold"] = "100", ["usb/type"] = "USB", ["usb/online"] = "1",
  ["usb/usb_type"] = "SDP DCP [PD] PD_PPS" }

test.it("says what feeds the battery and how fast", function()
  local answer = job({ "status" }, { EVA_POWER_SUPPLY = tree("pd", CHARGING) })
  test.contains(answer.text, "status Charging")
  test.contains(answer.text, "input USB PD")
  test.contains(answer.text, "power 18.2 W")
  test.contains(answer.text, "stops at 100")
end)

test.it("skips an input that is off, and a battery that is a peripheral's", function()
  local files = { ["AAA/type"] = "Battery", ["AAA/scope"] = "Device", ["AAA/status"] = "Full",
    ["BAT0/type"] = "Battery", ["BAT0/status"] = "Discharging", ["usb/type"] = "USB", ["usb/online"] = "0" }
  local answer = job({ "status" }, { EVA_POWER_SUPPLY = tree("off", files) })
  test.contains(answer.text, "status Discharging")
  test.falsy(answer.text:find("input", 1, true))
  test.falsy(answer.text:find("power", 1, true))
end)

test.it("holds a level back under EVA_DRY_RUN, and refuses a battery with no file", function()
  local dir = tree("dry", CHARGING)
  test.contains(job({ "limit", "80" }, { EVA_DRY_RUN = "1", EVA_POWER_SUPPLY = dir }).text, "dry run: charge limit 80")
  test.eq(morf.fs.read(dir .. "/BAT0/charge_control_end_threshold"), "100\n")
  local bare = tree("bare", { ["BAT0/type"] = "Battery", ["BAT0/status"] = "Charging" })
  test.contains(job({ "limit", "80" }, { EVA_POWER_SUPPLY = bare }).why, "no charge limit")
end)

-- ---------------------------------------------------------- the command line --

local function command(args)
  local state = morf.env("XDG_STATE_HOME")
  local log = log_file()
  local argv = { "env", "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log, "HOME=" .. state, "EVA_JOB_FAKE=1",
    "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"), "sh", ROOT .. "apps/bin/eva-battery" }
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  return test.wait(function() return test.ipc("result") end, 5000, "the tool answered"), morf.fs.read(log) or ""
end

test.it("eva-battery runs the module, not its own copy", function()
  local result, calls = command { "limit", "on" }
  test.falsy(result.ok)
  test.contains(calls, "apps/common/job/app.lua -- battery limit on")
  test.falsy(morf.fs.read(ROOT .. "apps/bin/eva-battery"):find("busctl", 1, true))
end)

test.it("refuses what it does not know", function()
  local result = command { "sideways" }
  test.falsy(result.ok)
  test.contains(result.stderr, "unknown command")
end)

-- ------------------------------------------------------------- the Power page --

local PAGE = [[
  local ui = require("morf.ui")
  local battery = { ac = false, batteries = { { name = "BAT0", capacity = 64, status = "Discharging" } } }
  package.loaded["lib.services.sysinfo"] = { history_size = 60, sources = { battery = { interval = 5000 } },
    battery = function() return battery end }
  package.loaded.services = { upower = { state = { available = true } } }
  package.loaded.dashboard_state = { show = function() end }
  morf.ipc.limit = function() return { enabled = require("charge_limit_model").on() } end
  local content = require("power_page").page(480, function() return 900 end)
  ui.Item { width = 480, height = 900, content }
  require("presentation").set("settings.power", true)
]]

local function power(env)
  local full = { EVA_DRY_RUN = "1", EVA_STYLE = "material", LULE_A = "/nonexistent/lule" }
  for key, value in pairs(env or {}) do full[key] = value end
  test.stub_run("busctl", { code = 1 })
  test.load("../shell/init.lua", { source = PAGE, env = full })
  test.settle(600)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("the Power page sets the limit in " .. style, function()
    power { EVA_FAKE_CHARGE_LIMIT = "1", EVA_STYLE = style }
    test.truthy(test.find { id = "power-limit-state", visible = true })
    test.falsy(test.ipc("limit").enabled)
    test.click("power-limit-switch")
    test.settle(400)
    test.truthy(test.ipc("limit").enabled)
    test.contains(test.get({ id = "power-limit-state-title" }).text, "Charge limit")
    test.contains(test.get({ id = "power-limit-state-subtitle" }).text, "Held by UPower")
  end)
end

test.it("the Power page hides the limit where the battery has none", function()
  power()
  local row = test.find { id = "power-limit-state" }
  test.truthy(row == nil or row.visible == false)
end)
