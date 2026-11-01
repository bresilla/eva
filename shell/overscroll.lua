-- A list pulled past its end runs on elastically and springs back. The
-- engine offers a view's parent a drag the view has no room left for, so the
-- handler goes on the node holding the flickable and only ever sees those.
--
--     holder.on_panned = require("overscroll").new {
--       flick = flick, room = function() return content_h - view_h end }.on_panned
--
-- A pull that shuts a panel is the panel's, and a pull an enclosing view can
-- still scroll is that view's. `sideways` is a view that scrolls so. With
-- `on_refresh(done)`, a pull past the start let go past `REST` holds the list
-- there until `done()`; `on_pull(fraction, refreshing)` follows it, 1 at REST.
local morf = require("morf")
local theme = require("theme")
local rubber = require("rubber_band")
local M = { REST = 64 }
-- The most a pull moves a list past its end.
local REACH = 120

local live = setmetatable({}, { __mode = "k" })

local function covers(flick, x, y)
  local left, top = flick.layout_x or 0, flick.layout_y or 0
  return x >= left and x < left + (flick.layout_width or 0)
    and y >= top and y < top + (flick.layout_height or 0)
end

local function area(flick) return (flick.layout_width or 0) * (flick.layout_height or 0) end

-- Whether a larger view under the point still has room the way `along` drags.
local function enclosed(self, along, x, y)
  for other in pairs(live) do
    if other ~= self and other.sideways == self.sideways and covers(other.flick, x, y)
      and area(other.flick) >= area(self.flick) then
      local at = other.flick[other.property] or 0
      if along > 0 and at > 0.5 then return true end
      if along < 0 and at < other.room() - 0.5 then return true end
    end
  end
  return false
end

function M.new(spec)
  local s = { flick = spec.flick, room = spec.room, sideways = spec.sideways == true,
    property = spec.sideways and "content_x" or "content_y" }
  live[s] = true
  local held, settling
  local refreshing = false
  local function along(dx, dy) if s.sideways then return dx end return dy end
  local function pulled(fraction) if spec.on_pull then spec.on_pull(fraction, refreshing) end end
  local function glide(to)
    local bounce = theme.bounce.spatial
    settling = morf.animation.play { { node = s.flick, property = s.property, to = to,
      duration = bounce.duration, easing = bounce.easing } }
  end
  local function refresh()
    refreshing = true
    pulled(1)
    require("haptics").fire("commit")
    glide(-M.REST)
    spec.on_refresh(function()
      refreshing = false
      pulled(0)
      if not held then glide(0) end
    end)
  end
  local function settle()
    local rest, shown = held.rest, -(s.flick[s.property] or 0)
    held = nil
    if rest == 0 and spec.on_refresh and not refreshing and shown >= M.REST then return refresh() end
    if not refreshing then pulled(0) end
    glide(refreshing and -M.REST or rest)
  end
  function s.on_panned(phase, dx, dy, _, _, x, y)
    if phase == "begin" then
      if math.abs(along(dx, dy)) <= math.abs(along(dy, dx)) then return false end
      local pull = along(dx, dy)
      local direction = s.sideways and (dx < 0 and "left" or "right") or (dy < 0 and "up" or "down")
      local panels = package.loaded.phone_gestures
      if panels and panels.pulls_shut(direction, x, y) then return false end
      if x and y and enclosed(s, pull, x, y) then return false end
      if settling then settling:stop() settling = nil end
      held = { rest = pull > 0 and 0 or math.max(0, s.room()) }
    end
    if not held then return end
    if phase == "begin" or phase == "update" then
      local shown = rubber.band(along(dx, dy), REACH)
      s.flick[s.property] = held.rest - shown
      if held.rest == 0 and not refreshing then pulled(math.max(0, shown) / M.REST) end
    else settle() end
  end
  return s
end

return M
