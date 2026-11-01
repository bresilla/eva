-- Where the panels of the top and bottom edges stand among a desk's side
-- panels. Each keeps to the middle while it clears them, is pushed along by a
-- side panel it would meet, and between two gives up width down to `LEAST`;
-- past that the panel open longest shuts. Where a panel touches a side one
-- their backgrounds join.
local morf = require("morf")
local theme = require("theme")
local M = {}

-- The bottom panel's width by choice, the dashboard's overview's; the least
-- any panel is laid out at, a side panel's page.
M.WANT, M.LEAST = 840, theme.SIDE_W
-- The least the bottom panel stands at under the dashboard.
M.LEAST_H = 320

--- What a side panel takes from the opening while open.
function M.side() return theme.SIDE_W + theme.STRIP end

--- The opening's width.
function M.opening() return require("responsive").desk_width() - theme.LEFT - theme.BORDER end

local function open(name)
  local d = require("drawer")[name]
  return d ~= nil and d.open:get()
end

local function taken(name) return open(name) and M.side() or 0 end

--- Where a panel wanting `want` stands in an opening `opening` wide, with
--- `left` and `right` taken from its ends: x and width.
function M.place(opening, left, right, want, least)
  local room = math.max(0, opening - left - right)
  local width = math.max(math.min(want, room), math.min(least or want, want))
  local x = math.floor((opening - width) / 2)
  return math.max(left, math.min(x, opening - right - width)), width
end

--- Where a panel wanting `want` stands now, x and width.
function M.span(want, least)
  return M.place(M.opening(), taken("leftbar"), taken("sidebar"), want, least)
end

--- Whether a panel at `x`, `width` touches the open side panel on `side`.
function M.joined(side, x, width)
  if side == "left" then return open("leftbar") and x <= M.side() + 0.5 end
  return open("sidebar") and x + width >= M.opening() - M.side() - 0.5
end

--- The `corners` of a drawer on `edge` (drawer.lua): those facing the side
--- panels square off as it joins them, so the seam runs straight into
--- theirs. `where()` is its x and width.
function M.corners(edge, where)
  local function corner(side)
    return function()
      local x, width = where()
      return M.joined(side, x, width) and 0 or theme.ROUNDING
    end
  end
  local row = edge == "bottom" and "top" or "bottom"
  local left, right = row .. "_left_radius", row .. "_right_radius"
  return { [left] = corner("left"), [right] = corner("right"),
    behavior = { [left] = theme.spring.effects, [right] = theme.spring.effects } }
end

-- What a panel in the middle needs across the opening.
local NEEDS = {
  bottom = function() return M.LEAST end,
  dashboard = function()
    local dashboard = require("dashboard")
    return (dashboard.size(dashboard.tab:get()))
  end,
  launcher = function() return require("launcher").width() end,
}

-- The height of the dashboard while it is open, else 0.
local function top_taken()
  if not open("dashboard") then return 0 end
  local dashboard = require("dashboard")
  return select(2, dashboard.size(dashboard.tab:get()))
end

-- What the desk leaves the bottom panel under the dashboard.
local function under_top()
  return require("responsive").desk_height() - 2 * theme.BORDER - theme.space.l - top_taken()
end

--- The bottom panel's height when it wants `want`: under the dashboard while
--- that is open, down to `LEAST_H`.
function M.height(want)
  if not open("dashboard") then return want end
  return math.max(math.min(want, M.LEAST_H), math.min(want, under_top()))
end

--- Whether the side panel on `side` stands in a panel `width` wide, centred
--- on the opening.
function M.collides(side, width)
  if not open(side == "left" and "leftbar" or "sidebar") then return false end
  local x = (M.opening() - width) / 2
  if side == "left" then return x < M.side() end
  return x + width > M.opening() - M.side()
end

--- Shuts the side panels a centred panel `width` wide would stand in.
function M.clear(width)
  for side, name in pairs { left = "leftbar", right = "sidebar" } do
    if M.collides(side, width) then require("drawer")[name].set(false) end
  end
end

-- Every panel of the set in the order it opened, oldest first.
local order, stamp, seen = {}, 0, {}
local function note(name, now)
  if now == (seen[name] or false) then return end
  seen[name] = now
  if now then stamp = stamp + 1 order[name] = stamp else order[name] = nil end
end

local function oldest(names)
  local found
  for _, name in ipairs(names) do
    if order[name] and (not found or order[name] < order[found]) then found = name end
  end
  return found
end

--- The panel to shut when those open are too many for the opening, or nil.
function M.crowded()
  for _, middle in ipairs { "launcher", "bottom", "dashboard" } do
    if open(middle) and NEEDS[middle]() + taken("leftbar") + taken("sidebar") > M.opening() + 0.5 then
      return oldest { "leftbar", "sidebar", middle }
    end
  end
  if open("bottom") and open("dashboard") and under_top() < M.LEAST_H then
    return oldest { "bottom", "dashboard" }
  end
end

--- Starts watching the panels: what opened last stays.
function M.watch()
  if require("responsive").sheets() then return end
  morf.effect("eva.panels.room", function()
    for _, name in ipairs { "leftbar", "sidebar", "bottom", "dashboard", "launcher" } do note(name, open(name)) end
    local shut = M.crowded()
    -- Shut outside the effect that noticed.
    if shut then morf.time.timer(1, function() require("drawer")[shut].set(false) end, false) end
  end)
end

return M
