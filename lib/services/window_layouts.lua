-- A saved arrangement of windows, as plain rows, and which running window is
-- which saved one. Pure: shell/layouts_model.lua reads and moves real ones.
local M = {}

--- The rows to keep for `list` (windows_model's), `monitors` their screens.
--- `known(class)` says whether something can start that class again.
function M.capture(list, monitors, known)
  local names, out = {}, {}
  for _, m in ipairs(monitors or {}) do names[m.id] = m.name end
  for _, c in ipairs(list or {}) do
    if type(c.workspace) == "number" and c.workspace > 0 then
      out[#out + 1] = { class = c.class or "", title = c.title or "", workspace = c.workspace, monitor = names[c.monitor] or "",
        floating = c.floating == true, pinned = c.pinned == true, fullscreen = c.fullscreen or 0,
        x = c.x, y = c.y, width = c.width, height = c.height, startable = known(c.class or "") }
    end
  end
  return out
end

--- Pairs saved rows with `running` windows: the same class and title first,
--- then the same class. Answers `pairs` ({ saved, window }) and `missing`.
function M.match(saved, running)
  local free, pairs_out, missing = {}, {}, {}
  for _, c in ipairs(running or {}) do free[#free + 1] = c end
  local function take(test)
    for index, c in ipairs(free) do
      if test(c) then
        table.remove(free, index)
        return c
      end
    end
  end
  local left = {}
  for _, row in ipairs(saved or {}) do
    local found = take(function(c) return c.class == row.class and c.title == row.title end)
    if found then pairs_out[#pairs_out + 1] = { saved = row, window = found } else left[#left + 1] = row end
  end
  for _, row in ipairs(left) do
    local found = take(function(c) return c.class == row.class end)
    if found then pairs_out[#pairs_out + 1] = { saved = row, window = found } else missing[#missing + 1] = row end
  end
  return pairs_out, missing
end

--- Whether `window` already stands where `saved` says.
function M.placed(saved, window)
  if window.workspace ~= saved.workspace or (window.floating == true) ~= (saved.floating == true) then return false end
  if not saved.floating then return true end
  return math.abs((window.x or 0) - (saved.x or 0)) < 3 and math.abs((window.y or 0) - (saved.y or 0)) < 3
    and math.abs((window.width or 0) - (saved.width or 0)) < 3 and math.abs((window.height or 0) - (saved.height or 0)) < 3
end

--- The name a saved window goes by in a report.
function M.label(row)
  return row.class ~= "" and row.class or row.title
end

return M
