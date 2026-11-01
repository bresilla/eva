-- Whether a real keyboard is attached and in reach (lib.services.keyboards),
-- read from EVA_INPUT_DEVICES in place of /proc/bus/input/devices when that is
-- set. The specs set it, so what they see does not depend on the machine they
-- run on. Folded (models.posture), a built-in keyboard is behind the screen
-- and only one plugged in or paired counts.
local morf = require("morf")

local M = {}

function M.attached()
  local path = morf.env and morf.env("EVA_INPUT_DEVICES")
  if path == false or path == "" then path = nil end
  local keyboards = require("lib.services.keyboards")
  if require("models.posture").folded() then return keyboards.external(path) end
  return keyboards.attached(path)
end

return M
