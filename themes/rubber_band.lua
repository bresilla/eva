-- Elastic resistance: past a limit a drag gets less the further it goes.
local M = { REACH = 90 }

--- What `extra` px past a limit moves, never more than `reach`.
function M.band(extra, reach)
  reach = reach or M.REACH
  return extra / (1 + math.abs(extra) / reach)
end

--- `value` held in `low`..`high`, running on elastically past either.
function M.between(value, low, high, reach)
  local bound = math.max(low, math.min(high, value))
  return bound + M.band(value - bound, reach)
end

return M
