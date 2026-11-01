-- `org.freedesktop.ScreenSaver`: how a browser or a video player asks the
-- desktop not to go idle. Each request is held until it is undone or the app
-- leaves the bus, and the list says who asked and why.
--
--   local saver = require("lib.services.screensaver").serve {
--     on_change = function(holders) end,   -- { { cookie, app, reason } }
--   }
--
-- Nil and a reason when something else holds the name.
local morf = require("morf")
local M = {}

local NAME = "org.freedesktop.ScreenSaver"

function M.serve(options)
  options = options or {}
  local service, outcome = morf.dbus.serve("session", NAME, "/org/freedesktop/ScreenSaver", false)
  if outcome ~= "owned" then return nil, "the name is " .. tostring(outcome) end
  local holders, next_cookie = {}, 1
  local function changed() if options.on_change then options.on_change(holders) end end
  local function drop(test)
    local kept = {}
    for _, row in ipairs(holders) do if not test(row) then kept[#kept + 1] = row end end
    local moved = #kept ~= #holders
    holders = kept
    if moved then changed() end
  end
  service:on_call(function(call)
    if call.member == "Inhibit" then
      local cookie = next_cookie
      next_cookie = next_cookie + 1
      holders[#holders + 1] = { cookie = cookie, app = tostring(call.args[1] or ""),
        reason = tostring(call.args[2] or ""), sender = call.sender }
      service:reply(call.id, { signature = "u", value = cookie })
      changed()
    elseif call.member == "UnInhibit" then
      local cookie = tonumber(call.args[1])
      drop(function(row) return row.cookie == cookie end)
      service:reply(call.id)
    elseif call.member == "GetActive" then
      service:reply(call.id, false)
    else
      service:reply(call.id)
    end
  end)
  if morf.dbus.on_name_owner_changed then
    morf.dbus.on_name_owner_changed("session", function(name, _, owner)
      if owner == "" then drop(function(row) return row.sender == name end) end
    end)
  end
  return { holders = function() return holders end, close = function() service:close() end }
end

return M
