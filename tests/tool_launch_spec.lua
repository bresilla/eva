-- apps/launch, how every tool of apps/ starts as a program of its own: finding
-- the shell's files, and one overlay at a time, a second launch answering the
-- first. eva-draw stands in for them all.
--
--     morf test --no-dbus tests/tool_launch_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local STATE = morf.env("XDG_STATE_HOME")

local function launch(env)
  local state = STATE .. "/launch-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  local log = state .. "/calls.log"
  morf.fs.write(log, "")
  if env then env(state) end
  local argv = { "env", "-u", "EVA_SETTINGS", "-u", "EVA_APPEARANCE", "MORF=" .. ROOT .. "tests/fixtures/bin/morf",
    "STUB_LOG=" .. log, "HOME=" .. state, "XDG_STATE_HOME=" .. state }
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/launch"
  argv[#argv + 1] = "draw"
  test.ipc("run", table.unpack(argv))
  local result = test.wait(function() return test.ipc("result") end, 5000, "the launcher answered")
  return result, morf.fs.read(log) or "", state
end

local function launcher_host()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
end

test.it("runs a tool as an application", function()
  launcher_host()
  local result, calls = launch()
  test.truthy(result.ok)
  test.contains(calls, "app " .. ROOT .. "apps/draw/app.lua")
end)

test.it("finds the settings the shell named", function()
  launcher_host()
  local _, calls = launch(function(state)
    morf.fs.mkdir(state .. "/eva")
    morf.fs.write(state .. "/eva/settings-path", "/named/by/the/shell.json")
  end)
  test.contains(calls, "EVA_SETTINGS=/named/by/the/shell.json")
end)

test.it("falls back on the newest settings the shell left", function()
  launcher_host()
  local _, calls = launch(function(state)
    morf.fs.mkdir(state .. "/morf/shell-abc")
    morf.fs.write(state .. "/morf/shell-abc/eva.json", "{}")
  end)
  test.contains(calls, "/morf/shell-abc/eva.json")
end)

test.it("finds the appearance the shell keeps", function()
  launcher_host()
  local _, calls = launch(function(state)
    morf.fs.mkdir(state .. "/eva/appearance")
    morf.fs.write(state .. "/eva/appearance/appearance.json", "{}")
  end)
  test.contains(calls, "/eva/appearance/appearance.json")
end)

-- The launcher with the tool already up: `sh -c` holds the tool's path in its
-- arguments, as morf would.
local function second_launch(args)
  launcher_host()
  local state = STATE .. "/guard-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  local log, run = state .. "/calls.log", state .. "/run"
  morf.fs.mkdir(run)
  morf.fs.write(log, "")
  local holder = morf.process.spawn { command = { "sh", "-c", "sleep 30; :", ROOT .. "apps/draw/app.lua" } }
  morf.fs.mkdir(run .. "/eva")
  morf.fs.write(run .. "/eva/draw.window", tostring(holder:pid()))
  local argv = { "env", "-u", "EVA_SETTINGS", "-u", "EVA_APPEARANCE", "MORF=" .. ROOT .. "tests/fixtures/bin/morf",
    "STUB_LOG=" .. log, "HOME=" .. state, "XDG_STATE_HOME=" .. state, "XDG_RUNTIME_DIR=" .. run,
    "WAYLAND_DISPLAY=wayland-9", "sh", ROOT .. "apps/launch", "draw" }
  for _, word in ipairs(args or {}) do argv[#argv + 1] = word end
  test.ipc("run", table.unpack(argv))
  local result = test.wait(function() return test.ipc("result") end, 5000, "the launcher answered")
  local calls = morf.fs.read(log) or ""
  holder:kill("KILL")
  return result, calls, holder:pid()
end

test.it("a second launch answers the first and starts nothing", function()
  local result, calls, pid = second_launch()
  test.truthy(result.ok)
  test.contains(calls, "-i wayland-9-app-" .. pid .. " ipc call eva-raise")
  test.falsy(calls:find(" app ", 1, true))
end)

test.it("a job with arguments runs beside it", function()
  local result, calls = second_launch { "--watch" }
  test.truthy(result.ok)
  test.contains(calls, "app " .. ROOT .. "apps/draw/app.lua -- --watch")
end)

test.it("a tool that ended leaves no guard behind", function()
  launcher_host()
  local result, calls = launch(function(state)
    morf.fs.mkdir(state .. "/run")
  end)
  test.truthy(result.ok)
  test.contains(calls, "app " .. ROOT .. "apps/draw/app.lua")
  local again = launch()
  test.truthy(again.ok)
end)

test.it("refuses a tool that is not there", function()
  launcher_host()
  test.ipc("run", "sh", ROOT .. "apps/launch", "nothing")
  local result = test.wait(function() return test.ipc("result") end, 5000, "the launcher answered")
  test.falsy(result.ok)
  test.contains(result.stderr, "no tool nothing")
end)
