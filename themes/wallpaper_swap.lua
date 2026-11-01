-- One picture turning into another through a shape. The incoming image is drawn
-- through a mask of distance fields, and the mask's shapes grow over the
-- outgoing image; the engine moves them, so a transition runs no Lua per frame.
--
--     local swap = require("themes.wallpaper_swap").new { id = "desk" }
--     swap.show(path, { kind = "circle", x = 320, y = 180, width = w, height = h })
--
-- `M.KINDS` is what a picker offers. A field holds at most sixteen layers, so a
-- kind that needs more tiles several fields inside one mask.
local morf = require("morf")
local ui = require("morf.ui")
local M = {}

M.KINDS = {
  { id = "fade", name = "Fade", icon = "gradient" },
  { id = "wipe", name = "Wipe", icon = "swipe_right" },
  { id = "circle", name = "Circle", icon = "radio_button_unchecked" },
  { id = "grow", name = "Grow", icon = "bubble_chart" },
  { id = "dissolve", name = "Dissolve", icon = "blur_on" },
  { id = "stripes", name = "Stripes", icon = "view_column" },
  { id = "diamond", name = "Diamond", icon = "diamond" },
  { id = "star", name = "Star", icon = "star" },
  { id = "melt", name = "Melt", icon = "water_drop" },
}
M.POOL = { "wipe", "circle", "grow", "dissolve", "stripes", "diamond", "star", "melt" }

local TILE = 4

-- A repeatable scatter in 0..1: the same transition looks the same each time.
local function scatter(i) return (i * 0.618034) % 1 end

local function far_corner(w, h, x, y)
  local dx, dy = math.max(x, w - x), math.max(y, h - y)
  return math.sqrt(dx * dx + dy * dy)
end

-- The steps that take `shape`, a circle at (x, y), out to radius `r`.
local function bloom(steps, shape, x, y, r, delay, time, ease)
  for property, to in pairs { x = x - r, y = y - r, width = 2 * r, height = 2 * r } do
    steps[#steps + 1] = { node = shape, property = property, to = to, duration = time, delay = delay, easing = ease }
  end
end

local function dot(x, y, operation)
  return ui.SdfShape { shape = "circle", x = x, y = y, width = 0, height = 0, operation = operation }
end

local builders = {}

function builders.wipe(w, h, ctx)
  local side = 2 * math.sqrt(w * w + h * h)
  local bar = ui.SdfShape { shape = "box", x = -side - ctx.soft, y = (h - side) / 2, width = side, height = side,
    rotation = 12 }
  local field = ui.Sdf { anchors = { fill = true }, softness = ctx.soft, bar }
  return field, { { node = bar, property = "x", to = (w - side) / 2, duration = ctx.time, easing = ctx.ease } }
end

function builders.circle(w, h, ctx)
  local disc = dot(ctx.x, ctx.y)
  local steps = {}
  bloom(steps, disc, ctx.x, ctx.y, far_corner(w, h, ctx.x, ctx.y) + ctx.soft, 0, ctx.time, ctx.ease)
  return ui.Sdf { anchors = { fill = true }, softness = ctx.soft, disc }, steps
end

function builders.grow(w, h, ctx)
  local shapes = { anchors = { fill = true }, softness = ctx.soft, blend = math.min(w, h) * 0.12 }
  local steps = {}
  local reach = far_corner(w, h, w / 2, h / 2)
  for i = 1, 6 do
    local x = i == 1 and ctx.x or w * (0.12 + 0.76 * scatter(i))
    local y = i == 1 and ctx.y or h * (0.12 + 0.76 * scatter(i * 2.4 + 0.3))
    local seed = dot(x, y, i > 1 and "smooth_union" or nil)
    shapes[i] = seed
    local delay = math.floor((i - 1) * ctx.time * 0.08)
    bloom(steps, seed, x, y, reach * (i == 1 and 1.5 or 0.9), delay, ctx.time - delay, ctx.ease)
  end
  return ui.Sdf(shapes), steps
end

function builders.dissolve(w, h, ctx)
  local cell = math.max(40, math.floor(w / 16))
  local tiles, steps = { anchors = { fill = true } }, {}
  local across, down = math.ceil(w / cell), math.ceil(h / cell)
  local serial = 0
  for row = 0, math.ceil(down / TILE) - 1 do
    for col = 0, math.ceil(across / TILE) - 1 do
      local shapes = { x = col * TILE * cell, y = row * TILE * cell, width = TILE * cell, height = TILE * cell,
        softness = ctx.soft / 3, blend = cell / 5 }
      for r = 0, TILE - 1 do
        for c = 0, TILE - 1 do
          serial = serial + 1
          local x, y = (c + 0.5) * cell, (r + 0.5) * cell
          local seed = dot(x, y, #shapes > 0 and "smooth_union" or nil)
          shapes[#shapes + 1] = seed
          local delay = math.floor(scatter(serial) * ctx.time * 0.55)
          bloom(steps, seed, x, y, cell * 0.8, delay, math.floor(ctx.time * 0.45), ctx.ease)
        end
      end
      tiles[#tiles + 1] = ui.Sdf(shapes)
    end
  end
  return ui.Item(tiles), steps
end

function builders.stripes(w, h, ctx)
  local shapes, steps = { anchors = { fill = true }, softness = ctx.soft / 3 }, {}
  local band = w / 16
  for i = 0, 15 do
    local bar = ui.SdfShape { shape = "box", x = i * band, y = 0, width = band + 1, height = 0 }
    shapes[#shapes + 1] = bar
    local delay = math.floor(i / 16 * ctx.time * 0.5)
    steps[#steps + 1] = { node = bar, property = "height", to = h + ctx.soft, duration = math.floor(ctx.time / 2),
      delay = delay, easing = ctx.ease }
  end
  return ui.Sdf(shapes), steps
end

local function growing(shape, w, h, ctx, scale, extra)
  local node = ui.SdfShape(shape)
  local steps = {}
  bloom(steps, node, ctx.x, ctx.y, far_corner(w, h, ctx.x, ctx.y) * scale, 0, ctx.time, ctx.ease)
  for _, step in ipairs(extra or {}) do step.node = node steps[#steps + 1] = step end
  return ui.Sdf { anchors = { fill = true }, softness = ctx.soft, node }, steps
end

function builders.diamond(w, h, ctx)
  return growing({ shape = "box", x = ctx.x, y = ctx.y, width = 0, height = 0, rotation = 45 }, w, h, ctx, 1.5)
end

function builders.star(w, h, ctx)
  return growing({ shape = "star", points = 5, inner_radius = 0.55, x = ctx.x, y = ctx.y, width = 0, height = 0 },
    w, h, ctx, 3.4, { { property = "rotation", to = 90, duration = ctx.time, easing = ctx.ease } })
end

function builders.melt(w, h, ctx)
  local shapes, steps = { anchors = { fill = true }, softness = ctx.soft / 2, blend = w / 24 }, {}
  local drops = 12
  local wide = w / drops * 1.5
  for i = 1, drops do
    local x = (i - 1) * w / drops - wide / 6
    local drop = ui.SdfShape { shape = "box", radius = wide / 2, x = x, y = -2 * h, width = wide, height = 2 * h,
      operation = i > 1 and "smooth_union" or nil }
    shapes[i] = drop
    local delay = math.floor(scatter(i) * ctx.time * 0.4)
    steps[#steps + 1] = { node = drop, property = "y", to = wide / 2 + ctx.soft, duration = ctx.time - delay, delay = delay,
      easing = ctx.ease }
  end
  return ui.Sdf(shapes), steps
end

--- The kind a choice stands for: "random" draws from the pool, skipping `last`.
function M.pick(choice, last, roll)
  if choice ~= "random" then return choice end
  roll = roll or math.random
  local pool = {}
  for _, id in ipairs(M.POOL) do if id ~= last then pool[#pool + 1] = id end end
  return pool[roll(#pool)]
end

--- A picture that changes through a shape. `id`, `fit` (a fill mode or fn).
--- Returns `{ node, show(source, options), source(), running() }`. `options`:
--- `kind`, `x`, `y` (where it starts), `width`, `height`, `soft`, `time`, `ease`,
--- `instant`, `on_done`.
function M.new(spec)
  local fit = spec.fit or "preserve_aspect_crop"
  local function image(slot)
    return ui.Image { id = spec.id and (spec.id .. "-picture-" .. slot), anchors = { fill = true }, fill_mode = fit,
      visible = false }
  end
  local slots = { image(1), image(2) }
  local front = 1
  local running, finish = nil, nil
  local self = { last = nil, kind = "" }
  self.node = ui.Item { id = spec.id, anchors = { fill = true }, slots[1], slots[2] }

  function self.source() return slots[front].source end
  function self.running() return running ~= nil end
  function self.fronts() return slots[front] end

  function self.show(source, options)
    options = options or {}
    if finish then finish() end
    local incoming, outgoing = slots[3 - front], slots[front]
    if not incoming or source == "" then
      outgoing.visible = false
      outgoing.source = ""
      return
    end
    local had = outgoing.visible
    incoming.source = source
    incoming.opacity = 1
    incoming.z, outgoing.z = 2, 1
    incoming.visible = true
    front = 3 - front
    local kind = M.pick(options.kind or "fade", self.last, options.roll)
    self.kind, self.last = kind, kind
    local function settle()
      finish = nil
      running = nil
      incoming.mask = nil
      incoming.opacity = 1
      outgoing.visible = false
      outgoing.source = ""
      if options.on_done then options.on_done() end
    end
    if not had or options.instant then settle() return end
    local w, h = options.width or 1, options.height or 1
    local ctx = { x = options.x or w / 2, y = options.y or h / 2, soft = options.soft or 24,
      time = options.time or 1100, ease = options.ease or "in_out_cubic" }
    local steps
    if builders[kind] then
      local mask
      mask, steps = builders[kind](w, h, ctx)
      incoming.mask = mask
    else
      incoming.opacity = 0
      steps = { { node = incoming, property = "opacity", to = 1, duration = ctx.time, easing = ctx.ease } }
    end
    finish = settle
    local group = { { parallel = steps } }
    group.on_finished = function() if finish == settle then settle() end end
    running = morf.animation.play(group)
  end
  return self
end

return M
