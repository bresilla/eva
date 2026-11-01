-- The touchscreens attached (lib.services.input_devices).
local devices = require("lib.services.input_devices")

local M = {}

--- The touchscreens, each `{ name, node, multi }`: `node` the device file, `multi`
--- whether it tells fingers apart. A touchscreen is a direct input device and no
--- pen: a pen is direct too, and a machine with both has two devices.
function M.list()
  local found = {}
  for _, device in ipairs(devices.list()) do
    if device.direct and not device.pen and device.event then
      found[#found + 1] = { name = device.name or "", node = "/dev/input/" .. device.event, multi = device.multitouch }
    end
  end
  return found
end

--- Whether one is attached.
function M.attached() return #M.list() > 0 end

return M
