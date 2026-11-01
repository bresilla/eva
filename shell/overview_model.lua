-- The overview's arithmetic: where cards go, which workspaces it shows, what
-- a point falls on. No nodes and no compositor calls.
local windows = require("windows_model")
local services = require("services")
local M = {}

-- Nine workspaces per output, as the rail keeps them.
local COUNT, STRIDE = 9, 10

--- `sizes` (each `{ width, height }`) laid out in `rows` rows, by running
--- width: the rows, each a list of indices.
local function rows_of(sizes, gap, count)
  local total = 0
  for _, s in ipairs(sizes) do total = total + s.width + gap end
  local target = total / count
  local rows, row, run = { {} }, 1, 0
  for i, s in ipairs(sizes) do
    local left = #sizes - i + 1
    if run >= target and row < count and left >= count - row then
      row, run = row + 1, 0
      rows[row] = {}
    end
    table.insert(rows[row], i)
    run = run + s.width + gap
  end
  return rows
end

--- Fits `sizes` into `area` (`x, y, width, height`) keeping their shapes, as
--- large as they go, no larger than they are: a box per size, in order.
function M.arrange(sizes, area, gap)
  if #sizes == 0 then return {} end
  local best_scale, best_rows
  for count = 1, #sizes do
    local rows = rows_of(sizes, gap, count)
    local heights, widest = 0, 0
    for _, row in ipairs(rows) do
      local width, height = -gap, 0
      for _, i in ipairs(row) do
        width = width + sizes[i].width + gap
        height = math.max(height, sizes[i].height)
      end
      heights = heights + height
      widest = math.max(widest, width)
    end
    local free_h = area.height - gap * (#rows - 1)
    local scale = math.min(1, area.width / math.max(1, widest), free_h / math.max(1, heights))
    if not best_scale or scale > best_scale + 1e-6 then best_scale, best_rows = scale, rows end
  end
  local out, heights = {}, 0
  local row_heights = {}
  for r, row in ipairs(best_rows) do
    local height = 0
    for _, i in ipairs(row) do height = math.max(height, sizes[i].height * best_scale) end
    row_heights[r] = height
    heights = heights + height
  end
  local y = area.y + (area.height - heights - gap * (#best_rows - 1)) / 2
  for r, row in ipairs(best_rows) do
    local width = -gap
    for _, i in ipairs(row) do width = width + sizes[i].width * best_scale + gap end
    local x = area.x + (area.width - width) / 2
    for _, i in ipairs(row) do
      local w, h = sizes[i].width * best_scale, sizes[i].height * best_scale
      out[i] = { x = x, y = y + (row_heights[r] - h) / 2, width = w, height = h }
      x = x + w + gap
    end
    y = y + row_heights[r] + gap
  end
  return out
end

--- The boxes of `count` desks of one shape in a row, centred in `area`.
function M.strip(count, area, aspect, gap)
  local h = area.height
  local w = h * aspect
  local total = count * w + (count - 1) * gap
  if total > area.width then
    w = (area.width - (count - 1) * gap) / math.max(1, count)
    h = w / aspect
    total = area.width
  end
  local out, x = {}, area.x + (area.width - total) / 2
  for i = 1, count do
    out[i] = { x = x, y = area.y + (area.height - h) / 2, width = w, height = h }
    x = x + w + gap
  end
  return out
end

--- The first box of `boxes` holding the point, by its key: `{ key = box }`.
function M.hit(boxes, x, y)
  for key, b in pairs(boxes) do
    if x >= b.x and x < b.x + b.width and y >= b.y and y < b.y + b.height then return key end
  end
end

--- The workspaces to show for each monitor, as desks: `id`, `name`, `monitor`,
--- `active`, `windows` (rows), with the next empty one at the end.
function M.desks()
  local out = {}
  local workspaces = windows.workspaces()
  for _, m in ipairs(windows.monitors()) do
    local ids, by = {}, {}
    for _, w in ipairs(workspaces) do
      if w.id > 0 and (w.monitor == m.name or w.monitor == "") then
        by[w.id] = w
        ids[#ids + 1] = w.id
      end
    end
    local shown = windows.int(m.active_workspace or 0)
    if shown > 0 and not by[shown] then ids[#ids + 1] = shown end
    table.sort(ids)
    local base = (((ids[1] or math.max(shown, 1)) - 1) // STRIDE) * STRIDE + 1
    local free
    for id = base, base + COUNT - 1 do
      local used = by[id] ~= nil or id == shown
      if not used then free = id break end
    end
    if free then
      ids[#ids + 1] = free
      table.sort(ids)
    end
    for _, id in ipairs(ids) do
      local row = by[id] or {}
      local name = row.name ~= nil and row.name ~= "" and row.name or tostring(id)
      out[#out + 1] = { id = id, name = name, named = name ~= tostring(id), monitor = m.name, monitor_id = m.id,
        active = id == shown, windows = windows.on(id) }
    end
  end
  return out
end

--- The nearest box to `from` in direction `dx, dy`, by its key.
function M.step(boxes, from, dx, dy)
  local origin = boxes[from]
  if not origin then return next(boxes) end
  local fx, fy = origin.x + origin.width / 2, origin.y + origin.height / 2
  local best, score
  for key, b in pairs(boxes) do
    if key ~= from then
      local bx, by = b.x + b.width / 2 - fx, b.y + b.height / 2 - fy
      local along, across = bx * dx + by * dy, math.abs(bx * dy - by * dx)
      if along > 4 then
        local s = along + across * 2.5
        if not score or s < score then best, score = key, s end
      end
    end
  end
  return best
end

--- This output's workspace on show.
function M.here() return windows.int(services.workspace.active()) end

return M
