-- eva-nightlight: the sun's times for a place and a day, what `auto` decides, and
-- turning hyprsunset, a stand-in here, on and off.
--
--     morf test --no-dbus tests/nightlight_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"

-- 2026-06-21 and 2026-12-21, at noon UTC.
local JUNE, DECEMBER = "1782043200", "1797854400"
local AMSTERDAM, TROMSO = "52.37,4.90", "69.65,18.96"

local function host()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
end

local function night(args, env)
  local state = morf.env("XDG_STATE_HOME")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=/dev/null",
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"), "XDG_STATE_HOME=" .. state }
  for _, word in ipairs(env or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/bin/eva-nightlight"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.ipc("run", table.unpack(argv))
  return test.wait(function() return test.ipc("result") end, 5000, "the tool answered")
end

local function at(place, now) return { "EVA_NIGHTLIGHT_PLACE=" .. place, "EVA_NOW=" .. now } end

test.it("works out the sun's times for a place and a day", function()
  host()
  local result = night({ "times" }, at(AMSTERDAM, JUNE))
  test.truthy(result.ok)
  test.contains(result.stdout, "sunrise 03:")
  test.contains(result.stdout, "sunset 20:")
  local winter = night({ "times" }, at(AMSTERDAM, DECEMBER))
  test.contains(winter.stdout, "sunrise 07:")
  test.contains(winter.stdout, "sunset 15:")
end)

test.it("knows when the sun stays up or stays down", function()
  host()
  test.contains(night({ "times" }, at(TROMSO, JUNE)).stdout, "does not set")
  test.contains(night({ "times" }, at(TROMSO, DECEMBER)).stdout, "does not rise")
end)

test.it("decides day or night, holding back under a dry run", function()
  host()
  local dry = { "EVA_DRY_RUN=1" }
  local function auto(place, now)
    local env = at(place, now)
    env[#env + 1] = dry[1]
    return night({ "auto" }, env)
  end
  test.contains(auto(AMSTERDAM, JUNE).stdout, "day")
  test.contains(auto(AMSTERDAM, "1782086400").stdout, "night")
  test.contains(auto(TROMSO, JUNE).stdout, "day")
  local polar = auto(TROMSO, DECEMBER)
  test.contains(polar.stdout, "night")
  test.contains(polar.stderr, "dry run: hyprsunset -t 4000")
end)

test.it("says when it has no place", function()
  host()
  local result = night({ "times" }, { "EVA_SETTINGS=/nonexistent/eva.json" })
  test.falsy(result.ok)
  test.contains(result.stderr, "no place")
end)

test.it("runs hyprsunset and stops it", function()
  host()
  test.eq(night({ "status" }).stdout, "off\n")
  test.truthy(night({ "on", "3500" }).ok)
  test.eq(night({ "status" }).stdout, "on\n")
  test.truthy(night({ "toggle" }).ok)
  test.eq(night({ "status" }).stdout, "off\n")
end)

test.it("refuses what it does not know", function()
  host()
  local result = night { "sideways" }
  test.falsy(result.ok)
  test.contains(result.stderr, "unknown command")
end)
