-- Public warnings by cell broadcast. No nodes. Message identifiers are 3GPP
-- TS 23.041's: CMAS in the US, the same numbers as EU-Alert and the like. The
-- second range repeats the first in the network's other language.
--
--   local alerts = require("models.phone_alerts").new { mobile = m, log = journal,
--     enabled = fn, ring = ringer, notify = fn }
--   alerts.showing:get()   -- the alert on screen, or nil's stand-in {}
--   alerts.dismiss()
local morf = require("morf")

local M = {}

M.KINDS = {
  { id = "presidential", name = "National alerts", first = 4370, last = 4370, other = 4383, level = "extreme", locked = true },
  { id = "extreme", name = "Extreme threats", first = 4371, last = 4372, other = 4384, level = "extreme" },
  { id = "severe", name = "Severe threats", first = 4373, last = 4378, other = 4386, level = "severe" },
  { id = "amber", name = "Missing children", first = 4379, last = 4379, other = 4392, level = "severe" },
  { id = "test", name = "Test alerts", first = 4380, last = 4381, other = 4393, level = "info" },
}

--- The kind `channel` belongs to, or nil for one that is no public warning.
function M.kind(channel)
  for _, kind in ipairs(M.KINDS) do
    if channel >= kind.first and channel <= kind.last then return kind end
    local span = kind.last - kind.first
    if channel >= kind.other and channel <= kind.other + span then return kind end
  end
end

--- The channel ranges to listen to, for `enabled(id)`: national alerts stay on.
function M.ranges(enabled)
  local out = {}
  for _, kind in ipairs(M.KINDS) do
    if kind.locked or enabled(kind.id) then
      out[#out + 1] = { kind.first, kind.last }
      out[#out + 1] = { kind.other, kind.other + kind.last - kind.first }
    end
  end
  return out
end

function M.new(options)
  local mobile, log = options.mobile, options.log
  local function enabled(id)
    return not options.enabled or options.enabled(id)
  end
  local alerts = { showing = morf.signal("eva.alerts.showing", {}) }
  local waiting = {}

  local function show_next()
    alerts.showing:set(table.remove(waiting, 1) or {})
  end

  --- Whether an alert is on screen.
  function alerts.active() return alerts.showing:get().text ~= nil end

  --- Puts the alert away, and shows any that came behind it.
  function alerts.dismiss() show_next() end

  --- Past alerts, newest first.
  function alerts.history()
    local out = {}
    local rows = log and log.rows:get() or {}
    for index = #rows, 1, -1 do out[#out + 1] = rows[index] end
    return out
  end

  --- Tells the modem what to listen for, after a setting changes.
  function alerts.apply() return mobile.cell.channels(M.ranges(enabled)) end

  mobile.cell.on_alert(function(row)
    local kind = M.kind(row.channel)
    if not kind then return end
    if not kind.locked and not enabled(kind.id) then return end
    local entry = { id = ("%d/%d/%d"):format(row.channel, row.code, row.update), text = row.text,
      channel = row.channel, kind = kind.id, title = kind.name, level = kind.level, time = morf.time.now() }
    if log then log.put(entry) end
    if options.ring then options.ring.trigger("message-new-cellbroadcast", { important = true }) end
    if options.wake then options.wake() end
    if alerts.active() then waiting[#waiting + 1] = entry else alerts.showing:set(entry) end
    mobile.cell.delete(row.path)
  end)

  morf.effect("eva.alerts.channels", function()
    if mobile.cell.present:get() then alerts.apply() end
  end)
  return alerts
end

return M
