-- The mixer that was eva-audio, in the Settings window against the stand-in for
-- morf.audio: what plays and what records, routing and channels, and the sound
-- server's restart on Sound's second page; then `eva-audio`'s words, a job on
-- shell/sound_cli.lua, and its command line. PipeWire is never reached.
--
--     morf test --no-dbus tests/audio_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"

local SOURCE = [[
  require("init")
  morf.ipc.sound = function(kind)
    local page = require("sound_page")
    local model = kind == "input" and page.input_model() or page.output_model()
    local streams = {}
    for index = 1, model.streams:len() do
      local row = model.streams:get(index)
      streams[index] = { id = row.id, device = row.device, muted = row.muted }
    end
    return { streams = streams, default = model.default() }
  end
]]

local serial = 0
local function shell(style, env, size)
  serial = serial + 1
  local all = { EVA_STYLE = style, EVA_FAKE_AUDIO = "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "",
    LULE_A = "/nonexistent/lule", HOME = morf.env("XDG_CACHE_HOME"),
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/audio-" .. serial .. ".json" }
  for key, value in pairs(env or {}) do all[key] = value end
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = size or { 1600, 1000 }, source = SOURCE, env = all })
  test.settle(1200)
end

local function ids(rows)
  local out = {}
  for _, row in ipairs(rows) do out[#out + 1] = row.id end
  return out
end

-- The Settings window's page wheeled until `id` stands in it.
local function reach(id)
  for _ = 1, 40 do
    local node, pane = test.find { id = id, visible = true }, test.get("settings-detail")
    if node and node.y > pane.y and node.y + node.height < pane.y + pane.height then return id end
    test.wheel(0, 120, { x = pane.x + pane.width / 2, y = pane.y + pane.height / 2 }) test.advance(200)
  end
  return id
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("shows what plays and what records, each on its page, in " .. style, function()
    shell(style, { EVA_DRY_RUN = "1" })
    test.ipc("settings", "sound") test.settle(1200)
    test.truthy(test.get("sound-output-volume").visible)
    test.eq(ids(test.ipc("sound", "output").streams), { 30, 31 })
    test.ipc("settings", "microphone") test.settle(1200)
    test.eq(ids(test.ipc("sound", "input").streams), { 40 })
    test.truthy(test.find { text = "Record from" })
    test.eq(#test.logs("error"), 0)
  end)

  test.it("sends a recording to another input and mutes it, in " .. style, function()
    shell(style, nil, { 1600, 1600 })
    test.ipc("settings", "microphone") test.settle(1200)
    test.click(reach("sound-app-40-to-21")) test.settle(200)
    test.eq(test.ipc("sound", "input").streams[1].device, 21)
    test.click(reach("sound-app-40-mute")) test.settle(200)
    test.truthy(test.ipc("sound", "input").streams[1].muted)
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("each channel of the input has its own slider", function()
  shell("material")
  test.ipc("settings", "microphone") test.settle(1200)
  test.truthy(test.find { id = "sound-input-channel-2" }, "no slider for the second channel")
end)

test.it("Sound's second page restarts the sound server, the session's own units", function()
  test.stub_run("systemctl", { code = 0 })
  shell("material")
  test.ipc("settings", "sound/more") test.settle(1200)
  test.click(reach("sound-restart-button")) test.settle(300)
  local ran
  for _, run in ipairs(test.runs()) do
    if run[1] == "systemctl" then ran = table.concat(run, " ") end
  end
  test.eq(ran, "systemctl --user restart wireplumber pipewire pipewire-pulse")
  test.truthy(test.find { text = "Restarted", visible = true }, "it did not say so")
end)

test.it("restarts the sound server only when not held back", function()
  shell("material", { EVA_DRY_RUN = "1" })
  test.ipc("settings", "sound/more") test.settle(1200)
  test.click(reach("sound-restart-button")) test.settle(300)
  for _, run in ipairs(test.runs()) do test.falsy(run[1] == "systemctl") end
end)

-- --------------------------------------------------------------------- jobs --

local HOST = [[
  require("morf.ui").Item { width = 1, height = 1 }
  local answer
  morf.ipc.job = function(...)
    answer = nil
    require("sound_cli").job({ ... }, function(text, why) answer = { text = text, why = why } end)
    return true
  end
  morf.ipc.answer = function() return answer end
]]

local function job(...)
  test.load("../shell/init.lua", { source = HOST, env = { EVA_FAKE_AUDIO = "1" } })
  test.ipc("job", ...)
  return test.wait(function() return test.ipc("answer") end, 4000, "the job answered")
end

test.it("next makes the following output the default", function()
  test.eq(job("next").text, "Headset")
end)

test.it("next input leaves the monitors out", function()
  test.eq(job("next", "input").text, "Headset microphone")
end)

test.it("lists the devices and the apps, its own monitors aside", function()
  local text = job("list").text
  test.contains(text, "* Built-in speakers 70%")
  test.contains(text, "> Firefox 80%")
  test.contains(text, "< OBS Studio")
  test.eq(text:find("spectrum", 1, true), nil)
end)

test.it("says when a command is not known", function()
  test.contains(job("sideways").why, "unknown command")
end)

-- ---------------------------------------------------------- the command line --

local function cli(args, env)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/audio-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR") }
  for _, word in ipairs(env or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/bin/eva-audio"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.clear_stubs()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or "", test.ipc("result")
end

test.it("the command line runs the shell's own code as a job", function()
  test.contains(cli { "next", "input" }, "app " .. ROOT .. "apps/common/job/app.lua -- audio next input")
end)

test.it("alone it opens Sound in the Settings window", function()
  local calls, result = cli({}, { "STUB_UP=1" })
  test.contains(calls, "ipc call settings sound")
  test.truthy(result.ok)
end)

test.it("alone with no shell it says Settings is the shell's", function()
  local _, result = cli {}
  test.falsy(result.ok)
  test.contains(result.stderr, "the shell is not running")
end)

test.it("its help is its header", function()
  local _, result = cli { "--help" }
  test.contains(result.stdout, "eva-audio next input")
end)
