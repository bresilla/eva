-- The night light: the sun's times for a place and a day, the commands the tile
-- and eva-nightlight share, and eva-nightlight reaching them.
--
--     morf test --no-dbus tests/nightlight_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"

-- 2026-06-21 and 2026-12-21, at noon UTC.
local JUNE, DECEMBER = "1782043200", "1797854400"
local AMSTERDAM, TROMSO = "52.37,4.90", "69.65,18.96"

local HOST = [[
  local morf = require("morf")
  local ui = require("morf.ui")
  ui.Item { width = 1, height = 1 }
  local lib = require("lib.services.nightlight")
  local state = { on = false, temperature = 4500, follow = false }
  local device = {
    on = function() return state.on end,
    set = function(now) state.on = now end,
    temperature = function() return state.temperature end,
    set_temperature = function(value) state.temperature = lib.clamp(value) end,
    follow = function() return state.follow end,
    set_follow = function(now) state.follow = now end,
  }
  local answer
  local function hold(text, why) answer = { text = text, why = why } end
  morf.ipc.times = function(where) answer = nil lib.times(where, hold) return true end
  morf.ipc.decide = function(where) answer = nil lib.decide(device, where, hold) return true end
  morf.ipc.answer = function() return answer end
  morf.ipc.state = function() return state end
  morf.ipc.command = function(how, value)
    local text, why = lib.command(device, how, value)
    return { text = text, why = why }
  end
  morf.ipc.coordinates = function(where)
    local lat, lon = lib.coordinates(where)
    return { lat = lat, lon = lon }
  end
]]

local function host(now)
  test.load("../shell/init.lua", { source = HOST, env = { EVA_NOW = now or JUNE } })
end

local function times(place, now)
  host(now)
  test.ipc("times", place)
  return test.wait(function() return test.ipc("answer") end, 2000, "the sun answered")
end

local function decide(place, now)
  host(now)
  test.ipc("decide", place)
  return test.wait(function() return test.ipc("answer") end, 2000, "the sun answered")
end

test.it("works out the sun's times for a place and a day", function()
  local summer = times(AMSTERDAM, JUNE).text
  test.contains(summer, "sunrise 03:")
  test.contains(summer, "sunset 20:")
  local winter = times(AMSTERDAM, DECEMBER).text
  test.contains(winter, "sunrise 07:")
  test.contains(winter, "sunset 15:")
end)

test.it("knows when the sun stays up or stays down", function()
  test.contains(times(TROMSO, JUNE).text, "does not set")
  test.contains(times(TROMSO, DECEMBER).text, "does not rise")
end)

test.it("decides day or night and sets the light", function()
  test.eq(decide(AMSTERDAM, JUNE).text, "day")
  test.falsy(test.ipc("state").on)
  test.eq(decide(AMSTERDAM, "1782086400").text, "night")
  test.truthy(test.ipc("state").on)
  test.eq(decide(TROMSO, JUNE).text, "day")
  test.eq(decide(TROMSO, DECEMBER).text, "night")
end)

test.it("says when it has no place", function()
  local answer = times("")
  test.falsy(answer.text)
  test.contains(answer.why, "no place")
end)

test.it("reads coordinates however they are written", function()
  host()
  test.eq(test.ipc("coordinates", "52.37,4.90").lat, 52.37)
  test.eq(test.ipc("coordinates", " -33.9, 151.2 ").lon, 151.2)
  test.eq(test.ipc("coordinates", "Amsterdam").lat, nil)
end)

test.it("takes the commands both surfaces take", function()
  host()
  test.eq(test.ipc("command", "status").text, "off")
  test.eq(test.ipc("command", "on", "3500").text, "on")
  test.eq(test.ipc("state").temperature, 3500)
  test.eq(test.ipc("command", "toggle").text, "off")
  test.eq(test.ipc("command", "temperature", "9000").text, "6000")
  test.eq(test.ipc("command", "follow", "on").text, "on")
  test.truthy(test.ipc("state").follow)
end)

test.it("refuses what it does not know", function()
  host()
  test.contains(test.ipc("command", "sideways").why, "unknown command")
end)

-- ---------------------------------------------------------- the command line --

local function cli(args, env)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/night-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log, "HOME=" .. state,
    "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR") }
  for _, word in ipairs(env or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/bin/eva-nightlight"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  return test.wait(function() return test.ipc("result") end, 5000, "the tool answered"), morf.fs.read(log) or ""
end

test.it("eva-nightlight asks the shell when it is up", function()
  local _, calls = cli({ "on", "3500" }, { "STUB_UP=1" })
  test.contains(calls, "ipc call nightlight on 3500")
  test.falsy(calls:find("job/app.lua", 1, true))
end)

test.it("eva-nightlight runs the same code as a job with the shell down", function()
  local _, calls = cli { "off" }
  test.contains(calls, "apps/common/job/app.lua -- nightlight off")
end)

test.it("the sun's times are a job whether the shell is up or not", function()
  local _, calls = cli({ "times" }, { "STUB_UP=1" })
  test.contains(calls, "apps/common/job/app.lua -- nightlight times")
end)

test.it("eva-nightlight holds no copy of what the module does", function()
  local script = morf.fs.read(ROOT .. "apps/bin/eva-nightlight")
  test.falsy(script:find("hyprsunset -t", 1, true))
  test.falsy(script:find("awk", 1, true))
  test.falsy(script:find("curl", 1, true))
end)

test.it("refuses a command the shell would not take", function()
  local result = cli { "sideways" }
  test.falsy(result.ok)
  test.contains(result.stderr, "unknown command")
end)
