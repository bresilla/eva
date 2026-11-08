-- eva-pomodoro: the cycle of phases, the timer in eva-clock's store, a session
-- that outlives its window, the focus seam, the window and the command line. A
-- session driven through the shell's verbs on a real compositor is
-- tools/see/pomodoro.steps'.
--
--     morf test --no-dbus tests/pomodoro_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
-- Monday 2 November 2026, 10:00 UTC.
local MONDAY = 1793613600
local MINUTE = 60

local function fresh(name)
  local state = morf.env("XDG_STATE_HOME") .. "/pomodoro-" .. name .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  return state
end

local function environment(state, at, extra)
  local env = { XDG_STATE_HOME = state, EVA_DRY_RUN = "1", EVA_NOW = tostring(at), EVA_ALARM_ENGINE = "local",
    EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_TEST_TOOL = "pomodoro",
    EVA_STYLE = "material", EVA_TEST_PAGE = "408x620" }
  for key, value in pairs(extra or {}) do env[key] = value end
  return env
end

local function open(state, at, extra)
  test.load("../shell/init.lua", { env = environment(state, at, extra),
    source = morf.fs.read(ROOT .. "tests/fixtures/tool_page.lua") })
  test.settle(300)
end

local function store(state)
  local ok, list = pcall(function() return morf.json.decode(morf.fs.read(state .. "/eva/clock/alarms.json")) end)
  return ok and list or {}
end

-- ---------------------------------------------------------------- the store --

test.it("a phase's end is a timer in eva-clock's store, named for it", function()
  local state = fresh("store")
  open(state, MONDAY)
  test.truthy(test.ipc("start"))
  local list = store(state)
  test.eq(#list, 1)
  test.eq(list[1].kind, "timer")
  test.eq(list[1].label, "focus")
  test.eq(list[1].seconds, 25 * MINUTE)
  test.eq(list[1].at, MONDAY + 25 * MINUTE)
  test.eq(list[1].tool, "pomodoro")
  test.eq(test.ipc("state").alarm, list[1].id)
end)

test.it("pause takes the timer away, and resume sets one for what is left", function()
  local state = fresh("pause")
  open(state, MONDAY)
  test.ipc("start")
  open(state, MONDAY + 10 * MINUTE)
  test.truthy(test.ipc("pause"))
  test.eq(#store(state), 0)
  test.falsy(test.ipc("state").running)
  test.eq(test.ipc("state").left, 15 * MINUTE)
  open(state, MONDAY + 50 * MINUTE)
  test.eq(test.ipc("state").left, 15 * MINUTE, "a paused session does not run down")
  test.ipc("start")
  test.eq(store(state)[1].at, MONDAY + 65 * MINUTE)
  test.eq(store(state)[1].label, "focus")
end)

test.it("a timer cancelled in eva-clock stops the session", function()
  local state = fresh("cancel")
  open(state, MONDAY)
  test.ipc("start")
  morf.fs.write(state .. "/eva/clock/alarms.json", "[]", { atomic = true })
  test.wait(function() return not test.ipc("state").running end, 3000, "the session stopped")
  test.eq(test.ipc("state").left, 25 * MINUTE)
end)

-- ---------------------------------------------------------------- the cycle --

test.it("survives its window: the phase moves on and counts with none open", function()
  local state = fresh("survive")
  open(state, MONDAY)
  test.ipc("start")
  open(state, MONDAY + 10 * MINUTE)
  test.truthy(test.ipc("state").running, "still running after the window went")
  test.eq(test.ipc("state").left, 15 * MINUTE)
  open(state, MONDAY + 26 * MINUTE)
  local after = test.ipc("state")
  test.falsy(after.running)
  test.eq(after.phase, "short")
  test.eq(after.round, 1)
  test.eq(after.today, 1)
  test.eq(after.left, 5 * MINUTE)
end)

test.it("goes work, short, work, short and so on to a long break, then starts a set", function()
  local state = fresh("cycle")
  local at = MONDAY
  local seen = {}
  open(state, at)
  for _ = 1, 8 do
    local now = test.ipc("state")
    seen[#seen + 1] = now.phase
    test.ipc("start")
    at = at + now.seconds + 1
    open(state, at)
    -- The ring took the timer; the local engine has no shell to do it here.
    morf.fs.write(state .. "/eva/clock/alarms.json", "[]", { atomic = true })
  end
  test.eq(seen, { "work", "short", "work", "short", "work", "short", "work", "long" })
  local final = test.ipc("state")
  test.eq(final.phase, "work")
  test.eq(final.round, 0)
  test.eq(final.today, 4)
end)

test.it("a skipped phase is not counted, and a running one starts the next", function()
  local state = fresh("skip")
  open(state, MONDAY)
  test.ipc("start")
  test.ipc("skip")
  local now = test.ipc("state")
  test.eq(now.phase, "short")
  test.truthy(now.running)
  test.eq(now.round, 0)
  test.eq(now.today, 0)
  test.eq(#store(state), 1)
  test.eq(store(state)[1].label, "break")
  test.ipc("pause")
  test.ipc("skip")
  test.eq(test.ipc("state").phase, "work")
  test.falsy(test.ipc("state").running)
  test.eq(#store(state), 0)
end)

test.it("reset goes back to a waiting first phase and keeps the day's count", function()
  local state = fresh("reset")
  open(state, MONDAY)
  test.ipc("start")
  open(state, MONDAY + 26 * MINUTE)
  morf.fs.write(state .. "/eva/clock/alarms.json", "[]", { atomic = true })
  test.ipc("start")
  test.truthy(test.ipc("reset"))
  local now = test.ipc("state")
  test.eq(now.phase, "work")
  test.eq(now.round, 0)
  test.eq(now.today, 1)
  test.falsy(now.running)
  test.eq(#store(state), 0)
end)

test.it("the day's count starts again on a new day", function()
  local state = fresh("day")
  open(state, MONDAY)
  test.ipc("start")
  open(state, MONDAY + 26 * MINUTE)
  test.eq(test.ipc("state").today, 1)
  open(state, MONDAY + 86400)
  test.eq(test.ipc("state").today, 0)
  test.eq(test.ipc("state").total, 1)
end)

test.it("a plan takes hold on a phase that has not begun, never on a running one", function()
  local state = fresh("plan")
  open(state, MONDAY)
  test.truthy(test.ipc("plan", "2"))
  test.eq(test.ipc("state").left, 50 * MINUTE)
  test.ipc("start")
  test.truthy(test.ipc("plan", "3"))
  test.eq(test.ipc("state").seconds, 50 * MINUTE)
  test.falsy(test.ipc("plan", "9"))
end)

-- ------------------------------------------------------------------ focus --

local function verbs()
  local out = {}
  for _, run in ipairs(test.runs()) do
    local line = table.concat(run, " ")
    local verb = line:match("ipc call (focus %a+)")
    if verb then out[#out + 1] = verb end
  end
  return out
end

test.it("do not disturb holds while a work phase runs, and only then", function()
  local state = fresh("focus")
  test.stub_run("env", { code = 0, stdout = '{"ok":true,"result":true}' })
  open(state, MONDAY, { EVA_DRY_RUN = "0" })
  test.clear_stubs()
  test.stub_run("env", { code = 0, stdout = '{"ok":true,"result":true}' })
  test.ipc("start")
  test.settle(100)
  test.eq(verbs()[#verbs()], "focus on")
  test.ipc("pause")
  test.settle(100)
  test.eq(verbs()[#verbs()], "focus off")
  test.ipc("skip")
  test.ipc("start")
  test.settle(100)
  test.eq(test.ipc("state").phase, "short")
  test.eq(verbs()[#verbs()], "focus off", "a break is not quiet")
end)

test.it("says so when no shell holds the quiet", function()
  local state = fresh("noshell")
  test.stub_run("env", { code = 1 })
  open(state, MONDAY, { EVA_DRY_RUN = "0" })
  test.ipc("start")
  test.settle(100)
  test.contains(test.ipc("state").message, "not running")
end)

test.it("a phase that ends lets the quiet go with no window, when eva-clock says it rang", function()
  local state = fresh("rang")
  open(state, MONDAY)
  test.ipc("start")
  local out = state .. "/rang.out"
  test.stub_run("env", { code = 0, stdout = '{"ok":true,"result":false}' })
  test.load("../apps/pomodoro/app.lua", { args = { "rang" },
    env = environment(state, MONDAY + 25 * MINUTE, { EVA_DRY_RUN = "0", EVA_JOB_OUT = out }) })
  test.settle(100)
  test.contains(table.concat(verbs(), ","), "focus off")
  test.advance(1000)
  test.contains(morf.fs.read(out), "Short break 5:00, ready, 1 of 4, 1 today")
end)

test.it("eva-clock's store tells the tool that set an entry once it has rung", function()
  local state = fresh("hook")
  test.load("../shell/init.lua", { env = environment(state, MONDAY), source = [[
    local morf = require("morf")
    require("morf.ui").Item { width = 1, height = 1 }
    local a = require("lib.services.alarm").new { ring = true }
    a.load()
    morf.ipc.add = function(words, tool)
      local item = a.add(words, tool ~= "" and tool or nil)
      return item.id
    end
    morf.ipc.finish = function(id) a.finish(id) return true end
  ]] })
  local mine = test.ipc("add", "timer 1 min focus", "pomodoro")
  local plain = test.ipc("add", "timer 1 min tea", "")
  test.clear_logs()
  test.ipc("finish", plain)
  local told = false
  for _, line in ipairs(test.logs("info")) do told = told or line.message:find("rang", 1, true) ~= nil end
  test.falsy(told, "an entry no tool set tells nobody")
  test.ipc("finish", mine)
  for _, line in ipairs(test.logs("info")) do told = told or line.message:find("cli rang", 1, true) ~= nil end
  test.truthy(told, "the pomodoro heard")
end)

-- ---------------------------------------------------------------- the window --

for _, style in ipairs { "material", "tsugumori" } do
  test.it("shows the dial and starts from its button, in " .. style, function()
    local state = fresh("window-" .. style)
    local appearance = state .. "/appearance.json"
    morf.fs.write(appearance, morf.json.encode { theme = style, font = "" })
    open(state, MONDAY, { EVA_APPEARANCE = appearance })
    test.eq(test.get({ id = "pomodoro-left" }).text, "25:00")
    test.eq(test.get({ id = "pomodoro-phase" }).text, "Focus")
    test.truthy(test.find { id = "pomodoro-arc" })
    test.click("pomodoro-go")
    test.settle(300)
    test.truthy(test.ipc("state").running)
    test.eq(test.get({ id = "pomodoro-go-box" }) ~= nil, true)
    test.click("pomodoro-skip")
    test.settle(300)
    test.eq(test.get({ id = "pomodoro-phase" }).text, "Short break")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("fills a bead for each work phase of the set", function()
  local state = fresh("beads")
  open(state, MONDAY)
  test.near(test.get({ id = "pomodoro-bead-1" }).width, 0, 0.5)
  test.ipc("start")
  open(state, MONDAY + 26 * MINUTE)
  test.near(test.get({ id = "pomodoro-bead-1" }).width, 16, 0.5)
  test.near(test.get({ id = "pomodoro-bead-2" }).width, 0, 0.5)
end)

-- ---------------------------------------------------------- the command line --

test.it("answers status with no window", function()
  local state = fresh("status")
  local out = state .. "/status.out"
  test.load("../apps/pomodoro/app.lua", { args = { "status" }, env = environment(state, MONDAY, { EVA_JOB_OUT = out }) })
  test.settle(100)
  test.eq(morf.fs.read(out), "0\nFocus 25:00, ready, 0 of 4, 0 today\n")
end)

test.it("refuses a word it does not know", function()
  local state = fresh("nonsense")
  local out = state .. "/nonsense.out"
  test.load("../apps/pomodoro/app.lua", { args = { "bounce" }, env = environment(state, MONDAY, { EVA_JOB_OUT = out }) })
  test.settle(100)
  test.contains(morf.fs.read(out), "1\nunknown command: bounce")
end)

test.it("hands its words to the tool as a job", function()
  test.clear_stubs()
  local log = morf.env("XDG_STATE_HOME") .. "/pomodoro-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. morf.env("XDG_STATE_HOME"), "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"),
    "sh", ROOT .. "apps/pomodoro/cli", "start")
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  test.contains(morf.fs.read(log), "pomodoro/app.lua -- start")
end)
