-- Where the bar's modules go along its row: three zones, what folds when a zone
-- runs out of room, and how a cutout splits the row. Geometry only: no nodes
-- and no state.
--
-- An item is `{ id, size, tier, flex, hold, island, extra }`. `tier` says when
-- it folds: 1 the rare ones, then 2, then 3; 0 never. `flex` gives up its own
-- size first (the windows, which scroll). `island` sits centred over a cutout
-- (the live pill), `extra` of its size hanging off past the far side.
local M = {}

M.ZONES = { "start", "centre", "end" }

--- What to give up of `items` (each `{ key, tier, size }`) for them to take
--- no more than `room`, with `dot` for the mark that stands for them. Rare
--- ones go first, each tier in the order given. Returns `{ hidden, dot, need }`:
--- `hidden[key]`, whether the dot shows, and what is left to fit.
function M.fold(items, room, dot)
  local need = 0
  for _, item in ipairs(items) do need = need + item.size end
  local out = { hidden = {}, dot = false, need = need }
  for tier = 1, 3 do
    for _, item in ipairs(items) do
      if need <= room then break end
      if item.tier == tier then
        out.hidden[item.key or item.id] = true
        need = need - item.size
        if not out.dot then out.dot = true need = need + dot end
      end
    end
  end
  out.need = need
  return out
end

-- The size of `items` in a row, those with no size taking no gap.
local function span(items, gap, hidden)
  local total, count = 0, 0
  for _, item in ipairs(items) do
    if item.size > 0 and not (hidden and hidden[item.id]) then
      total, count = total + item.size, count + 1
    end
  end
  return total + math.max(0, count - 1) * gap
end

-- What `items` take when each flexible one gives up all it can.
local function least(items, gap)
  local rigid = {}
  for _, item in ipairs(items) do
    if not item.flex then rigid[#rigid + 1] = item end
  end
  return span(rigid, gap)
end

-- The items of a zone that fit in `room`: what folds, and each size kept. A
-- flexible item with `hold` counts whole until the rest have folded, then takes
-- what they leave; one without counts for nothing.
local function fit(items, room, gap, dot)
  local rigid, others = {}, {}
  for _, item in ipairs(items) do
    if item.size > 0 and (not item.flex or item.hold) then
      rigid[#rigid + 1] = { id = item.id, tier = item.flex and 0 or item.tier, size = item.size + gap }
    end
    if not item.flex then others[#others + 1] = item end
  end
  local folded = M.fold(rigid, room + gap, dot + gap)
  local taken = span(others, gap, folded.hidden)
  local left = room - taken - (folded.dot and dot + gap or 0)
  local sizes = {}
  for _, item in ipairs(items) do
    sizes[item.id] = item.size
    if item.flex then
      local spare = math.max(0, left - (taken > 0 and gap or 0))
      sizes[item.id] = math.min(item.size, spare)
      left = left - sizes[item.id] - (taken > 0 and gap or 0)
      if sizes[item.id] > 0 then taken = taken + sizes[item.id] end
    end
  end
  return folded.hidden, folded.dot, sizes
end

-- `items` laid along from `at`, kept in `cells`.
local function place(items, at, gap, hidden, sizes, cells)
  for _, item in ipairs(items) do
    local size = sizes[item.id] or 0
    if hidden[item.id] then
      cells[item.id] = { at = at, size = 0, folded = true }
    else
      cells[item.id] = { at = at, size = size }
      if size > 0 then at = at + size + gap end
    end
  end
  return at
end

--- Every item's place along the row. `spec`: `zones` (each zone's items),
--- `from` and `to` (the row), `middle` (where the centre zone centres),
--- `gap_from` and `gap_to` (a cutout across the row), `gap` (between items),
--- `dot` (an overflow mark's size). Returns `{ cells, more }`: `cells[id]` is
--- `{ at, size, folded }`, `more[zone]` `{ at, ids }` where a zone folded.
function M.flow(spec)
  local gap, dot = spec.gap or 0, spec.dot or 0
  local from, to = spec.from, spec.to
  local head, centre, tail = spec.zones.start or {}, spec.zones.centre or {}, spec.zones["end"] or {}
  local cells, more = {}, {}
  local left_end, right_start

  local island
  if spec.gap_from then
    -- A cutout: the centre gives way to its two sides; only an island stays.
    local joined = {}
    for _, item in ipairs(centre) do
      if item.island and item.size > 0 then island = item else joined[#joined + 1] = item end
    end
    for _, item in ipairs(tail) do joined[#joined + 1] = item end
    tail, centre = joined, {}
    left_end, right_start = spec.gap_from, spec.gap_to
    if island then
      local at = (spec.gap_from + spec.gap_to) / 2 - (island.size - (island.extra or 0)) / 2
      cells[island.id] = { at = at, size = island.size }
      left_end, right_start = math.min(left_end, at), math.max(right_start, at + island.size)
    end
  else
    local width = span(centre, gap)
    if width > 0 then
      local at = math.max(from, math.min((spec.middle or (from + to) / 2) - width / 2, to - width))
      place(centre, at, gap, {}, (function()
        local sizes = {}
        for _, item in ipairs(centre) do sizes[item.id] = item.size end
        return sizes
      end)(), cells)
      left_end, right_start = at, at + width
    else
      for _, item in ipairs(centre) do cells[item.id] = { at = (from + to) / 2, size = 0 } end
    end
  end

  -- The end zone is placed first: what it leaves is the start zone's.
  local tail_room = to - (right_start and right_start + gap or from + least(head, gap) + gap)
  local hidden, dotted, sizes = fit(tail, tail_room, gap, dot)
  local tail_width = span(tail, gap, hidden)
  for _, item in ipairs(tail) do
    if item.flex then tail_width = tail_width - item.size + (sizes[item.id] or 0) end
  end
  local tail_at = to - tail_width
  if dotted then
    tail_at = tail_at - dot - gap
    more["end"] = { at = tail_at, ids = {} }
    for _, item in ipairs(tail) do
      if hidden[item.id] then more["end"].ids[#more["end"].ids + 1] = item.id end
    end
    place(tail, tail_at + dot + gap, gap, hidden, sizes, cells)
  else
    place(tail, tail_at, gap, hidden, sizes, cells)
  end

  local head_end = left_end and left_end - gap or tail_at - gap
  hidden, dotted, sizes = fit(head, head_end - from, gap, dot)
  local after = place(head, from, gap, hidden, sizes, cells)
  if dotted then
    more.start = { at = after, ids = {} }
    for _, item in ipairs(head) do
      if hidden[item.id] then more.start.ids[#more.start.ids + 1] = item.id end
    end
  end
  return { cells = cells, more = more }
end

return M
