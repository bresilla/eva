-- StandBy: a phone or a tablet on charge, turned sideways, becomes a bedside
-- screen. State only: when it shows, which view, and whether it is night.
local morf = require("morf")
local config = require("config")
local M = {}

M.VIEWS = { { "clock", "Clock", "schedule" }, { "photos", "Photos", "photo_library" }, { "widgets", "Widgets", "widgets" } }
M.view = morf.signal("eva.standby.view", "clock")
-- Sent away until it is unplugged or turned; asked for by hand.
M.dismissed = morf.signal("eva.standby.dismissed", false)
M.forced = morf.signal("eva.standby.forced", false)

--- Whether it is on charge.
function M.charging()
  local status = require("battery_status_model").read()
  return status.present == true and (status.charging or status.plugged or status.full) == true
end

--- Whether the screen lies on its side.
function M.sideways()
  morf.window.screens_revision()
  return not require("responsive").portrait()
end

--- Whether this machine has it at all: a desk has its own desktop.
function M.able()
  return config.get("desktop.standby") == true and require("responsive").form() ~= "desk"
end

--- Whether conditions call for it.
function M.called() return M.able() and M.charging() and M.sideways() end

--- Whether it shows.
function M.showing() return M.forced:get() or (M.called() and not M.dismissed:get()) end

--- Sends it away until the conditions lapse and return.
function M.dismiss()
  M.forced:set(false)
  M.dismissed:set(true)
end

--- The view `delta` steps along.
function M.step(delta)
  local at = 1
  for i, view in ipairs(M.VIEWS) do if view[1] == M.view:get() then at = i end end
  M.view:set(M.VIEWS[(at - 1 + delta) % #M.VIEWS + 1][1])
end

--- Whether it is the dark part of the day, for a dim red face.
function M.night()
  local mode = require("themes.color_mode")
  local kept = require("themes").preferences
  local now = mode.minutes(morf.env("EVA_FAKE_CLOCK"))
  if not now then
    morf.time.minute_clock:get()
    now = (tonumber(morf.time.format("%H")) or 0) * 60 + (tonumber(morf.time.format("%M")) or 0)
  end
  local from, to = mode.minutes(kept.get("light_from")), mode.minutes(kept.get("dark_from"))
  if not from or not to then return false end
  return mode.by_clock(now, from, to) == "dark"
end

-- The next conditions start fresh once these lapse.
morf.effect("eva.standby.reset", function()
  if not M.called() then M.dismissed:set(false) end
end)

--- `standby [on|off|state|VIEW]`.
function M.verb(how)
  how = how or "state"
  if how == "on" then M.forced:set(true) M.dismissed:set(false)
  elseif how == "off" then M.dismiss()
  elseif how ~= "state" then
    local known = false
    for _, view in ipairs(M.VIEWS) do known = known or view[1] == how end
    if not known then error("`" .. tostring(how) .. "`: on, off, state, clock, photos or widgets") end
    M.view:set(how)
  end
  return { showing = M.showing(), view = M.view:get(), called = M.called(), night = M.night() }
end

return M
