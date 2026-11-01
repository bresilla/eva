-- The kernel's list of input devices, read for everyone who asks of it.
--
--   local devices = require("lib.services.input_devices")
--   devices.list()             -- every device, as below
--   devices.first("direct")    -- the first with that field set, or nil
--
-- A device: `name`, `bus`, `handlers`, `event` (its node's name), and what it
-- can do: `direct` (a touchscreen or a pen), `pen`, `multitouch`, `joystick`,
-- `tablet_switch`.
--
-- Read from EVA_INPUT_DEVICES in place of /proc/bus/input/devices when that is
-- set.
local morf = require("morf")

local M = {}

local KERNEL = "/proc/bus/input/devices"

-- INPUT_PROP_DIRECT, bit 1 of PROP.
local DIRECT_BIT = 2
-- SW_TABLET_MODE is switch 1, the second bit of the device's SW word.
local TABLET_BIT = 2
local BTN_TOOL_PEN, ABS_MT_POSITION_X = 0x140, 0x35
-- The width of a word in the kernel's bitmaps.
local LONG = string.packsize("l") * 8

-- Bit `n` of a bitmap as the kernel prints it: hex words, highest first.
local function bit(words, n)
  if not words then return false end
  local list = {}
  for word in words:gmatch("%x+") do list[#list + 1] = word end
  local word = list[#list - n // LONG]
  return word ~= nil and (tonumber(word, 16) >> (n % LONG)) & 1 == 1
end

--- The file the list is read from.
function M.path()
  local path = morf.env and morf.env("EVA_INPUT_DEVICES")
  if path == false or path == "" then path = nil end
  return path or KERNEL
end

local function device(block)
  local handlers = block:match("H: Handlers=([^\n]*)")
  local prop = tonumber(block:match("B: PROP=(%x+)") or "0", 16)
  -- The SW line's words run high to low: the last holds switch 1.
  local words = block:match("B: SW=([%x ]+)")
  local switches = tonumber(words and words:match("(%x+)%s*$") or "0", 16)
  return {
    name = block:match('N: Name="([^"]*)"'),
    bus = block:match("I: Bus=(%x+)"),
    handlers = handlers,
    event = handlers and handlers:match("event%d+"),
    direct = prop & DIRECT_BIT ~= 0,
    pen = bit(block:match("B: KEY=([%x ]+)"), BTN_TOOL_PEN),
    multitouch = bit(block:match("B: ABS=([%x ]+)"), ABS_MT_POSITION_X),
    joystick = handlers ~= nil and handlers:find("js%d") ~= nil,
    tablet_switch = switches & TABLET_BIT ~= 0,
  }
end

--- The devices in `text`, the list's format.
function M.parse(text)
  local out = {}
  for block in (text .. "\n\n"):gmatch("(.-)\n\n") do
    if block ~= "" then out[#out + 1] = device(block) end
  end
  return out
end

--- Every device in `path`, or in the list in use; none if it cannot be read.
function M.list(path)
  local ok, text = pcall(morf.fs.read, path or M.path())
  if not ok or type(text) ~= "string" then return {} end
  return M.parse(text)
end

--- The first device with `field` set, or nil.
function M.first(field, path)
  for _, each in ipairs(M.list(path)) do
    if each[field] then return each end
  end
end

return M
