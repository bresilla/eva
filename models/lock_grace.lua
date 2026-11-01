-- A moment after an idle lock in which any key opens it again.
--
-- It starts shut and fails shut. It arms only for a lock the idle timer asked
-- for, with a number of seconds set, off a phone, on a machine that can say
-- when it sleeps. Each of these ends it for good: the time running out, the
-- machine preparing to sleep or found to have slept, the lid shutting, another
-- lock request, a wrong password, or the sensor it watches going unreadable. A
-- key is the only thing that uses it, and it opens once.
--
-- Three witnesses of sleep, any one enough: logind's PrepareForSleep, the
-- kernel's count of suspends, and a gap in the boot-time clock between ticks
-- (user processes stop while the machine sleeps, the clock does not).
--
--   local grace = require("models.lock_grace").new {
--     seconds = 15, reason = "idle", phone = false,
--     guard = login,                 -- models.logind's, or nil
--     clock = fn, suspends = fn, timer = fn,   -- seams, for specs
--   }
--   grace.arm()        -- the compositor has confirmed the lock
--   grace.take()       -- a key: true means open
local morf = require("morf")
local M = { GAP = 2.5, STATS = "/sys/power/suspend_stats/success" }

local function suspends()
  local ok, text = pcall(morf.fs.read, M.STATS)
  return ok and type(text) == "string" and tonumber(text:match("%d+")) or nil
end

function M.new(options)
  local clock = options.clock or require("models.lock_reason").uptime
  local count = options.suspends or suspends
  local timer = options.timer or morf.time.timer
  local seconds = math.floor(tonumber(options.seconds) or 0)
  local guard = options.guard
  local self = { left = morf.signal("lock.grace.left", 0), why = "" }
  local armed, deadline, last, baseline, ticking = false, 0, 0, nil, nil

  local function stop(why)
    armed = false
    self.why = why or ""
    self.left:set(0)
    if ticking then ticking:cancel() ticking = nil end
  end
  --- Ends it, for good.
  function self.revoke(why)
    stop(why or "revoked")
    seconds = 0
  end

  -- Whether the window still holds, read fresh.
  local function holds()
    if not armed then return false end
    local now = clock()
    if not now then self.revoke("no clock") return false end
    if now - last > M.GAP then self.revoke("slept") return false end
    if now >= deadline then self.revoke("expired") return false end
    local total = count()
    if total == nil or total ~= baseline then self.revoke("slept") return false end
    if guard and guard.preparing and guard.preparing() then self.revoke("sleeping") return false end
    if guard and guard.lid_closed and guard.lid_closed() then self.revoke("lid") return false end
    last = now
    self.left:set(math.ceil(deadline - now))
    return true
  end

  --- Whether a lock like this one may have a window at all.
  function self.eligible()
    return seconds > 0 and options.reason == "idle" and not options.phone
      and guard ~= nil and guard.available() and clock() ~= nil and count() ~= nil
  end

  --- The lock is confirmed on every output: the window starts.
  function self.arm()
    if armed or not self.eligible() then return false end
    if guard.preparing and guard.preparing() then return false end
    if guard.lid_closed and guard.lid_closed() then return false end
    local now = clock()
    armed, deadline, last, baseline = true, now + seconds, now, count()
    self.left:set(seconds)
    guard.on_sleep(function() self.revoke("sleeping") end)
    guard.on_lock(function() self.revoke("locked again") end)
    ticking = timer(500, function() holds() end, true)
    return true
  end

  --- A key was pressed: true once, while the window holds.
  function self.take()
    if not holds() then return false end
    stop("used")
    seconds = 0
    return true
  end

  function self.armed() return armed end
  return self
end

return M
