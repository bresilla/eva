-- eva-awake: it speaks only to the shell's `awake` verb, and shows what comes
-- back. The verb itself is tests/tool_verbs_spec.lua's; the tile, the bar and
-- the real verb together are tools/see/awake.steps'.
--
--     morf test --no-dbus tests/awake_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
-- Monday 2 November 2026, 10:00 UTC.
local MONDAY = 1793613600

local serial = 0
local function fresh()
  serial = serial + 1
  local state = morf.env("XDG_STATE_HOME") .. "/awake-" .. serial .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  return state
end

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

local function window(style, reply, env)
  test.clear_stubs()
  test.stub_run("env", reply or answer(false, 0))
  local state = fresh()
  local appearance = state .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style, font = "" })
  local full = { XDG_STATE_HOME = state, EVA_NOW = tostring(MONDAY), EVA_SETTINGS = "/nonexistent/eva.json",
    LULE_A = "/nonexistent/lule", EVA_APPEARANCE = appearance }
  for key, value in pairs(env or {}) do full[key] = value end
  test.load("../apps/awake/app.lua", { env = full })
  test.settle(400)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("shows the time left the shell holds, in " .. style, function()
    window(style, answer(true, MONDAY + 1800))
    test.truthy(test.ipc("state").on)
    test.eq(test.get("awake-left").text, "30:00")
    test.contains(test.get("awake-until").text, "Until ")
    test.eq(#test.logs("error"), 0)
  end)

  test.it("a preset asks the shell, in " .. style, function()
    window(style, answer(true, MONDAY + 3600))
    test.clear_stubs()
    test.stub_run("env", answer(true, MONDAY + 3600))
    test.click("awake-preset-60")
    test.settle(200)
    test.contains(table.concat(verbs(), "\n"), "call awake on 60")
    test.eq(test.ipc("state").left, 3600)
    test.near(test.ipc("state").fraction, 1, 0.01)
  end)
end

test.it("never holds an inhibitor of its own", function()
  local source = morf.fs.read(ROOT .. "apps/awake/model.lua") .. morf.fs.read(ROOT .. "apps/awake/app.lua")
  test.eq(source:find("idle.inhibit", 1, true), nil)
end)

test.it("takes the time however it is said", function()
  window("material")
  test.stub_run("env", answer(true, MONDAY + 60))
  for _, case in ipairs {
    { "30m", 30 }, { "45 min", 45 }, { "1h", 60 }, { "2 hours", 120 }, { "1h30", 90 }, { "half an hour", 30 },
  } do
    test.truthy(test.ipc("say", case[1]), case[1])
    test.settle(50)
    local all = verbs()
    test.contains(all[#all], "call awake on " .. case[2], case[1])
  end
end)

test.it("a time of day counts from now", function()
  window("material")
  test.stub_run("env", answer(true, MONDAY + 60))
  test.truthy(test.ipc("say", "until 23:59"))
  test.settle(50)
  local all = verbs()
  local minutes = tonumber(all[#all]:match("awake on ([%d%.]+)"))
  test.truthy(minutes > 0 and minutes <= 1440)
end)

test.it("says what it needs when the words make no time", function()
  window("material")
  test.falsy(test.ipc("say", "whenever"))
  test.contains(test.ipc("state").message, "Say a time")
end)

test.it("reads the time it gave from where it left it", function()
  local state = fresh()
  morf.fs.write(state .. "/eva/awake/run.json", morf.json.encode { stop = MONDAY + 900, seconds = 1800 }, { parents = true })
  window("material", answer(true, MONDAY + 900), { XDG_STATE_HOME = state })
  test.near(test.ipc("state").fraction, 0.5, 0.01)
end)

test.it("follows the tile while it is open", function()
  window("material", answer(true, 0))
  test.truthy(test.ipc("state").on)
  test.eq(test.get("awake-left").text, "On")
  test.clear_stubs()
  test.stub_run("env", answer(false, 0))
  test.advance(2100)
  test.settle(100)
  test.falsy(test.ipc("state").on)
  test.eq(test.get("awake-left").text, "Off")
end)

test.it("says so plainly when the shell is not running", function()
  window("material", { code = 1 })
  test.falsy(test.ipc("state").up)
  test.eq(test.get("awake-left").text, "The shell is not running")
  test.click("awake-preset-30")
  test.settle(100)
  test.eq(#verbs(), 1)
end)

test.it("comes back when the shell does", function()
  window("material", { code = 1 })
  test.clear_stubs()
  test.stub_run("env", answer(true, 0))
  test.advance(2100)
  test.settle(100)
  test.truthy(test.ipc("state").up)
end)

test.it("holds back under a dry run", function()
  window("material", nil, { EVA_DRY_RUN = "1" })
  local before = #verbs()
  test.click("awake-off")
  test.ipc("keep", "30")
  test.settle(100)
  test.eq(#verbs(), before)
  test.truthy(test.ipc("state").up)
end)

-- --------------------------------------------------------------------- jobs --

local function job(args, reply, env)
  test.clear_stubs()
  if reply then test.stub_run("env", reply) end
  local state = fresh()
  local out = state .. "/answer"
  local full = { EVA_JOB_OUT = out, XDG_STATE_HOME = state, EVA_NOW = tostring(MONDAY) }
  for key, value in pairs(env or {}) do full[key] = value end
  test.load("../apps/awake/app.lua", { args = args, env = full })
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

local function cli(args)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/awake-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"), "sh", ROOT .. "apps/awake/cli" }
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.clear_stubs()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or "", test.ipc("result")
end

test.it("the command line asks the tool's own job", function()
  test.contains(cli { "--pid", "12" }, "app " .. ROOT .. "apps/awake/app.lua -- --pid 12")
end)

test.it("its help is its header", function()
  local _, result = cli { "--help" }
  test.contains(result.stdout, "eva-awake --pid N")
end)
