-- Whether a real keyboard is attached: what an on-screen keyboard asks
-- before it offers itself.
--
--   local keyboards = require("lib.services.keyboards")
--   keyboards.attached()        -- true while one is plugged in (or built in)
--   keyboards.list()            -- { { name, handlers } }, the ones that count
--
-- Read from lib.services.input_devices. Plenty of things there call themselves
-- keyboards and are not: a power button, a laptop's hotkeys, a dock's audio
-- controls, the extra interface on a gaming mouse, a virtual keyboard (an
-- on-screen keyboard's own). A keyboard here is a device with letter keys
-- and LEDs -- the caps lock light every real one has -- and a name that is not
-- one of those.

local devices = require("lib.services.input_devices")

local keyboards = {}

-- Names of things that report keys but are not keyboards.
local NOT = {
  "power button", "sleep button", "lid switch", "video bus", "hid events", "button array",
  "consumer control", "system control", "pc speaker", "wmi hotkeys", "headset", "audio",
  "mouse", "virtual", "ydotool", "morf", "wtype", "uinput",
}

-- A cover that clips to a tablet: on USB, and yet part of the machine. One with
-- no caps lock light is a keyboard all the same.
local function cover(device)
  return (device.name or ""):lower():find("type cover", 1, true) ~= nil
end

local function counts(device)
  local name = (device.name or ""):lower()
  for _, word in ipairs(NOT) do
    if name:find(word, 1, true) then return false end
  end
  local handlers = device.handlers or ""
  -- Letter keys and the lights for caps and num lock.
  return handlers:find("kbd", 1, true) ~= nil and (cover(device) or handlers:find("leds", 1, true) ~= nil)
end

--- The keyboards that count, each `{ name, handlers, bus }`.
function keyboards.list(path)
  local found = {}
  for _, device in ipairs(devices.list(path)) do
    if device.name and counts(device) then found[#found + 1] = device end
  end
  return found
end

--- Whether one is attached now.
function keyboards.attached(path)
  return #keyboards.list(path) > 0
end

-- Input buses a keyboard is plugged or paired over: USB and Bluetooth.
local OUTSIDE = { ["0003"] = true, ["0005"] = true }

--- Whether one is attached from outside the machine: a cover folded behind
--- the screen is no more in reach than a laptop's own keys.
function keyboards.external(path)
  for _, device in ipairs(keyboards.list(path)) do
    if OUTSIDE[device.bus] and not cover(device) then return true end
  end
  return false
end

return keyboards
