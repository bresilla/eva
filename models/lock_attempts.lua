-- Wrong passwords: how many, and how long the field waits after too many. The
-- wait doubles each time the limit is reached, on the boot-time clock.
--
--   local tries = require("models.lock_attempts").new { limit = 5, wait = 30 }
--   tries.failed()          -- after each wrong password
--   tries.waiting()         -- seconds left, tracked; 0 when it may be tried
local morf = require("morf")
local M = {}

function M.new(options)
  local clock = options.clock or require("models.lock_reason").uptime
  local timer = options.timer or morf.time.timer
  local limit, wait = options.limit or 5, options.wait or 30
  local count = morf.signal("lock.attempts.count", 0)
  local left = morf.signal("lock.attempts.left", 0)
  local self = {}
  local until_at, ticking, rounds = 0, nil, 0

  local function tick()
    local now = clock() or until_at
    local remaining = math.ceil(until_at - now)
    left:set(math.max(0, remaining))
    if remaining <= 0 and ticking then ticking:cancel() ticking = nil end
  end

  function self.failed()
    count:set(count:get() + 1)
    if wait <= 0 or count:get() % limit ~= 0 then return end
    local now = clock()
    if not now then return end
    until_at = now + wait * 2 ^ rounds
    rounds = rounds + 1
    tick()
    if not ticking then ticking = timer(1000, tick, true) end
  end

  function self.count() return count:get() end
  function self.waiting() return left:get() end
  --- Whether a password may be submitted now, read fresh.
  function self.allowed()
    tick()
    return left:get() == 0
  end
  return self
end

return M
