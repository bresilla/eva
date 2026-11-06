-- What a focus session asks of the machine: quiet while it lasts, through the
-- shell's `focus` verb, which is do not disturb.
local sys = require("apps.common.sys")

local M = {}

--- Quiet on or off: `done(reply)`, `reply` nil where no shell answers.
function M.set(on, done)
  sys.shell({ "focus", on and "on" or "off" }, nil, done)
end

return M
