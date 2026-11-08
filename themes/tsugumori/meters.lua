-- Quiet instrument levels: square segments lit up to a value. (The slider
-- and the media rail are skins of the kit's Range: skins.lua.)
local morf = require("morf")
local ui = require("morf.ui")
local registry = require("themes.tsugumori.marks")

return function(theme, kit)
  local C = theme.color
  local M = {}
  local function clamp(v) return math.max(0, math.min(1, v)) end

  --- Drives `node.trim_end` to `lit()` (a fraction of `n` cells) one whole
  --- cell at a time: cells light in sequence, quickly first and then
  --- slower, from wherever the run stands when the value changes. A boot
  --- pass reaching it runs it up again from empty.
  function M.stepped(node, lit, n)
    local running
    local function run(from, target, delay, ms)
      if running then running:stop() running = nil end
      local a, b = math.floor(from * n + .5), math.floor(target * n + .5)
      local count = math.abs(b - a)
      if count == 0 then node.trim_end = target return false end
      local frames, before, last = { { at = 0, value = from } }, from, 0
      for k = 1, count do
        local at = (k / count) ^ 2
        local value = k == count and target or (a + (b > a and k or -k)) / n
        frames[#frames + 1] = { at = math.max(last + 1e-4, at - math.min(.002, (at - last) / 2)), value = before }
        frames[#frames + 1] = { at = at, value = value }
        before, last = value, at
      end
      local track = { node = node, property = "trim_end", duration = ms(count), keyframes = frames }
      if delay and delay > 0 then node.trim_end = from track = { sequence = { { pause = delay }, track } } end
      running = morf.animation.play { track, on_finished = function() running = nil end }
      return true
    end
    local function quick(count) return math.min(360, 60 + 22 * count) end
    local function slow(count) return math.min(440, 90 + 26 * count) end
    local wanted = math.max(.0001, lit())
    node.trim_end = wanted
    morf.effect("tsugumori.meter.step", function()
      local target = math.max(.0001, lit())
      local from = node.trim_end or target
      if target == wanted then return end
      wanted = target
      run(from, target, 0, quick)
    end, { owner = node })
    registry.values[node] = function(delay)
      if not run(.0001, math.max(.0001, lit()), math.max(1, delay), slow) then return nil end
      return function()
        if running then running:stop() running = nil end
        pcall(function() node.trim_end = math.max(.0001, lit()) end)
      end
    end
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
