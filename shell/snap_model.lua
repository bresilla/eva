-- Snapping's arithmetic: the cells a screen divides into, the zone a point
-- falls in, the layouts on offer. Boxes are in the compositor's logical
-- pixels. No nodes and no compositor calls.
local M = {}

-- A cell as fractions of the free area: x, y, width, height.
M.CELLS = {
  left = { 0, 0, .5, 1 }, right = { .5, 0, .5, 1 },
  top = { 0, 0, 1, .5 }, bottom = { 0, .5, 1, .5 },
  top_left = { 0, 0, .5, .5 }, top_right = { .5, 0, .5, .5 },
  bottom_left = { 0, .5, .5, .5 }, bottom_right = { .5, .5, .5, .5 },
  full = { 0, 0, 1, 1 }, center = { .15, .1, .7, .8 },
  left_third = { 0, 0, 1 / 3, 1 }, center_third = { 1 / 3, 0, 1 / 3, 1 }, right_third = { 2 / 3, 0, 1 / 3, 1 },
  left_two = { 0, 0, 2 / 3, 1 }, right_two = { 1 / 3, 0, 2 / 3, 1 },
}

-- The layouts on offer: each its cells, filled in order.
M.LAYOUTS = {
  { key = "halves", name = "Halves", cells = { "left", "right" } },
  { key = "stacked", name = "Stacked", cells = { "top", "bottom" } },
  { key = "thirds", name = "Thirds", cells = { "left_third", "center_third", "right_third" } },
  { key = "main_left", name = "Main left", cells = { "left_two", "right_third" } },
  { key = "main_right", name = "Main right", cells = { "left_third", "right_two" } },
  { key = "quarters", name = "Quarters", cells = { "top_left", "top_right", "bottom_left", "bottom_right" } },
  { key = "main_stack", name = "Main and stack", cells = { "left", "top_right", "bottom_right" } },
}
M.BY_KEY = {}
for _, layout in ipairs(M.LAYOUTS) do M.BY_KEY[layout.key] = layout end

-- What a cell's other side is: the cells snap assist offers to fill.
M.FREE = {
  left = { "right" }, right = { "left" }, top = { "bottom" }, bottom = { "top" },
  top_left = { "top_right", "bottom_left", "bottom_right" },
  top_right = { "top_left", "bottom_left", "bottom_right" },
  bottom_left = { "top_left", "top_right", "bottom_right" },
  bottom_right = { "top_left", "top_right", "bottom_left" },
  left_third = { "right_two" }, right_third = { "left_two" }, left_two = { "right_third" }, right_two = { "left_third" },
}

--- The monitor's free area, in logical pixels: without what is reserved on
--- its edges (`reserved` is left, top, right, bottom).
function M.area(monitor)
  local scale = math.max(.01, monitor.scale or 1)
  local r = monitor.reserved or {}
  local left, top, right, bottom = r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 0
  return { x = (monitor.x or 0) + left, y = (monitor.y or 0) + top,
    width = (monitor.width or 0) / scale - left - right, height = (monitor.height or 0) / scale - top - bottom }
end

--- A cell's box in `area`, `gap` apart from its neighbours and the edges.
function M.box(cell, area, gap)
  local c = M.CELLS[cell]
  if not c then return nil end
  gap = gap or 0
  local x0, y0 = area.x + c[1] * area.width, area.y + c[2] * area.height
  local x1, y1 = x0 + c[3] * area.width, y0 + c[4] * area.height
  local half = gap / 2
  local left = c[1] == 0 and gap or half
  local top = c[2] == 0 and gap or half
  local right = c[1] + c[3] >= 1 - 1e-6 and gap or half
  local bottom = c[2] + c[4] >= 1 - 1e-6 and gap or half
  return { x = math.floor(x0 + left), y = math.floor(y0 + top),
    width = math.floor(x1 - x0 - left - right), height = math.floor(y1 - y0 - top - bottom) }
end

--- The cell a point near an edge of `area` falls in, nil away from the
--- edges: `reach` from an edge is near it, `corner` from a corner is the
--- corner, and the top edge's middle is the whole screen.
function M.zone(x, y, area, reach, corner)
  local left, right = x - area.x, area.x + area.width - x
  local top, bottom = y - area.y, area.y + area.height - y
  local near_left, near_right = left < reach, right < reach
  local near_top, near_bottom = top < reach, bottom < reach
  if near_left and top < corner then return "top_left" end
  if near_left and bottom < corner then return "bottom_left" end
  if near_right and top < corner then return "top_right" end
  if near_right and bottom < corner then return "bottom_right" end
  if near_top and left < corner then return "top_left" end
  if near_top and right < corner then return "top_right" end
  if near_bottom and left < corner then return "bottom_left" end
  if near_bottom and right < corner then return "bottom_right" end
  if near_left then return "left" end
  if near_right then return "right" end
  if near_top then return "full" end
  if near_bottom then return "bottom" end
  return nil
end

--- `count` windows into the layout `key`: the cell for each, the last cell
--- shared by what is left over.
function M.assign(key, count)
  local layout = M.BY_KEY[key]
  if not layout then return {} end
  local out = {}
  for i = 1, count do out[i] = layout.cells[math.min(i, #layout.cells)] end
  return out
end

return M
