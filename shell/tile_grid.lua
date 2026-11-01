-- Where quick-settings tiles go: rows of slots, each slot two half columns
-- wide. A full tile takes a slot's width and a small one half of it, so two
-- small tiles share a slot. Geometry only: no nodes and no state.
local G = {}

--- Flows `items` (a list of `{ id, small }`) along `columns` slots. Returns
--- the cells by id (`column` in half columns, `row`, `span` in half columns)
--- and how many rows they take.
function G.flow(items, columns)
  local cells, column, row = {}, 0, 0
  local across = columns * 2
  for _, item in ipairs(items) do
    local span = item.small and 1 or 2
    if column + span > across then column, row = 0, row + 1 end
    cells[item.id] = { column = column, row = row, span = span }
    column = column + span
  end
  return cells, #items > 0 and row + 1 or 0
end

--- A cell's box inside the grid's own origin: `metrics` has `half` (a half
--- column's width), `gap` and `height`.
function G.box(cell, metrics)
  local x = cell.column * (metrics.half + metrics.gap)
  local y = cell.row * (metrics.height + metrics.gap)
  return x, y, cell.span * metrics.half + (cell.span - 1) * metrics.gap, metrics.height
end

--- How tall `rows` rows stand.
function G.height(rows, metrics)
  if rows <= 0 then return 0 end
  return rows * metrics.height + (rows - 1) * metrics.gap
end

--- `items` with `id` taken out and put at `index`.
local function moved(items, id, index)
  local out, carried = {}, nil
  for _, item in ipairs(items) do
    if item.id == id then carried = item else out[#out + 1] = item end
  end
  if carried then table.insert(out, math.max(1, math.min(index, #out + 1)), carried) end
  return out
end
G.moved = moved

--- The index `id` belongs at for its centre to rest nearest (x, y): every
--- insertion is flowed and the closest kept.
function G.nearest(items, id, x, y, columns, metrics)
  local best, distance
  for index = 1, #items do
    local cell = G.flow(moved(items, id, index), columns)[id]
    if cell then
      local bx, by, bw, bh = G.box(cell, metrics)
      local dx, dy = bx + bw / 2 - x, by + bh / 2 - y
      local d = dx * dx + dy * dy
      if not distance or d < distance then best, distance = index, d end
    end
  end
  return best
end

return G
