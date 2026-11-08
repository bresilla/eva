-- Simple workspace markers matching the right-edge level pills.
-- The active marker slides between slots; a switch reveals the HUD card.
-- Geometry keeps the level pills on the right edge aligned. Upright (a
-- phone, `model.bottom`) the markers run along the bottom edge and the card
-- rises out of it.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local stripes = require("themes.tsugumori.stripes")
local unicase = require("lib.util.unicase")
local C = theme.color
-- The few drawing helpers the rail uses.
local P = {}
local STRENGTH = { faint = .13, quiet = .24, idle = .4, mark = .72, hot = 1 }
function P.line(strength) local a = STRENGTH[strength] return function() return C.primary:alpha(a) end end
function P.signal() return function() return C.primary end end
function P.ink(kind)
  if kind == "lo" then return function() return C.onSurfaceVariant end end
  return function() return C.primary end
end
function P.label(props)
  local text = props.text
  props.text = function() local t = type(text) == "function" and text() or text return unicase.upper(tostring(t or "")) end
  props.font_family = props.font_family or theme.font
  props.color = props.color or P.ink("lo")
  return ui.Text(props)
end
function P.brackets(spec)
  local w, h, l = spec.width, spec.height, spec.length or 8
  local d = ("M0 %g V0 H%g M%g 0 H%g V%g M%g %g V%g H%g M%g %g H0 V%g"):format(
    l, l, w - l, w, l, w, h - l, h, w - l, l, h, h - l)
  return ui.Path { width = w, height = h, view_box = { 0, 0, w, h }, d = d, fill_color = "transparent",
    stroke_color = spec.color, stroke_width = 1, stroke_cap = "square" }
end
function P.hatch(spec)
  return stripes.box { x = spec.x, y = spec.y, width = spec.width, height = spec.height,
    gap = spec.spacing or 6, weight = spec.weight or 1.5, color = spec.color }
end
local V = {}

function V.geometry(model)
  local w, h = model.desk_size()
  local item, gap = 14, 10
  local track = model.count * item + (model.count - 1) * gap
  -- `top`: where the markers start along their edge (down the left one, or
  -- across the bottom one from the desk's left).
  local along = model.bottom and w or h
  local from = model.bottom and model.start() or 0
  return { w = w, h = h, item = item, gap = gap, top = from + math.floor((along - track) / 2),
    pill_x = theme.LEFT / 2 - 3, bud_x = theme.LEFT + 8 }
end

function V.build(model)
  local W, H = 176, 92
  local function geometry() return V.geometry(model) end
  local function center(id)
    local g = geometry()
    return g.top + (id - model.base(id)) * (g.item + g.gap) + g.item / 2
  end
  local shown = morf.signal("tsugumori.rail.shown", false)
  local root = ui.Item { id = "rail", accessible_role = "navigation", accessible_name = "Workspaces",
    anchors = { fill = true }, visible = model.enabled }

  -- Slots.
  -- A marker: across its edge 6 wide, along it `item` long, at `centre`.
  local B = model.bottom
  local function marker(props, centre)
    if B then
      props.y = function() return model.edge() - theme.BORDER / 2 - 3 end
      props.height = 6
      props.width = function() return geometry().item end
      props.x = function() return centre() - geometry().item / 2 end
    else
      props.x = function() return geometry().pill_x end
      props.width = 6
      props.height = function() return geometry().item end
      props.y = function() return centre() - geometry().item / 2 end
    end
    return ui.Rect(props)
  end
  for i = 1, model.count do
    local function id() return model.base(model.active()) + i - 1 end
    ui.reparent(marker({ id = "rail-pill-" .. i,
      color = function() return C.primary end,
      opacity = function()
        if model.hovered and model.hovered(i) then return 1 end
        return model.occupied(id()) and .65 or .28
      end,
      behavior = { opacity = { duration = 180 } } }, function() return center(id()) end), root)
  end

  -- The active marker has the same shape as every workspace slot and slides
  -- hard; a thin tick follows it on a longer tween and lands under it.
  local hard = { duration = theme.duration.normal, easing = theme.ease.emphasized }
  local late = { duration = theme.duration.large, easing = theme.ease.emphasized }
  ui.reparent(marker({ id = "rail-tick", opacity = .45,
    color = function() return C.primary end,
    behavior = { x = late, y = late } }, function() return center(model.active()) end), root)
  ui.reparent(marker({ id = "rail-selector",
    color = function() return C.primary end,
    behavior = { x = hard, y = hard } },
    function() return center(model.active()) end), root)

  -- A switch sends a bright segment along the opening's lip from the old
  -- slot to the new, its head leading a glowing tail, and it fades there.
  local SEG = 44
  local along = B and "x" or "y"
  local function streak(alpha, inset, thick)
    local props = { gradient = function()
      return { angle = B and 90 or 180, stops = { C.primary:alpha(0), C.primary:alpha(alpha) } } end }
    if B then props.y, props.height, props.width = inset, thick, SEG
    else props.x, props.width, props.height = inset, thick, SEG end
    return ui.Rect(props)
  end
  local trace = ui.Item { id = "rail-trace", opacity = 0, visible = false,
    streak(.4, 0, 8), streak(1, B and 3 or 2, 3) }
  if B then
    trace.y, trace.height, trace.width = function() return model.edge() - theme.BORDER - 3 end, 8, SEG
  else
    trace.x, trace.width, trace.height = theme.LEFT - 5, 8, SEG
  end
  ui.reparent(trace, root)
  local tracing
  local function untrace()
    if tracing then tracing:stop() tracing = nil end
    trace.visible, trace.opacity = false, 0
  end
  local function trace_to(from, to)
    untrace()
    if from == to then return end
    local a, b = center(from), center(to)
    local ahead = b > a
    -- Flipped about its middle on the way back: the head leads.
    trace[B and "scale_x" or "scale_y"] = ahead and 1 or -1
    local function lead(at) return ahead and at - SEG or at end
    trace[along], trace.visible = lead(a), true
    tracing = morf.animation.play { { parallel = {
      { node = trace, property = along, from = lead(a), to = lead(b), duration = 320, easing = "out_cubic" },
      { node = trace, property = "opacity", duration = 560, keyframes = {
        { at = 0, value = 0 }, { at = .08, value = 1 }, { at = .55, value = 1 }, { at = .64, value = .45 },
        { at = .72, value = 1 }, { at = 1, value = 0 } } },
    } }, on_finished = function(reason)
      if reason == "completed" then tracing = nil trace.visible = false end
    end }
  end

  -- -------------------------------------------------------------- card --
  local digits = kit.text { id = "rail-value", x = 12, y = 26, height = 36, font_size = 32,
    font_family = theme.font, font_weight = 300, morph = true,
    text = function() return ("%02d"):format(model.active()) end, color = function() return C.primary end }
  local meter = ui.Item { id = "rail-meter", x = 12, y = H - 22, width = W - 24, height = 6 }
  local CELL_GAP = 2
  local cell_w = (W - 24 - CELL_GAP * (model.count - 1)) / model.count
  for i = 1, model.count do
    local function id() return model.base(model.active()) + i - 1 end
    ui.reparent(ui.Rect { x = (i - 1) * (cell_w + CELL_GAP), width = cell_w, height = 6,
      color = function()
        if id() == model.active() then return C.primary end
        return model.occupied(id()) and C.primary:alpha(.4) or C.primary:alpha(.08)
      end }, meter)
  end
  -- Where the card hides, past its edge, and where it stands out of it.
  local function hidden() return B and model.edge() + 12 or -W - 12 end
  local function out() return B and model.edge() - theme.BORDER - 8 - H or geometry().bud_x end
  local slide = B and "y" or "x"
  local card = ui.Item { id = "rail-swell", width = W, height = H, visible = false, opacity = 0,
    -- It follows the active marker along its edge.
    behavior = B and { x = { duration = 380, easing = "out_cubic" } } or { y = { duration = 380, easing = "out_cubic" } },
    stretch = kit.STRETCH,
    ui.Rect { width = W, height = H, color = "transparent", border_width = 1, border_color = P.line("quiet") },
    P.brackets { width = W, height = H, length = 8, color = P.line("hot") },
    -- Header strip: code block, status chip, a stud.
    ui.Rect { x = 8, y = 8, width = 98, height = 11, color = function() return C.primary end },
    kit.heading { id = "rail-title", text = "Workspace", level = "caption", x = 12, y = 6, width = 92,
      font_size = 10, ink = function() return C.surface end,
      active = function() return shown:get() end, reveal_delay = 0, decode_lead = 160, decode_stagger = 20 },
    ui.Rect { x = 112, y = 8, width = 44, height = 11, color = "transparent", border_width = 1,
      border_color = P.signal("accent") },
    P.label { x = 112, y = 6, width = 44, height = 14, font_size = 10, horizontal_alignment = "center",
      color = P.ink("accent"),
      text = function() return model.occupied(model.active()) and "ACTIVE" or "EMPTY" end },
    ui.Rect { x = W - 15, y = 9, width = 7, height = 7, color = P.line("mark") },
    ui.Rect { x = 8, y = 23, width = W - 16, height = 1, color = P.line("quiet") },
    digits,
    P.label { x = 64, y = 32, text = function() return ("/%02d"):format(model.base(model.active()) + model.count - 1) end,
      font_size = 10, color = P.ink("lo") },
    P.label { x = 104, y = 32, width = W - 112, font_size = 10, color = P.ink("accent"), elide = "right",
      text = function()
        local n = 0
        local b = model.base(model.active())
        for i = b, b + model.count - 1 do if model.occupied(i) then n = n + 1 end end
        return ("OCC %02d/%02d"):format(n, model.count)
      end },
    P.hatch { x = 104, y = 52, width = W - 116, height = 8, spacing = 5, weight = 1.5, color = P.line("mark") },
    meter,
  }
  -- Along its edge it follows the active marker, kept on the screen.
  local function beside()
    local g = geometry()
    local span, size = B and g.w or g.h, B and W or H
    local from = B and model.start() or 0
    return math.max(from + 12, math.min(from + span - size - 12, center(model.active()) - size / 2))
  end
  if B then card.x, card.y = beside, hidden() else card.x, card.y = hidden(), beside end
  local shape = ui.SdfShape { id = "rail-swell-background", shape = "box", radius = 0,
    operation = "smooth_union", blend = 6, track = card, opacity = 0 }
  ui.reparent(card, root)
  -- The left panel opening carries a left-edge rail out with it.
  if not B then
    kit.ride("rail", root, model.leftbar.drawer,
      function() return theme.SIDE_W + theme.STRIP / 2 + theme.LEFT / 2 end)
  end

  local motion, hide
  -- The card boots as it stands out: its outline traces in, a scan crosses it.
  local boot = require("themes.tsugumori.boot")(theme).new(card, "rail-card",
    { brackets = false, register = false, z = 10 })
  local function cancel()
    if hide then hide:cancel() hide = nil end
    if motion then motion:stop() motion = nil end
  end
  local function close(immediate)
    cancel() shown:set(false) boot.stop(not immediate)
    if immediate then
      card.visible, card.opacity, shape.opacity = false, 0, 0
      card[slide] = hidden()
      return
    end
    motion = morf.animation.play { { parallel = {
      { node = card, property = slide, to = hidden(), duration = 260, easing = "in_out_quint" },
      { node = card, property = "opacity", to = 0, duration = 180 },
      { node = shape, property = "opacity", to = 0, duration = 180 },
    } }, on_finished = function(reason) if reason == "completed" then card.visible = false end end }
  end
  local function pop()
    local fresh = not card.visible
    cancel() shown:set(true) card.visible = true
    if fresh then boot.play(80) end
    motion = morf.animation.play { { parallel = {
      { node = card, property = slide, to = out(), duration = 340, easing = "out_expo" },
      { node = card, property = "opacity", to = 1, duration = 180 },
      { node = shape, property = "opacity", to = 1, duration = 180 },
      { node = digits, property = "translate_y", from = -8, to = 0, duration = 280, easing = "out_cubic" },
      { node = digits, property = "opacity", from = 0, to = 1, duration = 180 },
    } } }
    hide = morf.time.timer(model.hold(), function() hide = nil close(false) end, false)
  end

  local last = model.active()
  morf.effect("tsugumori.rail.follow", function()
    local id, on = model.active(), model.enabled()
    local changed, before = id ~= last, last
    last = id
    if not on then close(true) untrace()
    elseif changed then
      pop()
      if not require("themes.session").restoring then trace_to(before, id) end
    end
  end, { owner = root })
  return { node = root, shape = shape }
end
return V
