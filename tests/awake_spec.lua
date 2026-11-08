-- Keep awake for a time: the Focus page's dial, presets and words on the
-- shell's own keep awake, and `eva-awake`, a job that speaks only to the
-- shell's `awake` verb. The verb itself is tests/tool_verbs_spec.lua's; the
-- tile, the bar and the real verb together are tools/see/awake.steps'.
--
--     morf test --no-dbus tests/awake_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
local JOB = "../apps/common/job/app.lua"
-- Monday 2 November 2026, 10:00 UTC.
local MONDAY = 1793613600

local serial = 0
local function fresh()
  serial = serial + 1
  local state = morf.env("XDG_STATE_HOME") .. "/awake-" .. serial .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  return state
end

-- ------------------------------------------------------------- the page --

local SOURCE = [[
  require("init")
  morf.ipc.q_awake = function()
    local idle = require("idle_model")
    local stop = idle.awake_until()
    return { on = idle.awake:get(), left = stop > 0 and stop - morf.time.now() or 0 }
  end
]]

local function page(style)
  test.clear_stubs()
  test.stub_run("task", { code = 0, stdout = "[]" })
  local state = fresh()
  test.load("../shell/init.lua", { size = { 1600, 1000 }, source = SOURCE, env = { EVA_STYLE = style, EVA_DRY_RUN = "1",
    XDG_STATE_HOME = state, EVA_SETTINGS = state .. "/eva.json", HOME = morf.env("XDG_CACHE_HOME"), EVA_WALLPAPER = "" } })
  test.settle(1000)
  test.ipc("settings", "focus") test.settle(1500)
  return state
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
  test.it("a preset keeps the session awake, and the dial shows it, in " .. style, function()
    page(style)
    test.eq(test.get("awake-left").text, "Off")
    test.click(reach("awake-preset-60")) test.settle(200)
    local now = test.ipc("q_awake")
    test.truthy(now.on)
    test.near(now.left, 3600, 5)
    test.contains(test.get("awake-until").text, "Until ")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("takes the time however it is said", function()
  page("material")
  test.click(reach("awake-words")) test.type("45 min") test.settle(100)
  test.truthy(test.find { id = "awake-hint", visible = true }, "the words were not read back")
  test.key("Return") test.settle(200)
  test.near(test.ipc("q_awake").left, 45 * 60, 5)
end)

test.it("says what it needs when the words make no time", function()
  page("material")
  test.click(reach("awake-words")) test.type("whenever") test.settle(50)
  test.click(reach("awake-words-go")) test.settle(100)
  test.contains(test.get("awake-hint").text, "Say a time")
  test.falsy(test.ipc("q_awake").on)
end)

test.it("follows the Interruptions' switch, one state with the tile", function()
  page("material")
  test.click(reach("utilities-toggle-awake")) test.settle(200)
  test.truthy(test.ipc("q_awake").on)
  test.eq(test.get("awake-left").text, "On")
  test.click(reach("utilities-toggle-awake")) test.settle(200)
  test.eq(test.get("awake-left").text, "Off")
end)

test.it("never holds an inhibitor of its own", function()
  test.eq(morf.fs.read(ROOT .. "shell/awake_model.lua"):find("idle.inhibit", 1, true), nil)
end)

-- --------------------------------------------------------------------- jobs --

-- The shell's answer, as `morf ipc call` gives it.
local function answer(on, stop)
  return { code = 0, stdout = ([[{"n":1,"ok":true,"result":["{\"on\":%s,\"until\":%s}"]}]]):format(tostring(on), tostring(stop)) }
end

local function verbs()
  local out = {}
  for _, run in ipairs(test.runs()) do
    if run[1] == "env" then out[#out + 1] = table.concat(run, " ", 6) end
  end
  return out
end

local function job(args, reply, env)
  test.clear_stubs()
  if reply then test.stub_run("env", reply) end
  local state = fresh()
  local out = state .. "/answer"
  local full = { EVA_JOB_OUT = out, XDG_STATE_HOME = state, EVA_NOW = tostring(MONDAY) }
  for key, value in pairs(env or {}) do full[key] = value end
  local words = { "awake" }
  for _, word in ipairs(args) do words[#words + 1] = word end
  test.load(JOB, { args = words, env = full })
  test.settle(200)
  return out
end

local function read(out) return morf.fs.read(out) or "" end

test.it("status says how things stand", function()
  test.contains(read(job({ "status" }, answer(true, MONDAY + 1800))), "0\non until ")
  test.contains(read(job({ "status" }, answer(true, MONDAY + 1800))), "30 min left")
  test.contains(read(job({ "status" }, answer(true, 0))), "on until told otherwise")
  test.contains(read(job({ "status" }, answer(false, 0))), "0\noff")
end)

test.it("30m is thirty minutes of the shell's", function()
  job({ "30m" }, answer(true, MONDAY + 1800))
  test.contains(verbs()[1], "call awake on 30")
end)

test.it("words are minutes however they are said", function()
  for _, case in ipairs { { "45 min", 45 }, { "2 hours", 120 }, { "1h30", 90 } } do
    local words = {}
    for word in case[1]:gmatch("%S+") do words[#words + 1] = word end
    job(words, answer(true, MONDAY + 60))
    test.contains(verbs()[1], "call awake on " .. case[2], case[1])
  end
end)

test.it("off lets go", function()
  job({ "off" }, answer(false, 0))
  test.contains(verbs()[1], "call awake off")
end)

test.it("a job with no shell fails and says so", function()
  test.contains(read(job({ "status" }, { code = 1 })), "1\nThe shell is not running")
end)

test.it("--pid refuses what is not a process", function()
  test.contains(read(job({ "--pid", "banana" }, answer(true, 0))), "1\nno process banana")
  test.contains(read(job({ "--pid", "424242" }, answer(true, 0), { EVA_PROC_ROOT = fresh() })), "1\nno process 424242")
end)

test.it("--pid holds while the process lives, then lets go", function()
  local proc = fresh()
  morf.fs.mkdir(proc .. "/77")
  local out = job({ "--pid", "77" }, answer(true, 0), { EVA_PROC_ROOT = proc })
  test.contains(verbs()[1], "call awake on")
  test.advance(5000)
  test.eq(read(out), "")
  morf.fs.remove(proc .. "/77")
  test.advance(2100)
  test.settle(200)
  test.contains(read(out), "0\nprocess 77 ended")
  local all = verbs()
  test.contains(all[#all], "call awake off")
end)

test.it("--pid leaves a time put on it since", function()
  local proc = fresh()
  morf.fs.mkdir(proc .. "/78")
  local out = job({ "--pid", "78" }, answer(true, 0), { EVA_PROC_ROOT = proc })
  test.clear_stubs()
  test.stub_run("env", answer(true, MONDAY + 600))
  morf.fs.remove(proc .. "/78")
  test.advance(2100)
  test.settle(200)
  test.contains(read(out), "ended")
  local all = verbs()
  test.contains(all[#all], "awake state")
end)

local function cli(args, env)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/awake-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR") }
  for _, word in ipairs(env or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/bin/eva-awake"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.clear_stubs()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or "", test.ipc("result")
end

test.it("the command line runs the shell's own code as a job", function()
  test.contains(cli { "--pid", "12" }, "app " .. ROOT .. "apps/common/job/app.lua -- awake --pid 12")
end)

test.it("alone it opens Focus in the Settings window", function()
  test.contains(cli({}, { "STUB_UP=1" }), "ipc call settings focus")
end)

test.it("its help is its header", function()
  local _, result = cli { "--help" }
  test.contains(result.stdout, "eva-awake --pid N")
end)
