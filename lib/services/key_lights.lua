-- The lights of the lock keys, read from the LEDs a keyboard's driver exports:
-- every Linux keyboard has `inputN::capslock` and `inputN::numlock`, each with
-- a `brightness` file. No keyboard, no lights, and nobody is told otherwise.
--
--   local lights = require("lib.services.key_lights")
--   local found = lights.scan()     -- { caps = { paths }, num = { paths } }
--   lights.lit(found.caps)          -- true while any of them is on
--
-- EVA_LEDS names another folder.
local morf = require("morf")
local M = {}

function M.dir() return morf.env and morf.env("EVA_LEDS") or "/sys/class/leds" end

function M.scan(dir)
  dir = dir or M.dir()
  local caps, num = {}, {}
  local ok, entries = pcall(morf.fs.list, dir, { follow = true })
  for _, entry in ipairs(ok and entries or {}) do
    local list = entry.name:match("::capslock$") and caps or entry.name:match("::numlock$") and num
    if list then list[#list + 1] = dir .. "/" .. entry.name .. "/brightness" end
  end
  return { caps = caps, num = num }
end

function M.lit(list)
  for _, path in ipairs(list) do
    local ok, text = pcall(morf.fs.read, path)
    if ok and type(text) == "string" and (tonumber(text:match("%d+")) or 0) > 0 then return true end
  end
  return false
end

return M
