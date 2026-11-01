-- Where an edge is, walking pixels from the pointer: pure, for any reader. No
-- nodes, no pictures.
local M = {}

--- From index `from` towards `last`, each step `step` (1 or -1), the furthest
--- index whose pixel stays within `tolerance` of the first's on every channel.
--- `read(index)` gives `r, g, b`, in the units of `tolerance`.
function M.walk(read, from, step, last, tolerance)
  local r0, g0, b0 = read(from)
  local at = from
  while at ~= last do
    local next_at = at + step
    local r, g, b = read(next_at)
    if math.abs(r - r0) > tolerance or math.abs(g - g0) > tolerance or math.abs(b - b0) > tolerance then
      return at
    end
    at = next_at
  end
  return at
end

--- The inches and millimetres of `px` pixels at `mm_per_px`.
function M.length(px, mm_per_px)
  local mm = px * mm_per_px
  return mm, mm / 25.4
end

return M
