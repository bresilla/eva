-- eva-audio against the stand-in for morf.audio: the shell's own pages in a
-- window, recording streams and their routes, input channels, the equalizer as
-- a guest of the shell's file, and the command line. PipeWire is never reached.
--
--     morf test --no-dbus tests/audio_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"

local serial = 0
local function fresh()
  serial = serial + 1
  local state = morf.env("XDG_STATE_HOME") .. "/audio-" .. serial .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  return state
end

local function window(style, env, size)
  local state = fresh()
  local appearance = state .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style, font = "" })
  local full = { XDG_STATE_HOME = state, EVA_FAKE_AUDIO = "1", EVA_SETTINGS = state .. "/shell/eva.json",
    LULE_A = "/nonexistent/lule", EVA_APPEARANCE = appearance, MORF_APP = "1" }
  for key, value in pairs(env or {}) do full[key] = value end
  test.stub_run("env", { code = 1 })
  test.load("../apps/audio/app.lua", { env = full, size = size })
  test.settle(500)
  return full
end

local function ids(rows)
  local out = {}
  for _, row in ipairs(rows) do out[#out + 1] = row.id end
  return out
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("shows what plays, each on its page, in " .. style, function()
    window(style)
    test.truthy(test.get("sound-output-volume").visible)
    test.eq(ids(test.ipc("state").streams), { 30, 31 })
    test.ipc("tab", "input")
    test.settle(300)
    test.eq(ids(test.ipc("state").streams), { 40 })
    test.eq(ids(test.ipc("state").devices), { 20, 21 })
    test.eq(#test.logs("error"), 0)
  end)

  test.it("sends a recording to another input and mutes it, in " .. style, function()
    window(style)
    test.ipc("tab", "input")
    test.settle(300)
    test.truthy(test.get("sound-app-40-volume").visible)
    test.truthy(test.find { text = "Record from" })
    test.resize_window("Audio", 620, 1500)
    test.advance(300)
    test.settle(200)
    test.click("sound-app-40-to-21")
    test.settle(200)
    test.eq(test.ipc("state").streams[1].device, 21)
    test.click("sound-app-40-mute")
    test.settle(200)
    test.truthy(test.ipc("state").streams[1].muted)
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("a recording cannot be sent to an output, nor a player to an input", function()
  window("material")
  test.falsy(test.ipc("route", "output", "30", "20"))
  test.ipc("tab", "input")
  test.settle(300)
  test.falsy(test.ipc("route", "input", "40", "10"))
end)

test.it("each channel of the input has its own slider", function()
  window("material")
  test.ipc("tab", "input")
  test.settle(300)
  test.truthy(test.get("sound-input-channel-2").visible)
  test.truthy(test.ipc("channel", "input", "2", "0.25"))
  test.settle(200)
  test.near(test.ipc("state").default.volumes[2], 0.25, 0.001)
  test.near(test.ipc("state").default.volumes[1], 0.55, 0.001)
end)

test.it("the pages take the window's width when it changes", function()
  window("material")
  local wide = test.get("sound-output-volume").width
  test.resize_window("Audio", 420, 700)
  test.advance(400)
  test.settle(300)
  test.truthy(test.get("sound-output-volume").width < wide - 150)
end)

test.it("edits the file beside the shell's settings, and starts no filter", function()
  local env = window("material")
  test.ipc("tab", "equalizer")
  test.settle(300)
  test.truthy(test.ipc("equalizer", "on"))
  test.ipc("band", "3", "6")
  test.advance(600)
  test.settle(100)
  local path = env.XDG_STATE_HOME .. "/shell/eva-equalizer.json"
  test.truthy(morf.json.decode(morf.fs.read(path)).enabled)
  for _, run in ipairs(test.runs()) do
    test.falsy(run[1] == "wireplumber" or run[1] == "pipewire", "a filter was started")
  end
end)

test.it("says the filter needs the shell when none answers", function()
  window("material")
  test.ipc("tab", "equalizer")
  test.settle(800)
  test.falsy(test.ipc("state").shell)
  test.truthy(test.find { text_contains = "the shell is not running" })
end)

test.it("takes what the shell says of the filter", function()
  test.clear_stubs()
  test.stub_run("env", { code = 0, stdout = [[{"n":1,"ok":true,"result":["{\"status\":\"on\",\"error\":\"\",\"auto\":\"headphones\"}"]}]] })
  local state = fresh()
  test.load("../apps/audio/app.lua", { env = { XDG_STATE_HOME = state, EVA_FAKE_AUDIO = "1", MORF_APP = "1",
    EVA_SETTINGS = state .. "/shell/eva.json", LULE_A = "/nonexistent/lule" } })
  test.settle(800)
  test.truthy(test.ipc("state").shell)
  test.clear_stubs()
end)

test.it("opens the audiogram one level in, and comes back", function()
  window("material")
  test.ipc("tab", "equalizer")
  test.settle(300)
  test.ipc("editor", "open")
  test.settle(300)
  test.truthy(test.ipc("state").editing)
  test.truthy(test.get("audiogram-save").visible)
  test.click("audio-audiogram-head-back")
  test.settle(300)
  test.falsy(test.ipc("state").editing)
end)

test.it("restarts the sound server only when not held back", function()
  window("material", { EVA_DRY_RUN = "1" })
  test.ipc("restart")
  test.settle(100)
  for _, run in ipairs(test.runs()) do test.falsy(run[1] == "systemctl") end
end)

-- --------------------------------------------------------------------- jobs --

local function job(args)
  local state = fresh()
  local out = state .. "/answer"
  test.load("../apps/audio/app.lua", { args = args, env = { EVA_FAKE_AUDIO = "1", EVA_JOB_OUT = out } })
  test.advance(300)
  test.settle(100)
  return morf.fs.read(out) or ""
end

test.it("next makes the following output the default", function()
  test.contains(job { "next" }, "0\nHeadset")
end)

test.it("next input leaves the monitors out", function()
  test.contains(job { "next", "input" }, "0\nHeadset microphone")
end)

test.it("lists the devices and the apps, its own monitors aside", function()
  local text = job { "list" }
  test.contains(text, "* Built-in speakers 70%")
  test.contains(text, "> Firefox 80%")
  test.contains(text, "< OBS Studio")
  test.eq(text:find("spectrum", 1, true), nil)
end)

test.it("says when a command is not known", function()
  test.contains(job { "sideways" }, "1\nunknown command")
end)

local function cli(args)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/audio-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"), "sh", ROOT .. "apps/audio/cli" }
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.clear_stubs()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or "", test.ipc("result")
end

test.it("the command line asks the tool's own job", function()
  test.contains(cli { "next", "input" }, "app " .. ROOT .. "apps/audio/app.lua -- next input")
end)

test.it("its help is its header", function()
  local _, result = cli { "--help" }
  test.contains(result.stdout, "eva-audio next input")
end)
