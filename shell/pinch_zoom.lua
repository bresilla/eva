-- A picture under two fingers: spreading zooms it about their midpoint, moving
-- them pans it, one finger pans it while it is zoomed, and past its limits it
-- runs on elastically and springs back. A double tap zooms in and back out.
--
--     require("pinch_zoom").attach { node = picture, area = frame }
--
-- `node` moves (its `scale` and `translate_*` are the helper's), `area` takes
-- the gestures (`node` by default) and holds it, clipped; `most` is the largest
-- zoom (5), `pan` false leaves one finger and a double tap to the node,
-- `on_start()` runs as two fingers take over, `on_change()` follows.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local rubber = require("themes.rubber_band")
local M = {}

-- How far a zoom runs past its limits, and a double tap's.
local PAST, TAPPED = 0.6, 2.5

function M.attach(spec)
  local node, area = spec.node, spec.area or spec.node
  local most = spec.most or 5
  local z = { scale = 1, x = 0, y = 0 }
  local from, grip, running
  local function middle()
    return (node.layout_x or 0) + (node.layout_width or 0) / 2,
      (node.layout_y or 0) + (node.layout_height or 0) / 2
  end
  local function shown()
    node.scale, node.translate_x, node.translate_y = z.scale, z.x, z.y
    if spec.on_change then spec.on_change() end
  end
  -- How far it may pan at a zoom: its overhang on each side.
  local function reach(scale)
    return (node.layout_width or 0) * (scale - 1) / 2, (node.layout_height or 0) * (scale - 1) / 2
  end
  local function stop() if running then running:stop() running = nil end end
  local function settle(scale, x, y)
    local rx, ry = reach(scale)
    z.scale, z.x, z.y = scale, math.max(-rx, math.min(rx, x)), math.max(-ry, math.min(ry, y))
    stop()
    local bounce = theme.bounce.spatial
    local function step(property, to)
      return { node = node, property = property, to = to, duration = bounce.duration, easing = bounce.easing }
    end
    running = morf.animation.play { { parallel = { step("scale", z.scale), step("translate_x", z.x), step("translate_y", z.y) } },
      on_finished = function() running = nil if spec.on_change then spec.on_change() end end }
  end
  area.on_pinched = function(scale, phase, x, y)
    if phase == "update" then
      if not from then
        stop()
        local cx, cy = middle()
        from = { scale = z.scale, x = z.x, y = z.y, mx = x - cx, my = y - cy }
        if spec.on_start then spec.on_start() end
      end
      local cx, cy = middle()
      local at = rubber.between(from.scale * scale, 1, most, PAST)
      local k = at / from.scale
      z.scale = at
      z.x = (x - cx) - (from.mx - from.x) * k
      z.y = (y - cy) - (from.my - from.y) * k
      shown()
    elseif from then
      from = nil
      local scale_now = math.max(1, math.min(most, z.scale))
      if scale_now ~= z.scale or math.abs(z.x) > 0 or math.abs(z.y) > 0 then settle(scale_now, z.x, z.y) end
      require("haptics").fire("commit")
    end
  end
  if spec.pan ~= false then
    area.on_panned = function(phase, dx, dy, _, _)
      if phase == "begin" then
        if z.scale <= 1 then return false end
        stop()
        grip = { x = z.x, y = z.y }
        return true
      end
      if not grip then return end
      local rx, ry = reach(z.scale)
      if phase == "update" then
        z.x, z.y = rubber.between(grip.x + dx, -rx, rx), rubber.between(grip.y + dy, -ry, ry)
        shown()
      else
        grip = nil
        settle(z.scale, z.x, z.y)
      end
    end
    -- Under the picture, so the whole of `area` takes a finger.
    ui.reparent(ui.MouseArea { anchors = { fill = true }, z = -1,
      on_double_clicked = function(x, y)
        if z.scale > 1 then settle(1, 0, 0) else
          local cx, cy = middle()
          settle(TAPPED, -(x - cx) * (TAPPED - 1), -(y - cy) * (TAPPED - 1))
        end
        require("haptics").fire("commit")
      end }, area)
  end
  local view = {}
  --- Back at rest, as a new picture comes on show.
  function view.reset() stop() z.scale, z.x, z.y = 1, 0, 0 shown() end
  --- A surface point in the node as it stands unzoomed.
  function view.point(x, y)
    local cx, cy = middle()
    return cx + (x - cx - z.x) / z.scale, cy + (y - cy - z.y) / z.scale
  end
  function view.scale() return z.scale end
  return view
end

return M
