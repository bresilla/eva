-- A desk scroll bar over a page's right edge, shared by the desk themes: it
-- stands out while the page moves and fades once it rests, so it never sits
-- over a card's edge. Still there to drag where a pointer finds it.
local morf = require("morf")

return function(t, spec, o)
  local flick = spec.flick
  local function room() return math.max(0, t.content_height - t.viewport_height) end
  local bar = require("themes.kit.widgets").scroll_bar { width = o.width, orientation = "vertical", inverted = true,
    accessible_name = "Scroll position",
    anchors = { right = true, top = true, bottom = true, right_margin = o.margin, top_margin = o.ends, bottom_margin = o.ends },
    visible = function() return t.bar_y end,
    value = function() return t.position_y end,
    size = function() return t.size_y end,
    handle_size = function() return math.max(24, t.size_y * t.viewport_height) end,
    on_moved = function(v) if flick then flick.content_y = v * room() end end,
    opacity = 0 }
  local last = flick and flick.content_y or 0
  local timeout, fade
  morf.effect("desk.scroll.bar." .. tostring(bar), function()
    local offset = flick and flick.content_y or 0
    if offset == last then return end
    last = offset
    if timeout then timeout:cancel() end
    if fade then fade:stop() fade = nil end
    if (bar.opacity or 0) < 1 then
      fade = morf.animation.play { { node = bar, property = "opacity", to = 1, duration = 120, easing = "out_cubic" } }
    end
    timeout = morf.time.timer(900, function()
      timeout = nil
      fade = morf.animation.play { { node = bar, property = "opacity", to = 0, duration = 260, easing = "out_cubic" } }
    end, false)
  end, { owner = bar })
  return bar
end
