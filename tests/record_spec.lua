-- eva-record: its command line against stand-in programs, a real process that
-- finishes on SIGINT, and its window.
--
--     morf test --no-dbus tests/record_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"

local function host()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
end

local function cli(args, log, env)
  local state = morf.env("XDG_STATE_HOME")
  log = log or (state .. "/record-" .. tostring(morf.time.now_ms()) .. ".log")
  if not morf.fs.exists(log) then morf.fs.write(log, "") end
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "STUB_LOG=" .. log, "MORF=" .. BIN .. "/morf",
    "SWAYSOCK=/nonexistent/sway", "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR") }
  for _, word in ipairs(env or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/record/cli"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.ipc("run", table.unpack(argv))
  local result = test.wait(function() return test.ipc("result") end, 5000, "the tool answered")
  return result, morf.fs.read(log) or "", log
end

local function dry(args)
  local result = cli(args, nil, { "EVA_DRY_RUN=1" })
  test.truthy(result.ok)
  return result.stderr
end

test.it("never records a window with -w focused", function()
  host()
  local words = dry { "window" }
  test.falsy(words:find("focused", 1, true))
  test.contains(words, "-w region -region 70x80+5+6")
end)

test.it("records a region and a monitor", function()
  host()
  test.contains(dry { "region" }, "-w region -region 300x200+10+20")
  test.contains(dry { "monitor" }, "-w DP-1")
end)

test.it("takes the sound asked for", function()
  host()
  test.falsy(dry({ "monitor" }):find(" -a ", 1, true))
  test.contains(dry { "monitor", "--audio", "desktop" }, "-a default_output")
  test.contains(dry { "monitor", "--audio", "mic" }, "-a default_input")
  test.contains(dry { "monitor", "--audio", "both" }, "-a default_output|default_input")
end)

test.it("refuses a sound it does not know", function()
  host()
  local result = cli { "monitor", "--audio", "loud" }
  test.falsy(result.ok)
  test.contains(result.stderr, "--audio takes")
end)

test.it("starts, refuses a second, and stops with SIGINT", function()
  host()
  local result, _, log = cli({ "monitor" })
  test.truthy(result.ok)
  test.contains(result.stdout, ".mp4")
  test.eq(cli({ "status" }, log).stdout, "recording\n")
  local again = cli({ "monitor" }, log)
  test.falsy(again.ok)
  test.contains(again.stderr, "already recording")
  local stopped, calls = cli({ "stop" }, log)
  test.truthy(stopped.ok)
  test.contains(calls, "recorder stopped")
  test.eq(cli({ "status" }, log).stdout, "idle\n")
end)

test.it("offers Open on the recording itself, and no Edit", function()
  host()
  local result, _, log = cli({ "monitor" }, nil, { "STUB_NOTIFY=open" })
  local file = result.stdout:match("%S+")
  cli({ "stop" }, log, { "STUB_NOTIFY=open" })
  test.wait(function() return (morf.fs.read(log) or ""):find("xdg-open", 1, true) end, 5000, "Open ran")
  local calls = morf.fs.read(log)
  test.contains(calls, "xdg-open " .. file)
  test.contains(calls, "--icon=")
  test.falsy(calls:find("--action=edit", 1, true))
end)

test.it("says when nothing is recording", function()
  host()
  local result = cli { "stop" }
  test.falsy(result.ok)
  test.contains(result.stderr, "nothing is recording")
end)

test.it("shows the choices in its window", function()
  test.load("../apps/record/app.lua", { env = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_DRY_RUN = "1" } })
  test.settle(500)
  test.click { id = "record-window" }
  test.click { id = "record-both" }
  test.settle(200)
  local state = test.ipc("state")
  test.eq(state.target, "window")
  test.eq(state.audio, "both")
  test.truthy(test.find { id = "record-start" })
  test.eq(#test.logs("error"), 0)
end)

test.it("shows its indicator", function()
  test.load("../apps/record/app.lua", {
    args = { "indicator" },
    env = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_DRY_RUN = "1" },
  })
  test.settle(200)
  test.truthy(test.find { id = "record-indicator" })
  test.eq(#test.logs("error"), 0)
end)
