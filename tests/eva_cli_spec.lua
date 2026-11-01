-- `eva`, the command line (apps/bin/eva), against a stand-in morf: verbs,
-- deep links, the list of commands, and a shell that is not there.
--
--     morf test --no-dbus tests/eva_cli_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local STUB = ROOT .. "tests/fixtures/bin/morf"

local function host()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
end

-- Runs the command with `args`; answers its result and the calls morf saw.
local function eva(args, up)
  local log = morf.env("XDG_STATE_HOME") .. "/eva-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "MORF=" .. STUB, "STUB_LOG=" .. log, "STUB_UP=" .. (up and "1" or ""),
    "HOME=" .. morf.env("XDG_STATE_HOME"), "sh", ROOT .. "apps/bin/eva" }
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.ipc("run", table.unpack(argv))
  local done = test.wait(function() return test.ipc("result") end, 5000, "eva answered")
  return done, morf.fs.read(log) or ""
end

test.it("passes a verb to the running shell", function()
  host()
  local result, calls = eva({ "dashboard", "open" }, true)
  test.truthy(result.ok)
  test.contains(calls, "ipc call dashboard open")
end)

test.it("opens a settings page by its deep link", function()
  host()
  local result, calls = eva({ "open", "settings/power" }, true)
  test.truthy(result.ok)
  test.contains(calls, "ipc call settings power")
end)

test.it("opens a nested settings page and a panel tab", function()
  host()
  local _, calls = eva({ "open", "settings/sound/equalizer" }, true)
  test.contains(calls, "ipc call settings sound/equalizer")
  _, calls = eva({ "open", "sidebar/notifications" }, true)
  test.contains(calls, "ipc call sidebar open notifications")
end)

test.it("says so when the shell is not running", function()
  host()
  local result, calls = eva({ "dashboard", "open" }, false)
  test.falsy(result.ok)
  test.contains(result.stderr, "the shell is not running")
  test.falsy(calls:find("ipc call", 1, true))
end)

test.it("reaches the capture tool with or without the shell", function()
  host()
  local _, calls = eva({ "screenshot", "region" }, true)
  test.contains(calls, "ipc call screenshot region")
  local result, alone = eva({ "screenshot", "region" }, false)
  test.truthy(result.ok)
  test.contains(alone, "app.lua -- screenshot region")
  _, alone = eva({ "open", "capture" }, false)
  test.contains(alone, "-- capture open")
  _, alone = eva({ "open", "record" }, false)
  test.contains(alone, "-- capture open")
end)

test.it("lists the capture tool by both its names", function()
  host()
  local result = eva({ "tools" }, true)
  test.contains(result.stdout, "screenshot\n")
  test.contains(result.stdout, "record\n")
end)

test.it("refuses a target it does not know", function()
  host()
  local result = eva({ "open", "nowhere" }, true)
  test.falsy(result.ok)
  test.contains(result.stderr, "no such target: nowhere")
end)

test.it("lists the verbs as JSON, marking the ones the shell answers", function()
  host()
  local result = eva({ "commands", "--json" }, true)
  test.truthy(result.ok)
  local list = morf.json.decode(result.stdout)
  local seen = {}
  for _, entry in ipairs(list) do seen[entry.verb] = entry end
  test.truthy(seen.launcher.available)
  test.falsy(seen.record.available)
  test.contains(seen.settings.description, "Settings")
end)

test.it("lists the verbs with no shell at all", function()
  host()
  local result = eva({ "commands", "--json" }, false)
  test.truthy(result.ok)
  test.truthy(#morf.json.decode(result.stdout) > 10)
end)
