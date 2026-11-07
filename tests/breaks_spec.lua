-- eva-breaks: the count, with a hand on the clock and the idle notification
-- driven from here, and the shell's focus verb and notify-send stubbed. The real
-- idle protocol and the real notifications server are tools/see/breaks.steps'.
--
--     morf test --no-dbus tests/breaks_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
-- Monday 2 November 2026, 10:00 UTC.
local MONDAY = 1793613600

local HOST = [[
  local morf = require("morf")
  local fake_idle
  local shift = 0
  local threshold
  morf.idle = { subscribe = function(ms, fn) threshold, fake_idle = ms, fn return { cancel = function() end } end,
    inhibit = function() end }
  local model = require("apps.breaks.model")
  local base = tonumber(morf.env("TEST_BASE"))
  model.now = function() return base + shift end
  morf.ipc.pass = function(seconds) shift = shift + tonumber(seconds) return true end
  morf.ipc.idle = function(on) fake_idle(on == "yes") return true end
  morf.ipc.threshold = function() return threshold end
  morf.ipc.ending = function(how) model[how]() return true end
  morf.ipc.settings = function(json) model.change(function(value)
    for key, entry in pairs(morf.json.decode(json)) do value[key] = entry end
  end) model.settled() return true end
  require("app")
]]

local serial = 0
local function fresh()
  serial = serial + 1
  local root = morf.env("XDG_STATE_HOME") .. "/breaks-" .. serial .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(root .. "/eva/breaks", { parents = true })
  return root
end

local function focus(on)
  return { code = 0, stdout = ([[{"n":1,"ok":true,"result":[%s]}]]):format(tostring(on)) }
end

local function saved(root) return morf.json.decode(morf.fs.read(root .. "/eva/breaks/state.json")) end

local function watch(settings, style, root)
  root = root or fresh()
  test.clear_stubs()
  test.stub_run("env", focus(false))
  test.stub_run("notify-send", { code = 0 })
  if settings then morf.fs.write(root .. "/eva/breaks/settings.json", morf.json.encode(settings)) end
  local appearance = root .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style or "material", font = "" })
  test.load("../apps/breaks/app.lua", { source = HOST, args = { "--watch" }, env = { XDG_STATE_HOME = root,
    TEST_BASE = tostring(MONDAY), EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule",
    EVA_APPEARANCE = appearance } })
  test.settle(200)
  return root
end

local function pass(seconds)
  test.ipc("pass", tostring(seconds))
  test.advance(seconds * 1000 + 50)
  test.settle(100)
end

local function current() return test.ipc("state").current end

local function notes()
  local out = {}
  for _, run in ipairs(test.runs()) do
    if run[1] == "notify-send" then out[#out + 1] = table.concat(run, " ") end
  end
  return out
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("a break falls due, shows, and ends by itself, in " .. style, function()
    local root = watch(nil, style)
    pass(19 * 60)
    test.eq(current(), nil)
    pass(61)
    test.eq(current().kind, "eyes")
    test.eq(#notes(), 1)
    test.contains(notes()[1], "Look away")
    test.truthy(test.get("breaks-dial").visible)
    test.eq(test.get("breaks-left").text, "0:20")
    pass(21)
    test.eq(current(), nil)
    local key = morf.time.format("%Y-%m-%d", MONDAY)
    test.eq(saved(root).counts[key].taken, 1)
    test.falsy(test.find { id = "breaks-dial" })
    test.eq(#test.logs("error"), 0)
  end)

  test.it("the overlay's buttons skip and put off, in " .. style, function()
    local root = watch(nil, style)
    pass(20 * 60 + 1)
    test.click("breaks-skip")
    test.settle(200)
    test.eq(current(), nil)
    test.eq(saved(root).counts[morf.time.format("%Y-%m-%d", MONDAY)].skipped, 1)
    pass(20 * 60 + 1)
    test.click("breaks-postpone")
    test.settle(200)
    test.eq(current(), nil)
    test.near(saved(root).due.eyes, MONDAY + 2 * (20 * 60 + 1) + 300, 2)
  end)
end

test.it("the long rest stands in for the eyes when both fall due", function()
  local root = watch { eyes = { on = true, every = 60, length = 20 }, rest = { on = true, every = 60, length = 120 } }
  pass(3601)
  test.eq(current().kind, "rest")
  test.ipc("ending", "skip")
  test.settle(100)
  test.near(saved(root).due.eyes, MONDAY + 3601 + 3600, 2)
end)

test.it("idle time counts as the rest, and comes off nothing else", function()
  local root = watch()
  test.eq(test.ipc("threshold"), 20000)
  pass(600)
  test.ipc("pass", "20")
  test.ipc("idle", "yes")
  test.settle(50)
  test.truthy(saved(root).idle)
  test.eq(saved(root).due.eyes ~= nil, true)
  pass(100)
  test.eq(current(), nil)
  test.ipc("idle", "no")
  test.settle(100)
  local due = saved(root).due
  -- Away 120 s: the eyes are rested, the long rest is only pushed back.
  test.near(due.eyes, MONDAY + 720 + 1200, 2)
  test.near(due.rest, MONDAY + 3600 + 120, 2)
end)

test.it("a long time away rests everything", function()
  local root = watch()
  test.ipc("pass", "120")
  test.ipc("idle", "yes")
  pass(600)
  test.ipc("idle", "no")
  test.settle(100)
  test.near(saved(root).due.rest, MONDAY + 720 + 3600, 2)
end)

test.it("no timer runs while idle", function()
  watch()
  local before = test.resources().timers
  test.ipc("idle", "yes")
  test.settle(50)
  test.truthy(test.resources().timers < before)
end)

test.it("counts screen time from activity alone", function()
  local root = watch()
  pass(120)
  test.ipc("pass", "20")
  test.ipc("idle", "yes")
  pass(1000)
  test.ipc("idle", "no")
  test.settle(50)
  pass(60)
  test.ipc("ending", "settled")
  test.settle(50)
  test.near(saved(root).days[morf.time.format("%Y-%m-%d", MONDAY)], 180, 3)
end)

test.it("splits a stretch across midnight", function()
  local date = morf.time.date(MONDAY)
  local to_midnight = 86400 - (date.hour * 3600 + date.minute * 60 + date.second)
  local root = watch { eyes = { on = false, every = 20, length = 20 }, rest = { on = false, every = 60, length = 300 } }
  pass(to_midnight + 100)
  test.ipc("ending", "settled")
  test.settle(50)
  local days = saved(root).days
  test.near(days[morf.time.format("%Y-%m-%d", MONDAY)], to_midnight, 3)
  test.near(days[morf.time.format("%Y-%m-%d", MONDAY + to_midnight + 1)], 100, 3)
end)

test.it("does not disturb: a break is held off and asked again", function()
  local root = watch()
  test.clear_stubs()
  test.stub_run("env", focus(true))
  test.stub_run("notify-send", { code = 0 })
  pass(20 * 60 + 1)
  test.eq(current(), nil)
  test.eq(#notes(), 0)
  test.eq(saved(root).held, "eyes")
  test.clear_stubs()
  test.stub_run("env", focus(false))
  test.stub_run("notify-send", { code = 0 })
  pass(301)
  test.eq(current().kind, "eyes")
  test.eq(saved(root).held, nil)
end)

test.it("reads the verb as a shell that is down: no shell, no silence", function()
  watch()
  test.clear_stubs()
  test.stub_run("env", { code = 1 })
  test.stub_run("notify-send", { code = 0 })
  pass(20 * 60 + 1)
  test.eq(current().kind, "eyes")
end)

test.it("pausing holds everything, and starts the count again after", function()
  local root = watch()
  test.ipc("settings", morf.json.encode { pause_until = MONDAY + 1800 })
  test.eq(saved(root).due.eyes, nil)
  pass(1500)
  test.eq(current(), nil)
  pass(301)
  test.eq(current(), nil)
  test.near(saved(root).due.eyes, MONDAY + 1801 + 1200, 3)
end)

test.it("a reminder turned off stays off", function()
  local root = watch { eyes = { on = false, every = 20, length = 20 }, rest = { on = true, every = 60, length = 300 } }
  pass(30 * 60)
  test.eq(current(), nil)
  test.eq(saved(root).due.eyes, nil)
  test.truthy(saved(root).due.rest)
end)

test.it("follows settings another process wrote", function()
  local root = watch()
  local settings = morf.json.decode(morf.fs.read(root .. "/eva/breaks/settings.json"))
  settings.eyes.every = 30
  morf.fs.write(root .. "/eva/breaks/settings.json", morf.json.encode(settings), { atomic = true })
  test.wait(function() return math.abs(saved(root).due.eyes - (MONDAY + 1800)) < 2 end, 3000, "the settings were followed")
end)

test.it("a second watcher ends at once", function()
  local root = fresh()
  morf.fs.write(root .. "/eva/breaks/state.json", morf.json.encode { pid = 1 })
  test.truthy(watch(nil, nil, root))
end)

-- ----------------------------------------------------------------- the window --

local function window(style, state)
  local root = fresh()
  test.clear_stubs()
  morf.fs.write(root .. "/eva/breaks/state.json", morf.json.encode(state or {}))
  local appearance = root .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style, font = "" })
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/tool_page.lua"),
    env = { XDG_STATE_HOME = root, EVA_SETTINGS = "/nonexistent/eva.json", EVA_TEST_TOOL = "breaks", EVA_STYLE = style,
    LULE_A = "/nonexistent/lule", EVA_APPEARANCE = appearance, EVA_DRY_RUN = "1" } })
  test.settle(300)
  return root
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("shows the day and offers to start the watcher, in " .. style, function()
    local day = morf.time.format("%Y-%m-%d", morf.time.now())
    window(style, { days = { [day] = 7380 }, counts = { [day] = { taken = 3, skipped = 1 } } })
    test.contains(test.get("breaks-screen-title").text, "2 h 3 min")
    test.contains(test.get("breaks-screen-subtitle").text, "3 taken, 1 skipped")
    test.eq(test.get("breaks-next-title").text, "Not watching")
    test.truthy(test.get("breaks-start").visible)
    test.contains(test.get("breaks-day-0").text, "2 h 3 min")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("keeps a choice of the page", function()
  local root = window("material")
  test.click("breaks-eyes-every-2")
  test.settle(200)
  test.eq(morf.json.decode(morf.fs.read(root .. "/eva/breaks/settings.json")).eyes.every, 30)
  test.eq(test.ipc("state").settings.eyes.every, 30)
end)

test.it("a pause shows, and lifts", function()
  local root = window("material")
  test.ipc("pause", "30")
  test.settle(100)
  test.contains(test.get("breaks-next-title").text, "Paused until")
  test.ipc("pause", "0")
  test.settle(100)
  test.eq(morf.json.decode(morf.fs.read(root .. "/eva/breaks/settings.json")).pause_until, 0)
end)

-- --------------------------------------------------------------------- jobs --

local function job(root, args)
  local out = root .. "/answer"
  morf.fs.remove(out)
  test.clear_stubs()
  test.load("../apps/breaks/app.lua", { args = args, env = { XDG_STATE_HOME = root, EVA_JOB_OUT = out } })
  test.settle(100)
  return morf.fs.read(out) or ""
end

test.it("status says how things stand without a watcher", function()
  local root = fresh()
  local day = morf.time.format("%Y-%m-%d", morf.time.now())
  morf.fs.write(root .. "/eva/breaks/state.json", morf.json.encode { days = { [day] = 3600 } })
  local text = job(root, { "status" })
  test.contains(text, "0\nnot watching")
  test.contains(text, "screen today 1 h")
end)

test.it("pause writes the time, and resume takes it back", function()
  local root = fresh()
  test.contains(job(root, { "pause", "30" }), "0\npaused until ")
  test.truthy(morf.json.decode(morf.fs.read(root .. "/eva/breaks/settings.json")).pause_until > 0)
  test.contains(job(root, { "status" }), "paused until ")
  test.contains(job(root, { "resume" }), "0\nresumed")
  test.eq(morf.json.decode(morf.fs.read(root .. "/eva/breaks/settings.json")).pause_until, 0)
end)

test.it("refuses what it does not know", function()
  local root = fresh()
  test.contains(job(root, { "pause", "soon" }), "1\nusage")
  test.contains(job(root, { "sideways" }), "1\nunknown command")
end)

local function cli(args)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/breaks-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"), "sh", ROOT .. "apps/breaks/cli" }
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.clear_stubs()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or ""
end

test.it("--watch is the tool itself, not a job that waits for an answer", function()
  test.contains(cli { "--watch" }, "app " .. ROOT .. "apps/breaks/app.lua -- --watch")
end)

test.it("status is a job", function()
  test.contains(cli { "pause", "5" }, "app " .. ROOT .. "apps/breaks/app.lua -- pause 5")
end)
