-- eva-record: its command line against stand-in programs. The recorder is the
-- capture tool's, the panel's Record: tests/capture_tool_spec.lua.
--
--     morf test --no-dbus tests/record_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"

local function host()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
end

local function cli(args, env)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/record-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "STUB_LOG=" .. log, "MORF=" .. BIN .. "/morf",
    "WAYLAND_DISPLAY=wayland-1", "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR") }
  for _, word in ipairs(env or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/bin/eva-record"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.ipc("run", table.unpack(argv))
  local result = test.wait(function() return test.ipc("result") end, 5000, "the tool answered")
  return result, morf.fs.read(log) or ""
end

local function dry(args)
  local result = cli(args, { "EVA_DRY_RUN=1" })
  test.truthy(result.ok)
  return result.stderr
end

test.it("asks the tool's recorder for what it was given", function()
  host()
  test.contains(dry { "region" }, "record region start=1 fps=60")
  test.contains(dry { "window" }, "record window start=1 fps=60")
  test.contains(dry { "monitor" }, "record screen start=1 fps=60")
  test.contains(dry { "monitor", "--fps", "30" }, "fps=30")
end)

test.it("never reaches for slurp", function()
  host()
  local _, calls = cli { "region" }
  test.falsy(calls:find("slurp", 1, true))
end)

test.it("takes the sound asked for", function()
  host()
  test.falsy(dry({ "monitor" }):find("audio=", 1, true))
  test.contains(dry { "monitor", "--audio", "desktop" }, "audio=default_output")
  test.contains(dry { "monitor", "--audio", "mic" }, "audio=default_input")
  test.contains(dry { "monitor", "--audio", "both" }, "audio=default_output|default_input")
end)

test.it("refuses a sound it does not know", function()
  host()
  local result = cli { "monitor", "--audio", "loud" }
  test.falsy(result.ok)
  test.contains(result.stderr, "--audio takes")
end)

test.it("shows the panel with no target", function()
  host()
  local _, calls = cli {}
  test.contains(calls, "-- capture open")
end)

test.it("hands a recording to the tool that is running", function()
  host()
  local _, calls = cli({ "region" }, { "STUB_TOOL=1" })
  test.contains(calls, "ipc call record region start=1")
end)

test.it("refuses a second, stops the first, and says where it went", function()
  host()
  local recording = { "STUB_TOOL=1", "STUB_RECORD=/captures/capture_1.mp4" }
  local again = cli({ "monitor" }, recording)
  test.falsy(again.ok)
  test.contains(again.stderr, "already recording")
  test.eq(cli({ "status" }, recording).stdout, "recording\n")
  local stopped, calls = cli({ "stop" }, recording)
  test.truthy(stopped.ok)
  test.contains(stopped.stdout, "capture_1.mp4")
  test.contains(calls, "ipc call record stop")
end)

test.it("says when nothing is recording", function()
  host()
  test.eq(cli({ "status" }).stdout, "idle\n")
  test.eq(cli({ "status" }, { "STUB_TOOL=1" }).stdout, "idle\n")
  local result = cli { "stop" }
  test.falsy(result.ok)
  test.contains(result.stderr, "nothing is recording")
end)
