-- The touchscreens attached, read like models.keyboards: from
-- EVA_INPUT_DEVICES in place of /proc/bus/input/devices when that is set.
local morf = require("morf")

local M = {}

local PROP_DIRECT, BTN_TOOL_PEN, ABS_MT_POSITION_X = 1, 0x140, 0x35
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

local function read()
  local path = morf.env and morf.env("EVA_INPUT_DEVICES")
  if path == false or path == "" then path = nil end
  local ok, text = pcall(morf.fs.read, path or "/proc/bus/input/devices")
  return ok and type(text) == "string" and text or ""
end

--- The touchscreens, each `{ name, node, multi }`: `node` the device file, `multi`
--- whether it tells fingers apart. A touchscreen is a direct input device
--- (INPUT_PROP_DIRECT) and no pen: a pen is direct too, and a machine with
--- both has two devices.
function M.list()
  local found = {}
  for block in (read() .. "\n\n"):gmatch("(.-)\n\n") do
    local event = block:match("H: Handlers=[^\n]-(event%d+)")
    if event and bit(block:match("B: PROP=([%x ]+)"), PROP_DIRECT)
      and not bit(block:match("B: KEY=([%x ]+)"), BTN_TOOL_PEN) then
      found[#found + 1] = { name = block:match('N: Name="([^"]*)"') or "", node = "/dev/input/" .. event,
        multi = bit(block:match("B: ABS=([%x ]+)"), ABS_MT_POSITION_X) }
    end
  end
  return found
end

--- Whether one is attached.
function M.attached() return #M.list() > 0 end

return M
