-- Whether a real keyboard is attached and in reach (lib.services.keyboards).
-- Folded (models.posture), a built-in keyboard is behind the screen and only
-- one plugged in or paired counts.
local M = {}

function M.attached()
  local keyboards = require("lib.services.keyboards")
  if require("models.posture").folded() then return keyboards.external() end
  return keyboards.attached()
end

return M
