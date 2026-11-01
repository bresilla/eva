-- Whether a touchscreen is attached (lib.services.input_devices).
local devices = require("lib.services.input_devices")

local M = {}

function M.attached() return devices.first("direct") ~= nil end

return M
