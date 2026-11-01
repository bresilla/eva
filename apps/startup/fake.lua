-- What `systemctl --user list-timers` would say, with EVA_FAKE_STARTUP=1, for a
-- machine with no user session of systemd. Times are in microseconds, as it
-- gives them.
local M = {}

--- The rows, around `now` in seconds.
function M.timers(now)
  local function at(seconds) return math.floor((now + seconds) * 1000000) end
  return {
    { unit = "backup.timer", activates = "backup.service", next = at(5400), last = at(-81000) },
    { unit = "eva-alarm-a1b2c3.timer", activates = "eva-alarm-a1b2c3.service", next = at(1800), last = 0 },
    { unit = "mail-sync.timer", activates = "mail-sync.service", next = at(240), last = at(-660) },
    { unit = "systemd-tmpfiles-clean.timer", activates = "systemd-tmpfiles-clean.service", next = at(69000), last = at(-17400) },
  }
end

return M
