-- A finger along a row of workspaces: whichever it stands over comes on show,
-- one by one as it goes. The rail uses it.
local M = {}

--- `vertical` (fn: the row stands upright), `slot(x, y)` (the slot under a
--- point, or nil), `go(slot)`. Returns an `on_panned`.
function M.pan(spec)
  local from, at
  return function(phase, dx, dy, _, _, x, y)
    if phase == "begin" then
      local upright = spec.vertical()
      if (math.abs(dy) > math.abs(dx)) ~= upright then return false end
      from, at = { x = x, y = y }, spec.slot(x, y)
    end
    if not from then return end
    if phase == "begin" or phase == "update" then
      local slot = spec.slot(from.x + dx, from.y + dy)
      if slot and slot ~= at then
        at = slot
        spec.go(slot)
        require("haptics").fire("tap")
      end
      return true
    end
    if phase == "end" then require("haptics").fire("commit") end
    from = nil
  end
end

return M
