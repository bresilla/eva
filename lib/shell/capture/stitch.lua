-- Lines up the frames of a window as it scrolls. A frame is a list of its rows'
-- signatures, top to bottom; the same pixels give the same signature. Rows that
-- stand still at the top and bottom are a header and a footer. Of the rows that
-- move, those seen once in a frame vote for how far it moved, and a frame nothing
-- agrees on is refused. No pixels and no surfaces here.
local M = {}

-- What a verdict needs: this many rows for it, this share of those that could
-- have agreed, and no rival with this share of its votes. `PATCH` is the share of
-- a frame that may change in place and still be no movement.
M.LEAST_VOTES = 8
M.AGREEMENT = 0.5
M.RIVAL = 0.6
M.PATCH = 0.25

--- How many rows at the top and bottom of two frames are the same in place, the
--- first `guard` rows counted as the same whatever they hold.
function M.edges(before, after, guard)
  local count = math.min(#before, #after)
  local top = math.min(count, guard or 0)
  while top < count and before[top + 1] == after[top + 1] do top = top + 1 end
  if top == count then return count, 0 end
  local bottom = 0
  while bottom < count - top and before[count - bottom] == after[count - bottom] do bottom = bottom + 1 end
  return top, bottom
end

-- The rows between `top` and `bottom` seen once: signature to its row.
local function once(rows, top, bottom)
  local where, seen = {}, {}
  for y = top + 1, #rows - bottom do
    local row = rows[y]
    if seen[row] then where[row] = nil
    else seen[row], where[row] = true, y end
  end
  return where
end

--- How `after` stands to `before`: `{ kind = "same" }`, nothing moved;
--- `{ kind = "moved", shift, top, bottom }`, its content went up by `shift` rows;
--- `{ kind = "back", shift }`, it went down; `{ kind = "lost" }`, nothing to go by.
--- The first `guard` rows are covered by something else and take no part.
function M.align(before, after, guard)
  if #before ~= #after then return { kind = "lost" } end
  local top, bottom = M.edges(before, after, guard)
  if #before - top - bottom < M.LEAST_VOTES then return { kind = "same" } end
  local was, now = once(before, top, bottom), once(after, top, bottom)
  local votes = {}
  for row, y in pairs(now) do
    local from = was[row]
    if from then
      local shift = from - y
      votes[shift] = (votes[shift] or 0) + 1
    end
  end
  local best, most, second = nil, 0, 0
  for shift, count in pairs(votes) do
    if count > most or (count == most and best and shift < best) then
      if best then second = math.max(second, most) end
      best, most = shift, count
    elseif count > second then
      second = count
    end
  end
  if not best or most < M.LEAST_VOTES then
    -- A small patch that changed where it stands is no movement of the page.
    local band = #before - top - bottom
    return { kind = band <= #before * M.PATCH and "same" or "lost" }
  end
  if best == 0 then return { kind = "same" } end
  if second > most * M.RIVAL then return { kind = "lost" } end
  local could = 0
  for _, y in pairs(now) do
    local from = y + best
    if from > top and from <= #before - bottom then could = could + 1 end
  end
  if most < could * M.AGREEMENT then return { kind = "lost" } end
  if best < 0 then return { kind = "back", shift = -best } end
  return { kind = "moved", shift = best, top = top, bottom = bottom }
end

--- A run of frames. `least` is the fewest rows worth a new strip; its `guard` is
--- the rows at the top to leave out of comparing.
function M.new(least)
  local t = { least = least or 1, offset = 0, base = nil, covered = nil, height = 0, guard = 0 }

  --- Takes the movement `found` of `rows` as the new place the run stands, and
  --- answers `{ strip = { from, height, y }, first }`: the rows of that frame to
  --- paste at `y`, and the rows of the first frame to keep, the first time.
  function t.accept(rows, found)
    local line = t.height - found.bottom
    local first
    if not t.covered then
      first = line
      t.covered = line
    end
    local offset = t.offset + found.shift
    local from = t.covered - offset
    local height = line - from
    t.offset, t.base = offset, rows
    if height <= 0 then return { first = first } end
    local strip = { from = from, height = height, y = t.covered }
    t.covered = t.covered + height
    return { strip = strip, first = first }
  end

  --- What `rows` is to the run: a verdict of `align`, or `{ kind = "first" }`,
  --- or `{ kind = "small", found }` for movement too short to keep yet, compared
  --- again from the same frame. "moved" also has `strip` and `first`.
  function t.add(rows)
    if not t.base then
      t.base, t.height = rows, #rows
      return { kind = "first" }
    end
    local found = M.align(t.base, rows, t.guard)
    if found.kind ~= "moved" then return found end
    if found.shift < t.least then return { kind = "small", found = found, rows = rows } end
    local kept = t.accept(rows, found)
    found.strip, found.first = kept.strip, kept.first
    return found
  end

  --- The last of it, after the last frame taken: `{ from, height, y }`, and the
  --- height of the whole. nil when nothing moved.
  function t.finish()
    if not t.covered then return nil end
    local from = t.covered - t.offset
    local height = t.height - from
    return { from = from, height = height, y = t.covered }, t.covered + height
  end

  return t
end

return M
