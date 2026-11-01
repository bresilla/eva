-- The widgets a surface can show: those of `themes.widgets_catalogue`, then
-- what eva can draw on its own.
--
-- A widget: `{ id, name, lock_safe, build = function(view) return node end }`.
-- Only a widget marked `lock_safe` is drawn on a lock. It is given `view`: the
-- drawing tools and nothing else, no door, no password, no way to act.
local morf = require("morf")
local M = {}

local function calendar(view)
  local ui, s, C, text = view.ui, view.s, view.C, view.text
  local today = morf.time.date()
  local CELL = s(26)
  local head = { gap = s(2) }
  for _, letter in ipairs { "M", "T", "W", "T", "F", "S", "S" } do
    head[#head + 1] = text { text = letter, width = CELL, horizontal_alignment = "center",
      font_size = s(12), color = C.onSurfaceVariant }
  end
  local rows = { id = view.id, gap = s(2), ui.Row(head) }
  for _, week in ipairs(morf.time.month(today.year, today.month, 1)) do
    local cells = { gap = s(2) }
    for _, day in ipairs(week) do
      local shown, lit = day.current, day.current and day.day == today.day
      cells[#cells + 1] = ui.Rect { width = CELL, height = CELL, radius = CELL / 2,
        color = lit and C.primary or C.primary:alpha(0),
        text { anchors = { center_in = true }, text = shown and tostring(day.day) or "", font_size = s(13),
          color = lit and C.onPrimary or C.onSurface } }
    end
    rows[#rows + 1] = ui.Row(cells)
  end
  return ui.Column(rows)
end

M.BUILT_IN = {
  { id = "calendar", name = "Calendar", lock_safe = true, build = calendar },
}

--- Every widget there is: the catalogue's, then the built-in ones.
function M.list()
  local out = {}
  local ok, stream = pcall(require, "themes.widgets_catalogue")
  if ok and type(stream) == "table" and type(stream.list) == "function" then
    local fine, list = pcall(stream.list)
    for _, widget in ipairs(fine and type(list) == "table" and list or {}) do out[#out + 1] = widget end
  end
  for _, widget in ipairs(M.BUILT_IN) do out[#out + 1] = widget end
  return out
end

--- The widgets named in `ids` that may stand on a lock, in that order.
function M.for_lock(ids)
  local by_id = {}
  for _, widget in ipairs(M.list()) do by_id[widget.id] = by_id[widget.id] or widget end
  local out = {}
  for _, id in ipairs(ids or {}) do
    local widget = by_id[id]
    if widget and widget.lock_safe == true and type(widget.build) == "function" then out[#out + 1] = widget end
  end
  return out
end

return M
