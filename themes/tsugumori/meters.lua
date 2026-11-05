-- Quiet instrument levels: square segments lit up to a value. (The slider
-- and the media rail are skins of the kit's Range: skins.lua.)
local morf = require("morf")
local ui = require("morf.ui")

return function(theme, kit)
  local C = theme.color
  local M = {}
  local function clamp(v) return math.max(0, math.min(1, v)) end

  --- Drives `node.trim_end` to `lit()` (a fraction of `n` cells) one whole
  --- cell at a time: cells light in sequence, quickly first and then
  --- slower, from wherever the run stands when the value changes.
  function M.stepped(node, lit, n)
    local running
    node.trim_end = math.max(.0001, lit())
    morf.effect("tsugumori.meter.step", function()
      local target = math.max(.0001, lit())
      if running then running:stop() running = nil end
      local from = node.trim_end or target
      local a, b = math.floor(from * n + .5), math.floor(target * n + .5)
      local count = math.abs(b - a)
      if count == 0 then node.trim_end = target return end
      local frames, before, last = { { at = 0, value = from } }, from, 0
      for k = 1, count do
        local at = (k / count) ^ 2
        local value = k == count and target or (a + (b > a and k or -k)) / n
        frames[#frames + 1] = { at = math.max(last + 1e-4, at - math.min(.002, (at - last) / 2)), value = before }
        frames[#frames + 1] = { at = at, value = value }
        before, last = value, at
      end
      running = morf.animation.play { { node = node, property = "trim_end", duration = math.min(360, 60 + 22 * count),
        keyframes = frames }, on_finished = function() running = nil end }
    end, { owner = node })
    return node
  end

  --- A thin level: square segments, lit up to the value.
  function M.bar(spec)
    local W, H = spec.width, spec.stroke or 4
    local color = spec.color or function() return C.primary end
    local n = math.max(6, math.floor(W / 7))
    local gap = 2
    local seg = math.max(0.5, (W - gap * (n - 1)) / n)
    local d = ("M0 %g H%g"):format(H / 2, W)
    local function lit() return math.floor(clamp(spec.value()) * n + .5) / n end
    return ui.Item { id = spec.id, x = spec.x, y = spec.y, anchors = spec.anchors, width = W, height = H,
      ui.Path { width = W, height = H, view_box = { 0, 0, W, H }, d = d, fill_color = "transparent",
        stroke_width = H, dash = { seg, gap }, stroke_cap = "butt",
        stroke_color = spec.track or function() return C.primary:alpha(.16) end },
      M.stepped(ui.Path { id = spec.id and spec.id .. "-fill", width = W, height = H, view_box = { 0, 0, W, H }, d = d,
        fill_color = "transparent", stroke_width = H, dash = { seg, gap }, stroke_cap = "butt", stroke_color = color,
        opacity = function() return lit() > 0 and 1 or 0 end }, lit, n),
    }
  end

  return M
end
