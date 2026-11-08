-- A pattern drawn on the 3x3 grid: a dot joins as the pointer passes it, next
-- to the last and not used yet. The digits stay a local; `finger` is in
-- fractions of the grid's side.
local morf = require("morf")
local patty = require("lib.shell.auth.patty")

local M = {}

--- Centre of dot `n` on a grid `size` square, and its pitch.
function M.centre(n, size)
  local pitch = size / 3
  return ((n - 1) % 3 + .5) * pitch, ((n - 1) // 3 + .5) * pitch, pitch
end

--- The dot within `reach` of `x, y`, or nil.
function M.near(x, y, size, reach)
  for n = 1, 9 do
    local cx, cy = M.centre(n, size)
    if (x - cx) ^ 2 + (y - cy) ^ 2 <= reach * reach then return n end
  end
  return nil
end

--- Dots passed going from `a` to `b`, in order, sampled finer than `reach`.
function M.passed(a, b, size, reach)
  local out, last = {}, nil
  local steps = math.max(1, math.ceil(math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) / (reach / 3)))
  for i = 0, steps do
    local t = i / steps
    local n = M.near(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, size, reach)
    if n and n ~= last then out[#out + 1] = n last = n end
  end
  return out
end

function M.new(name)
  local seq, used = {}, {}
  local self = { revision = morf.signal(name .. ".trace", 0), finger = morf.signal(name .. ".finger", false) }
  local function changed() self.revision:set(self.revision:get() + 1) end

  function self.clear()
    if #seq == 0 and not self.finger:get() then return end
    seq, used = {}, {}
    self.finger:set(false)
    changed()
  end
  --- Adds dot `n` where it may follow; true when it did.
  function self.join(n)
    if type(n) ~= "number" or n < 1 or n > 9 or used[n] or #seq >= patty.MAX then return false end
    if #seq > 0 and not patty.neighbours(seq[#seq], n) then return false end
    seq[#seq + 1], used[n] = n, true
    changed()
    return true
  end
  function self.erase()
    if #seq == 0 then return end
    used[seq[#seq]] = nil
    seq[#seq] = nil
    changed()
  end
  function self.count() self.revision:get() return #seq end
  function self.lit(n) self.revision:get() return used[n] == true end
  function self.dots()
    self.revision:get()
    local copy = {}
    for i, n in ipairs(seq) do copy[i] = n end
    return copy
  end
  function self.digits() return table.concat(seq) end
  return self
end

return M
