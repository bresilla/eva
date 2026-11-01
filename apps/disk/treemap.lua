-- Squarified treemap: rectangles whose areas are the sizes given, kept as near to
-- square as the sizes allow. Plain numbers, no nodes.
local M = {}

-- The worst aspect of a row of `areas` laid along a side `side` long.
local function worst(sum, smallest, largest, side)
  if sum <= 0 then return math.huge end
  local square = side * side
  local whole = sum * sum
  return math.max(square * largest / whole, whole / (square * smallest))
end

--- Rectangles for `sizes` (numbers, largest first) in the box `x`, `y`, `w`, `h`:
--- `{ { x, y, w, h } }`, in the same order.
function M.layout(sizes, x, y, w, h)
  local out = {}
  local total = 0
  for _, size in ipairs(sizes) do total = total + size end
  if total <= 0 or w <= 0 or h <= 0 then
    for index = 1, #sizes do out[index] = { x = x, y = y, w = 0, h = 0 } end
    return out
  end
  local scale = w * h / total
  local index, count = 1, #sizes
  while index <= count do
    local side = math.min(w, h)
    local sum, smallest, largest = 0, math.huge, 0
    local last = index
    local best = math.huge
    while last <= count do
      local area = sizes[last] * scale
      local next_sum = sum + area
      local next_small, next_large = math.min(smallest, area), math.max(largest, area)
      local ratio = worst(next_sum, next_small, next_large, side)
      if ratio > best then break end
      sum, smallest, largest, best = next_sum, next_small, next_large, ratio
      last = last + 1
    end
    local thick = sum / side
    local along = 0
    for at = index, last - 1 do
      local length = sizes[at] * scale / thick
      if w >= h then
        out[at] = { x = x, y = y + along, w = thick, h = length }
      else
        out[at] = { x = x + along, y = y, w = length, h = thick }
      end
      along = along + length
    end
    if w >= h then
      x, w = x + thick, w - thick
    else
      y, h = y + thick, h - thick
    end
    index = last
  end
  return out
end

return M
