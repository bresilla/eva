-- eva-standby: the hands, the views and how they change, what it reads of eva-clock,
-- the screen held and let go, and `--when-charging`. The hold through the shell's real
-- verb on a real compositor is tools/see/standby.steps'; UPower is a stand-in in both,
-- as no system bus runs here.
--
--     morf test --no-dbus tests/standby_spec.lua

local test = morf.test

-- Monday 2 November 2026, 10:00 UTC.
local MONDAY = 1793613600
local AWAKE_OFF = '{"n":1,"ok":true,"result":["{\\"on\\":false,\\"until\\":0}"]}'
local AWAKE_ON = '{"n":1,"ok":true,"result":["{\\"on\\":true,\\"until\\":0}"]}'
local DONE = '{"n":1,"ok":true,"result":["{\\"on\\":true}"]}'

local function fresh(name)
  local state = morf.env("XDG_STATE_HOME") .. "/standby-" .. name .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  return state
end

local function environment(state, style, extra)
  local appearance = state .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style or "material", font = "" })
  local env = { XDG_STATE_HOME = state, EVA_DRY_RUN = "1", EVA_NOW = tostring(MONDAY), EVA_ALARM_ENGINE = "local",
    EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_APPEARANCE = appearance }
  for key, value in pairs(extra or {}) do env[key] = value end
  return env
end

local function open(options)
  options = options or {}
  test.clear_stubs()
  local state = options.state or fresh("open")
  test.load("../apps/standby/app.lua", { args = options.args, size = options.size or { 1280, 800 },
    env = environment(state, options.style, options.env) })
  test.settle(300)
  return state
end

-- The tool with the shell's verbs answered in-process, every call kept.
local function with_shell(reply_for_state, args, extra)
  test.clear_stubs()
  local env = environment(fresh("shell"), nil, extra)
  env.EVA_DRY_RUN = "0"
  test.load("../apps/standby/app.lua", { args = args, env = env, source = ([[
    local morf = require("morf")
    local state_reply = %q
    local done_reply = %q
    local calls = {}
    local quits = 0
    morf.process.run = function(argv, options, done)
      local line = table.concat(argv, " ")
      local verb = line:match("ipc call (.*)$")
      if verb then calls[#calls + 1] = verb end
      if done then done { ok = state_reply ~= "down", stdout = verb == "awake state" and state_reply or done_reply } end
    end
    local real_quit = morf.quit
    morf.quit = function() quits = quits + 1 end
    local frame = require("common.frame")
    local model = require("model")
    local view = require("view")
    model.start(morf.args)
    frame.quiet(true)
    frame.overlay { id = "standby", root = view.root() }
    frame.on_second(function() return model.quit() end)
    morf.ipc.calls = function() return calls end
    morf.ipc.quits = function() return quits end
    morf.ipc.state = function() return { held = model.held:get(), leaving = model.leaving:get(), message = model.message:get() } end
    morf.ipc.quit = function() return model.quit() end
  ]]):format(reply_for_state, DONE) })
  test.settle(200)
end

local function shot(name, ...) return test.ipc(name, ...) end

-- ------------------------------------------------------------------ the hands --

test.it("turns the hands to the time", function()
  test.clear_stubs()
  test.load("../apps/standby/app.lua", { env = environment(fresh("angles")), source = [[
    local morf = require("morf")
    require("morf.ui").Item { width = 1, height = 1 }
    local model = require("model")
    morf.ipc.angles = function(h, m, s)
      return { model.angles(tonumber(h), tonumber(m), tonumber(s)) }
    end
  ]] })
  test.eq(shot("angles", "3", "0", "0"), { 90, 1080, 64800 })
  test.eq(shot("angles", "0", "30", "0"), { 15, 180, 10800 })
  local half = shot("angles", "6", "30", "15")
  test.near(half[1], 195.125, 0.001)
  test.near(half[2] % 360, 181.5, 0.001)
  test.near(half[3] % 360, 90, 0.001)
end)

test.it("swings the hands to the time in under a turn, never a day's worth", function()
  open()
  test.settle(2000)
  local seconds = test.ipc("state").seconds
  local hand = test.get({ id = "standby-second" }).rotation
  test.truthy(hand < 400, "the hand has not wound through the day: " .. hand)
  local apart = (hand - seconds * 6) % 360
  test.truthy(apart < 12 or apart > 348, "and it reads the time: " .. apart)
end)

test.it("joins the hands in one field, each on the arm that turns", function()
  open()
  test.truthy(test.find { id = "standby-hour-layer" })
  test.truthy(test.find { id = "standby-minute-layer" })
  test.truthy(test.find { id = "standby-second-layer" })
  test.truthy(test.find { id = "standby-hands" })
end)

-- ------------------------------------------------------------------ the views --

for _, style in ipairs { "material", "tsugumori" } do
  test.it("draws every view, in " .. style, function()
    open { style = style }
    for _, name in ipairs { "clock", "world", "alarm" } do
      test.truthy(test.ipc("show", name))
      test.settle(200)
      test.eq(test.ipc("state").view, name)
    end
    test.eq(#test.logs("error"), 0)
  end)
end

for _, form in ipairs { { "landscape", { 1280, 800 } }, { "portrait", { 434, 966 } }, { "narrow", { 400, 860 } } } do
  test.it("keeps the dial and the digits apart, " .. form[1], function()
    open { size = form[2] }
    local dial = test.get({ id = "standby-dial" })
    local time = test.get({ id = "standby-time" })
    test.truthy(dial.width > 100, "a real dial")
    test.truthy(dial.width <= form[2][1], "it fits")
    test.ne(time.text, "")
    test.eq(#test.logs("error"), 0)
  end)
end

-- What the keyboard reaches, as the compositor gives it to the overlay.
local LAYER = "layer:eva-standby"

test.it("moves between the views by key, round the ends", function()
  open()
  test.eq(test.ipc("state").view, "clock")
  test.click("standby-area")
  test.key("Right")
  test.settle(100)
  test.eq(test.ipc("state").view, "world")
  test.key("Right")
  test.key("Right")
  test.settle(100)
  test.eq(test.ipc("state").view, "clock", "past the last is the first")
  test.key("Left")
  test.settle(100)
  test.eq(test.ipc("state").view, "alarm")
end)

test.it("moves between the views by swipe", function()
  open()
  test.swipe({ 900, 400 }, { 300, 400 }, { duration = 120, surface = LAYER })
  test.settle(200)
  test.eq(test.ipc("state").view, "world")
  test.swipe({ 300, 400 }, { 900, 400 }, { duration = 120, surface = LAYER })
  test.settle(200)
  test.eq(test.ipc("state").view, "clock")
end)

test.it("turns night mode on and off, by key and by its button", function()
  local state = open()
  test.falsy(test.ipc("state").night)
  test.click("standby-area")
  test.key("n")
  test.settle(100)
  test.truthy(test.ipc("state").night)
  test.click("standby-night")
  test.settle(100)
  test.falsy(test.ipc("state").night)
  test.ipc("night", "on")
  open { state = state }
  test.truthy(test.ipc("state").night, "it keeps across a start")
end)

test.it("takes night mode from the command line", function()
  open { args = { "--night" } }
  test.truthy(test.ipc("state").night)
end)

test.it("goes back to the view it was on", function()
  local state = open()
  test.ipc("show", "alarm")
  open { state = state }
  test.eq(test.ipc("state").view, "alarm")
end)

-- ---------------------------------------------------------------- eva-clock's --

test.it("shows the cities eva-clock saved, and follows them", function()
  local state = fresh("world")
  morf.fs.write(state .. "/eva/clock/world.json", morf.json.encode {
    { name = "Tokyo", zone = "Asia/Tokyo" }, { name = "Lisbon", zone = "Europe/Lisbon" },
  }, { parents = true })
  open { state = state }
  test.eq(test.ipc("state").cities, 2)
  test.eq(test.get({ id = "standby-city-name-1" }).text, "Tokyo")
  test.contains(test.get({ id = "standby-city-time-1" }).text, ":")
  morf.fs.write(state .. "/eva/clock/world.json", morf.json.encode { { name = "Oslo", zone = "Europe/Oslo" } }, { atomic = true })
  test.wait(function() return test.ipc("state").cities == 1 end, 3000, "the file was followed")
end)

test.it("says so where no city is saved", function()
  open()
  test.ipc("show", "world")
  test.settle(200)
  test.truthy(test.get({ id = "standby-world-empty" }).visible)
end)

test.it("shows what rings next, from eva-clock's store", function()
  local state = fresh("alarm")
  morf.fs.write(state .. "/eva/clock/alarms.json", morf.json.encode {
    { id = "later", kind = "alarm", label = "gym", on = true, hour = 18, minute = 0, at = MONDAY + 7200 },
    { id = "soon", kind = "timer", label = "tea", on = true, seconds = 600, at = MONDAY + 600 },
    { id = "off", kind = "alarm", label = "no", on = false, hour = 9, minute = 0, at = MONDAY + 60 },
  }, { parents = true })
  open { state = state }
  test.eq(test.ipc("state").upcoming, "tea")
  test.contains(test.get({ id = "standby-alarm-label" }).text, "tea · in 10 min")
end)

test.it("says so where nothing is set to ring", function()
  open()
  test.ipc("show", "alarm")
  test.settle(200)
  test.truthy(test.get({ id = "standby-alarm-empty" }).visible)
end)

-- ------------------------------------------------------------------ the screen --

test.it("takes the screen through the shell's verb, and lets it go on the way out", function()
  with_shell(AWAKE_OFF)
  test.eq(test.ipc("calls"), { "awake state", "awake on 15" })
  test.truthy(test.ipc("state").held)
  test.eq(test.ipc("quits"), 0)
  test.ipc("quit")
  test.settle(100)
  test.eq(test.ipc("calls")[3], "awake off")
  test.eq(test.ipc("quits"), 1)
end)

test.it("leaves alone a screen something else keeps awake", function()
  with_shell(AWAKE_ON)
  test.eq(test.ipc("calls"), { "awake state" })
  test.falsy(test.ipc("state").held)
  test.ipc("quit")
  test.settle(100)
  test.eq(test.ipc("calls"), { "awake state" }, "and does not turn it off")
  test.eq(test.ipc("quits"), 1)
end)

test.it("takes the screen again before its hold lapses", function()
  with_shell(AWAKE_OFF)
  test.advance(10 * 60 * 1000 + 100)
  test.eq(test.ipc("calls")[3], "awake on 15")
end)

test.it("says so when no shell can hold the screen", function()
  with_shell("down")
  test.contains(test.ipc("state").message, "No shell")
  test.ipc("quit")
  test.settle(100)
  test.eq(test.ipc("quits"), 1, "it still ends")
end)

test.it("a second launch closes it", function()
  with_shell(AWAKE_OFF)
  test.ipc("eva-raise")
  test.settle(100)
  test.truthy(test.ipc("state").leaving)
  test.eq(test.ipc("calls")[3], "awake off")
end)

test.it("lets the screen go though the shell answered it late", function()
  test.clear_stubs()
  local env = environment(fresh("late"))
  env.EVA_DRY_RUN = "0"
  test.load("../apps/standby/app.lua", { env = env, source = ([[
    local morf = require("morf")
    local calls = {}
    morf.process.run = function(argv, options, done)
      local verb = table.concat(argv, " "):match("ipc call (.*)$")
      if verb then calls[#calls + 1] = verb end
      -- The verb is carried out, and its answer never comes.
      if verb == "awake state" then done { ok = true, stdout = %q }
      elseif done then done { ok = false } end
    end
    morf.quit = function() end
    require("morf.ui").Item { width = 1, height = 1 }
    local model = require("model")
    model.start({})
    morf.ipc.calls = function() return calls end
    morf.ipc.quit = function() return model.quit() end
  ]]):format(AWAKE_OFF) })
  test.settle(100)
  test.ipc("quit")
  test.settle(100)
  test.eq(test.ipc("calls"), { "awake state", "awake on 15", "awake off" })
end)

test.it("Escape closes it", function()
  with_shell(AWAKE_OFF)
  test.click("standby-area")
  test.key("Escape")
  test.settle(100)
  test.truthy(test.ipc("state").leaving)
end)

-- ------------------------------------------------------------------- the power --

test.it("with --when-charging, ends when the power goes", function()
  with_shell(AWAKE_OFF, { "--when-charging" }, { EVA_FAKE_BATTERY = "57,charging" })
  test.falsy(test.ipc("state").leaving)
  test.ipc("fake-battery", "57,plugged")
  test.settle(100)
  test.falsy(test.ipc("state").leaving, "plugged in but full is still on the charger")
  test.ipc("fake-battery", "57")
  test.settle(100)
  test.truthy(test.ipc("state").leaving)
  test.eq(test.ipc("calls")[3], "awake off")
  test.eq(test.ipc("quits"), 1)
end)

test.it("without it, stays when the power goes", function()
  with_shell(AWAKE_OFF, nil, { EVA_FAKE_BATTERY = "57,charging" })
  test.ipc("fake-battery", "57")
  test.settle(100)
  test.falsy(test.ipc("state").leaving)
end)

test.it("a machine with no battery is on mains, and stays", function()
  with_shell(AWAKE_OFF, { "--when-charging" })
  test.settle(100)
  test.falsy(test.ipc("state").leaving)
end)

test.it("shows the power", function()
  open { env = { EVA_FAKE_BATTERY = "57,charging" } }
  test.contains(test.get({ id = "standby-power" }).text, "57%, charging")
end)
