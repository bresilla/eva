-- An emergency call from the lock's card: the phone's modem session
-- (themes/phone_lock.lua), the one that shows the call. A number the network does
-- not call an emergency one is refused there.
local M = {}

local function session()
  local ok, found = pcall(function() return require("themes.phone_lock").session() end)
  return ok and found or nil
end

--- Whether this machine can make a call.
function M.present()
  local found = session()
  return found ~= nil and found.mobile.voice.present:get() == true
end

--- Calls `number`. True once it is on its way.
function M.dial(number)
  local found = session()
  return found ~= nil and found.phone.emergency(number) == true
end

return M
