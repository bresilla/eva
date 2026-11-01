-- The live pill: what is going on, in one surface that grows out of the bar. It
-- is a distance field, so a press morphs the pill into a panel and back, its
-- progress is cut from the same outline, and a second activity buds off it as a
-- bubble joined by a seam that thins and parts as they spring apart. Over a cutout
-- it wraps the camera, with the icon on one side and the words on the other.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local responsive = require("responsive")
local C = theme.color
local S = theme.space

local V = {}
local WIDE, MARGIN = 420, S.s

--- The pill for the bar's modules `ctx`. Returns `{ node, part(), follow(vertical,
--- cell) }`: `node` goes on the bar, `part` is what the zones place, and `follow`
--- says where a strip put it.
function V.build(ctx)
  local model = ctx.model
  local live = model.live
  local ITEM, ICONS_H = ctx.ITEM, ctx.ICONS_H
  local HIGH = math.min(ITEM, S.xxl + S.xs)
  local cells = {}
  local place = { at = 0, size = 0 }
  local function expanded() return live.expanded:get() and live.count() > 0 end
  local function current() return live.current() end
  local function second() return live.second() end
  local function any() return live.count() > 0 end
  local function vertical() return model.vertical() end
  local function field(name)
    return function()
      local now = current()
      local value = now and now[name]
      if type(value) == "function" then value = value() end
      return value
    end
  end
  local function tone()
    local now = current()
    return now and kit.signal(now.tone)() or C.primary
  end

  local function cell()
    local read = cells[vertical()]
    local c = read and read()
    if c then place = c end
    return place
  end
  local function cutout()
    if vertical() then return 0 end
    local l = responsive.lanes(model.side() == "top" and 40 or 0)
    return l.gap_from and (l.gap_to - l.gap_from) or 0
  end

  -- The pill's size at rest: the icon, the words and any cutout between them.
  local words = kit.text { text = function() return field("short")() or "" end, font_size = theme.size.small, font_weight = 600,
    opacity = 0 }
  local function words_w() return math.min(words.layout_width or 0, 180) end
  local function rest_along()
    if vertical() then return HIGH end
    local cut = cutout()
    if cut > 0 then return math.max(ICONS_H, words_w()) * 2 + cut + S.m end
    return ICONS_H + words_w() + 3 * S.s
  end
  local function total()
    if not any() then return 0 end
    return rest_along() + (second() and (HIGH + S.xs) or 0)
  end

  local function bar_size()
    local i = model.insets()
    return i.left + i.right + theme.LEFT, i.top + i.bottom + theme.BORDER
  end

  -- The panel's size once pressed.
  local detail
  local function open_w()
    local w = model.screen()
    return math.min(WIDE, (w or WIDE) - 2 * S.l)
  end
  local function open_h() return (detail and detail.layout_height or 0) + 2 * S.m end

  local function box()
    local c, across, w, h = cell(), HIGH, model.screen()
    local thick_w, thick_h = bar_size()
    local side = model.side()
    if vertical() then
      local x = (thick_w - across) / 2
      if not expanded() then return x, c.at, across, rest_along() end
      local y = math.max(MARGIN, math.min(c.at + c.size / 2 - open_h() / 2, (h or 0) - open_h() - MARGIN))
      return side == "right" and x + across - open_w() or x, y, open_w(), open_h()
    end
    local y = (thick_h - across) / 2
    if not expanded() then return c.at, y, rest_along(), across end
    local x = math.max(MARGIN, math.min(c.at + c.size / 2 - open_w() / 2, (w or 0) - open_w() - MARGIN))
    return x, side == "bottom" and y + across - open_h() or y, open_w(), open_h()
  end

  local spring = theme.spring.spatial
  local main = ui.Item { id = "bar-live",
    x = function() return (select(1, box())) end, y = function() return (select(2, box())) end,
    width = function() return (select(3, box())) end, height = function() return (select(4, box())) end,
    visible = any, behavior = { x = spring, y = spring, width = spring, height = spring },
    stretch = { stiffness = 260, damping = 20, scale = 0.08 } }

  -- A second activity, standing off the end of the pill until a press draws it in.
  local bubble = ui.Item { id = "bar-live-bubble",
    width = function() return (not expanded() and second()) and HIGH or HIGH * 0.4 end,
    height = function() return (not expanded() and second()) and HIGH or HIGH * 0.4 end,
    x = function()
      local x, _, w = box()
      if expanded() or not second() then return x + w / 2 end
      return vertical() and x or x + w + S.xs
    end,
    y = function()
      local _, y, _, h = box()
      if expanded() or not second() then return y + h / 2 end
      return vertical() and y + h + S.xs or y
    end,
    visible = any, behavior = { x = spring, y = spring, width = spring, height = spring } }
  local fill = ui.Item { id = "bar-live-fill", x = function() return (select(1, box())) end,
    y = function() return (select(2, box())) end, height = function() return (select(4, box())) end,
    width = function()
      local _, _, w = box()
      return w * (field("progress")() or 0)
    end,
    behavior = { x = spring, y = spring, height = spring, width = theme.spring.effects } }

  local radius = function() return kit.round(expanded() and S.xl or HIGH / 2) end
  local round = { radius = spring }
  local ground = ui.Sdf { id = "bar-live-ground", fill_color = function() return C.surfaceContainerHighest end,
    blend = S.m, shadow_color = "#00000060", shadow_blur = S.s, visible = any,
    x = function() return (select(1, ctx.origin())) end, y = function() return (select(2, ctx.origin())) end,
    width = function() return (select(3, ctx.origin())) end, height = function() return (select(4, ctx.origin())) end,
    ui.SdfShape { id = "bar-live-shape", shape = "box", track = main, radius = radius, behavior = round },
    ui.SdfShape { id = "bar-live-bubble-shape", shape = "box", track = bubble, operation = "smooth_union",
      radius = function() return kit.round(HIGH / 2) end,
      opacity = function() return (second() and not expanded()) and 1 or 0 end,
      behavior = { opacity = theme.spring.effects } } }
  local tint = ui.Sdf { id = "bar-live-tint", fill_color = function() return tone():alpha(0.28) end, visible = any,
    x = function() return (select(1, ctx.origin())) end, y = function() return (select(2, ctx.origin())) end,
    width = function() return (select(3, ctx.origin())) end, height = function() return (select(4, ctx.origin())) end,
    ui.SdfShape { shape = "box", track = main, radius = radius, behavior = round },
    ui.SdfShape { shape = "box", track = fill, operation = "intersect" } }

  -- The pill at rest. A second's beat in the mark while something records.
  local function beat()
    local now = current()
    if not (now and now.key == "recording") then return 1 end
    return (tonumber(morf.time.clock:get():sub(-1)) or 0) % 2 == 0 and 1 or 0.72
  end
  local function mark()
    return kit.icon(function() return field("icon")() or "" end, ICONS_H - S.xs, tone, { fill = true,
      scale = beat, behavior = { scale = theme.spring.fast } })
  end
  local function short(props)
    props.text = function() return field("short")() or "" end
    props.font_size, props.font_weight = theme.size.small, 600
    props.elide = "right"
    return kit.text(props)
  end
  local at_rest = ui.Item { id = "bar-live-rest", anchors = { fill = true },
    opacity = function() return expanded() and 0 or 1 end, behavior = { opacity = theme.spring.effects },
    visible = function() return not vertical() and cutout() == 0 end,
    ui.Row { anchors = { center_in = true }, gap = S.xs, align = "center", mark(),
      short { width = function() return math.max(0, rest_along() - ICONS_H - 3 * S.s) end } } }
  local beside = ui.Item { id = "bar-live-split", anchors = { fill = true },
    opacity = function() return expanded() and 0 or 1 end, behavior = { opacity = theme.spring.effects },
    visible = function() return not vertical() and cutout() > 0 end,
    ui.Item { anchors = { left = true, top = true, bottom = true }, width = function() return (rest_along() - cutout()) / 2 end,
      ui.Item { anchors = { center_in = true }, width = ICONS_H, height = ICONS_H, mark() } },
    ui.Item { anchors = { right = true, top = true, bottom = true }, width = function() return (rest_along() - cutout()) / 2 end,
      short { anchors = { center_in = true } } } }
  local upright = ui.Item { id = "bar-live-upright", anchors = { fill = true },
    opacity = function() return expanded() and 0 or 1 end, behavior = { opacity = theme.spring.effects },
    visible = vertical,
    ui.Item { anchors = { center_in = true }, width = ICONS_H, height = ICONS_H, mark() } }

  -- The panel: what it is, how far along, and its controls.
  local function control(index)
    local function row()
      local now = current()
      return now and now.controls()[index] or nil
    end
    local area
    area = kit.action { id = "bar-live-control-" .. index, cursor = "pointer", width = S.TARGET, height = S.TARGET,
      visible = function() return row() ~= nil end,
      accessible_name = function() return (row() or {}).name or "" end,
      on_clicked = function()
        local now = row()
        if now then now.press() end
      end,
      kit.icon(function() return (row() or {}).icon or "" end, S.xl, function()
        local now = row()
        return now and now.tone and kit.signal(now.tone)() or C.onSurface
      end, { anchors = { center_in = true }, fill = true }) }
    return kit.hover(area, function(hovered) return hovered and C.onSurface:alpha(0.1) or C.onSurface:alpha(0) end, S.TARGET / 2)
  end
  local function inner() return math.max(1, open_w() - 2 * S.l) end
  detail = ui.Column { x = S.l, y = S.m, gap = S.xs,
    ui.Row { gap = S.s, align = "center", mark(),
      ui.Column { gap = 0,
        kit.text { id = "bar-live-title", text = function() return field("title")() or "" end, font_weight = 600, elide = "right",
          width = function() return inner() - ICONS_H - S.s end },
        kit.text { id = "bar-live-subtitle", text = function() return field("subtitle")() or "" end, font_size = theme.size.small,
          color = kit.ink("lo"), elide = "right", width = function() return inner() - ICONS_H - S.s end } } },
    ui.Row { gap = S.xs, align = "center", control(1), control(2), control(3),
      ui.Item { width = S.TARGET, height = S.TARGET, visible = function() return second() ~= nil end,
        kit.action { id = "bar-live-next", anchors = { fill = true }, cursor = "pointer", accessible_name = "Next activity",
          on_clicked = live.cycle,
          kit.icon(function() return (second() or {}).icon or "" end, S.xl, function()
            local other = second()
            return other and kit.signal(other.tone)() or C.onSurface
          end, { anchors = { center_in = true } }) } } } }
  local panel = ui.Item { id = "bar-live-panel", anchors = { fill = true }, clip = true,
    opacity = function() return expanded() and 1 or 0 end, behavior = { opacity = theme.spring.effects },
    visible = expanded, detail }

  local press
  press = kit.action { id = "bar-live-press", anchors = { fill = true }, cursor = "pointer",
    accessible_name = function() return live.summary() end,
    on_clicked = live.toggle, on_long_pressed = live.cycle }
  ui.reparent(ui.MouseArea { id = "bar-live-right", anchors = { fill = true }, accepted_buttons = { "right" },
    on_pressed = live.cycle }, press)
  ctx.tip(press, live.summary, nil, function() return not expanded() end)
  local bubble_press = kit.action { id = "bar-live-bubble-press", anchors = { fill = true }, cursor = "pointer",
    accessible_name = "Next activity", visible = function() return second() ~= nil and not expanded() end,
    on_clicked = live.cycle,
    kit.icon(function() return (second() or {}).icon or "" end, ICONS_H - S.s, function()
      local other = second()
      return other and kit.signal(other.tone)() or C.onSurface
    end, { anchors = { center_in = true }, fill = true }) }

  ui.reparent(press, main)
  ui.reparent(at_rest, main)
  ui.reparent(beside, main)
  ui.reparent(upright, main)
  ui.reparent(panel, main)
  ui.reparent(bubble_press, bubble)

  require("themes.kit.popup").track(main, { open = expanded, on_close = live.collapse, close_policy = "escape+outside" })
  morf.effect("eva.bar.live.empty", function()
    if not any() and live.expanded:get() then live.collapse() end
  end)

  local node = ui.Item { id = "bar-live-layer", anchors = { fill = true }, z = 20,
    ground, tint, words, fill, main, bubble }

  local out = { node = node }
  --- What the zones place: room, and the pill stands over it.
  function out.part()
    return { node = ui.Item {}, size = total, island = true, clip = false,
      extra = function() return second() and (HIGH + S.xs) or 0 end }
  end
  function out.follow(axis, read) cells[axis] = read end
  return out
end

return V
