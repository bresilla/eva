-- A colour written the ways a person copies one: hex, rgb, hsl and oklch.
local morf = require("morf")

local M = {}

M.NAMES = { "hex", "rgb", "hsl", "oklch" }

local function hsl_of(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local high, low = math.max(r, g, b), math.min(r, g, b)
  local l = (high + low) / 2
  if high == low then return 0, 0, l end
  local d = high - low
  local s = l > 0.5 and d / (2 - high - low) or d / (high + low)
  local h
  if high == r then h = (g - b) / d + (g < b and 6 or 0)
  elseif high == g then h = (b - r) / d + 2
  else h = (r - g) / d + 4 end
  return h * 60, s, l
end

--- `hex` written in format `name`.
function M.write(hex, name)
  local color = morf.color(hex)
  if name == "hex" then return color:hex() end
  local rgb = color:rgb8()
  if name == "rgb" then return ("rgb(%d, %d, %d)"):format(rgb.r, rgb.g, rgb.b) end
  if name == "hsl" then
    local h, s, l = hsl_of(rgb.r, rgb.g, rgb.b)
    return ("hsl(%d, %d%%, %d%%)"):format(math.floor(h + 0.5), math.floor(s * 100 + 0.5), math.floor(l * 100 + 0.5))
  end
  if name == "oklch" then return color:oklch_string() end
  error("unknown format " .. tostring(name))
end

return M
