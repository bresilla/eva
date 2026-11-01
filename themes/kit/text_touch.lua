-- A text field under a finger: a drag walks the caret, a long press selects the
-- word under it, and a drag after that long press runs the selection on.
local M = {}

local function word_at(text, at)
  local start, stop = at, at
  while start > 0 and text:sub(start, start):match("[%w_\128-\255]") do start = start - 1 end
  while stop < #text and text:sub(stop + 1, stop + 1):match("[%w_\128-\255]") do stop = stop + 1 end
  return start, stop
end

function M.attach(input)
  local touching, selecting = false, false
  input.on_touch_pressed = function() touching, selecting = true, false end
  input.on_touch_canceled = function() touching, selecting = false, false end
  input.on_long_pressed = function()
    selecting = true
    local text = input.text or ""
    local start, stop = word_at(text, input.cursor_position or 0)
    if stop > start then input:select(start, stop) elseif #text > 0 then input:select_all() end
    local haptics = package.loaded.haptics
    if haptics then haptics.fire("long") end
  end
  input.on_released = function()
    if touching and not selecting then input:deselect() end
    touching = false
  end
end

return M
