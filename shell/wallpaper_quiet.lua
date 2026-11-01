-- What a picture looks like from far off: a small copy read cell by cell, for
-- how bright each part is and how busy. A clock uses it to find the picture's
-- quiet part, and ink to stand out from what is behind it.
local morf = require("morf")
local M = { COLS = 32, ROWS = 18 }

--- The reading of the picture on show: `{ cols, rows, bright, busy }`, flat
--- lists by row, or nil before there is one.
M.reading = morf.signal("eva.wallpaper.reading", false)

local function cell(list, cols, x, y) return list[y * cols + x + 1] end

--- A reading of `bright`, a flat list of brightness 0..1, `cols` across.
function M.read_cells(bright, cols, rows)
  local busy = {}
  for y = 0, rows - 1 do
    for x = 0, cols - 1 do
      local here, sum, n = cell(bright, cols, x, y), 0, 0
      for _, step in ipairs { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
        local nx, ny = x + step[1], y + step[2]
        if nx >= 0 and nx < cols and ny >= 0 and ny < rows then
          sum, n = sum + math.abs(here - cell(bright, cols, nx, ny)), n + 1
        end
      end
      busy[#busy + 1] = n > 0 and sum / n or 0
    end
  end
  return { cols = cols, rows = rows, bright = bright, busy = busy }
end

local function span(reading, x, y, w, h)
  local cols, rows = reading.cols, reading.rows
  local x0 = math.max(0, math.min(cols - 1, math.floor(x * cols)))
  local y0 = math.max(0, math.min(rows - 1, math.floor(y * rows)))
  local x1 = math.max(x0, math.min(cols - 1, math.ceil((x + w) * cols) - 1))
  local y1 = math.max(y0, math.min(rows - 1, math.ceil((y + h) * rows) - 1))
  return x0, y0, x1, y1
end

local function mean(reading, list, x, y, w, h)
  local x0, y0, x1, y1 = span(reading, x, y, w, h)
  local sum, n = 0, 0
  for cy = y0, y1 do
    for cx = x0, x1 do sum, n = sum + cell(list, reading.cols, cx, cy), n + 1 end
  end
  return n > 0 and sum / n or 0
end

--- How bright the picture is under a box, in fractions of the picture.
function M.brightness(reading, x, y, w, h) return mean(reading, reading.bright, x, y, w, h) end

--- Where a box `w` x `h` (fractions) lies quietest: its top left corner. Edges
--- are kept clear by `margin`, and a tie goes to the upper left.
function M.quietest(reading, w, h, margin)
  margin = margin or 0.04
  local best, bx, by
  local step_x, step_y = 1 / reading.cols, 1 / reading.rows
  local y = margin
  while y + h <= 1 - margin + 1e-6 do
    local x = margin
    while x + w <= 1 - margin + 1e-6 do
      local score = mean(reading, reading.busy, x, y, w, h)
      if not best or score < best - 1e-9 then best, bx, by = score, x, y end
      x = x + step_x
    end
    y = y + step_y
  end
  return bx or margin, by or margin
end

--- A colour of ink that reads over brightness `bright`.
function M.dark_ink(bright) return bright > 0.55 end

local serial = 0
--- Reads `path` on a worker, then publishes it.
function M.analyse(path)
  serial = serial + 1
  local own = serial
  if not path or path == "" then M.reading:set(false) return end
  local out = morf.paths.cache("eva-wallpaper-reading.png")
  morf.fs.mkdir(morf.paths.cache(), { parents = true })
  local queued = pcall(morf.image.process, { source = path, output = out,
    ops = { { "resize", M.COLS, M.ROWS, "fill" } },
    on_done = function(ok)
      if own ~= serial or not ok then return end
      local bright = {}
      for y = 0, M.ROWS - 1 do
        for x = 0, M.COLS - 1 do
          local color = morf.image.pixel(out, x, y)
          bright[#bright + 1] = color and color:luminance() or 0
        end
      end
      M.reading:set(M.read_cells(bright, M.COLS, M.ROWS))
    end })
  return queued
end

return M
