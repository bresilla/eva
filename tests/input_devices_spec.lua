-- The kernel's input devices, read in one place: what each device is, and
-- everyone who asks going through it, the stand-in file included.
--
--     morf test --no-dbus tests/input_devices_spec.lua
local test = morf.test
local HOST = [[
  local ui = require("morf.ui")
  ui.Item { width = 10, height = 10 }
  local devices = require("lib.services.input_devices")
  morf.ipc.path = function() return devices.path() end
  morf.ipc.parsed = function(path) return devices.parse(morf.fs.read(path)) end
  morf.ipc.count = function(path) return #devices.list(path) end
  morf.ipc.first = function(field, path)
    local device = devices.first(field, path)
    return device and (device.name or "nameless") or "none"
  end
  morf.ipc.asked = function()
    local keyboards = require("lib.services.keyboards")
    local switch = require("models.posture").find()
    return {
      touch = require("models.touchscreens").attached(),
      keyboard = require("models.keyboards").attached(),
      listed = #keyboards.list(),
      external = keyboards.external(),
      switch = switch and switch.node or "none",
      gamepad = require("focus_triggers").seen().gamepad,
    }
  end
]]

local PLAIN = morf.env("PWD") .. "/tests/fixtures/input-devices"
local TOUCH = PLAIN .. "-touch"
local CONVERTIBLE = PLAIN .. "-convertible"

local function load(devices)
  test.load("../shell/init.lua", { size = { 100, 100 }, source = HOST,
    env = { EVA_DRY_RUN = "1", EVA_INPUT_DEVICES = devices } })
  test.advance(50)
end

local function named(list, name)
  for _, device in ipairs(list) do if device.name == name then return device end end
end

test.it("a device reads as one shape: name, bus, handlers, node and what it can do", function()
  load(PLAIN)
  local list = test.ipc("parsed", CONVERTIBLE)
  local keyboard = named(list, "AT Translated Set 2 keyboard")
  test.eq(keyboard.bus, "0011")
  test.eq(keyboard.handlers, "sysrq kbd leds event0")
  test.eq(keyboard.event, "event0")
  test.falsy(keyboard.direct)
  test.falsy(keyboard.joystick)
  test.falsy(keyboard.tablet_switch)
  test.truthy(named(list, "Goodix Capacitive TouchScreen").direct, "PROP bit 1 is a direct device")
  test.truthy(named(list, "Intel HID switches").tablet_switch, "SW bit 1 is the tablet switch")
end)

test.it("a block with no name still counts, as the touch check always read it", function()
  load(PLAIN)
  local text = morf.env("XDG_CACHE_HOME") .. "/devices-nameless"
  morf.fs.write(text, "H: Handlers=event5\nB: PROP=2\n")
  test.eq(test.ipc("count", text), 1)
  test.eq(test.ipc("first", "direct", text), "nameless")
end)

test.it("a joystick handler among others is a joystick", function()
  load(PLAIN)
  local path = morf.env("XDG_CACHE_HOME") .. "/devices-pad"
  morf.fs.write(path, 'N: Name="Pad"\nH: Handlers=event7 js0\nB: PROP=0\n\nN: Name="Keys"\nH: Handlers=kbd event8\n')
  test.eq(test.ipc("first", "joystick", path), "Pad")
end)

test.it("everyone reads the stand-in file, and it is the only seam", function()
  load(CONVERTIBLE)
  local asked = test.ipc("asked")
  test.truthy(asked.touch)
  test.truthy(asked.keyboard)
  test.eq(asked.listed, 1)
  test.falsy(asked.external)
  test.eq(asked.switch, "/dev/input/event12")
  test.falsy(asked.gamepad)
  load(TOUCH)
  asked = test.ipc("asked")
  test.truthy(asked.touch)
  test.falsy(asked.keyboard)
  test.eq(asked.switch, "none")
end)

test.it("a list that cannot be read is no devices, for everyone", function()
  load("/nonexistent/devices")
  local asked = test.ipc("asked")
  test.falsy(asked.touch)
  test.falsy(asked.keyboard)
  test.eq(asked.listed, 0)
  test.eq(asked.switch, "none")
  test.falsy(asked.gamepad)
end)

test.it("an empty stand-in means the kernel's own list", function()
  load("")
  test.eq(test.ipc("path"), "/proc/bus/input/devices")
end)

test.it("nothing else reads or picks apart the list", function()
  for _, name in ipairs { "shell/focus_triggers.lua", "models/touchscreens.lua", "models/keyboards.lua",
    "lib/services/keyboards.lua", "models/posture.lua" } do
    local source = morf.fs.read(name)
    for _, word in ipairs { "EVA_INPUT_DEVICES", "/proc/bus/input", "Handlers=", "B: PROP", "B: SW", "N: Name" } do
      test.falsy(source:find(word, 1, true), name .. " still holds " .. word)
    end
  end
end)
