-- The on-screen displays: a few buds, each showing one kind where its setting
-- puts it. A `level` is the theme's meter with its reading (upright on the
-- side edges and in the centre, lying down along the top and bottom), a
-- `status` a short pill, `media` a pill with its cover.
--
-- At an edge a bud swells out of the frame, a layer of the frame's field with
-- its seam, its corners easing from round to the theme's own as it lands and
-- stretching along its run. In the centre it floats free in a field of its
-- own, with a shadow. A hidden bud is no layer of any field. A bud whose place
-- changes travels there, along its rail or across to another edge. Nothing
-- moves at rest.
--
-- Readings, hold and visibility are shell/levels.lua's; this is the face.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.parts")
local C = theme.color
local S = theme.space
local V = {}

V.BUDS = 3

local INSTANT = { duration = 0 }
local EXIT_MS, FADE_MS = 260, 180
local LEAVE = { duration = EXIT_MS, easing = theme.ease.emphasized_accel }
local FADE = { duration = FADE_MS }
-- The stretch along its run, where the theme stretches.
local STRETCH = kit.STRETCH and { stiffness = 360, damping = 30, scale = .1, max = .2 } or nil

-- How far a bud reaches under the frame.
local BLEED = S.s
local CORNERS = { top_left_radius = { "top", "left" }, top_right_radius = { "top", "right" },
  bottom_left_radius = { "bottom", "left" }, bottom_right_radius = { "bottom", "right" } }

function V.build(model)
  local TALL_W, TALL_H = 118, 322
  local avail = model.rail_geometry().w - theme.LEFT - theme.BORDER - 2 * S.m
  local WIDE_W, WIDE_H = math.min(340, avail), 76
  local PILL_W, PILL_H = math.min(264, avail), 64
  local MEDIA_W, MEDIA_H = math.min(368, avail), 96
  local INSET = theme.ROUNDING + theme.SEAM + S.m

  local function geometry()
    local r = model.rail_geometry()
    local top = math.floor((r.h - 2 * r.item - r.gap) / 2)
    return { w = r.w, h = r.h, item = r.item, pill_h = r.item, gap = r.gap, pill_x = r.w - theme.BORDER / 2 - 3,
      clear = 8, tops = { volume = top, brightness = top + r.item + r.gap } }
  end
  local function size_of(kind, horizontal)
    local family = model.family(kind)
    if family == "status" then return PILL_W, PILL_H end
    if family == "media" then return MEDIA_W, MEDIA_H end
    if horizontal then return WIDE_W, WIDE_H end
    return TALL_W, TALL_H
  end

  --- Where `kind` stands: `x`, `y`, `w`, `h` (the box, with what reaches under
  --- the frame), `tuck_x`, `tuck_y` (out of sight), `body_x`, `body_y`,
  --- `body_w`, `body_h` (the part on show), `edge` (nil in the centre).
  local function spot(kind)
    local g = geometry()
    local edge, along = model.anchor(model.position(kind))
    local horizontal = edge == "top" or edge == "bottom"
    local w, h = size_of(kind, horizontal)
    local left, right = theme.LEFT, g.w - theme.BORDER
    local top, bottom = theme.BORDER, g.h - theme.BORDER
    local box_w = w + ((edge == "left" or edge == "right") and BLEED or 0)
    local box_h = h + (horizontal and BLEED or 0)
    local x, y = math.floor((g.w - w) / 2), math.floor((g.h - h) / 2)
    if horizontal and along ~= 0 then x = along < 0 and left + INSET or right - INSET - w end
    if edge == "left" then x = left - BLEED end
    if edge == "right" then
      x = right - w
      if g.tops[kind] then y = g.tops[kind] + math.floor(g.item / 2 - h / 2) end
    end
    if edge == "top" then y = top - BLEED end
    if edge == "bottom" then y = bottom - h end
    if horizontal then x = math.max(left, math.min(right - w, x)) end
    if not horizontal then y = math.max(top + S.xs, math.min(bottom - h - S.xs, y)) end
    local tuck_x, tuck_y = x, y
    if edge == "left" then tuck_x = -(box_w + theme.SEAM + 2) end
    if edge == "right" then tuck_x = g.w + theme.BORDER + 2 end
    if edge == "top" then tuck_y = -(box_h + theme.SEAM + 2) end
    if edge == "bottom" then tuck_y = g.h + theme.BORDER + 2 end
    return { x = x, y = y, w = box_w, h = box_h, tuck_x = tuck_x, tuck_y = tuck_y, edge = edge,
      horizontal = horizontal, body_x = edge == "left" and BLEED or 0, body_y = edge == "top" and BLEED or 0,
      body_w = w, body_h = h }
  end

  -- ------------------------------------------------------------------ faces --

  local CAP = P.role_size("caption")
  local TITLE_H = P.lh(CAP)
  local LABEL_H = P.lh(P.role_size("label"))
  local CHIP_Y = S.xs + S.xxs + TITLE_H + S.xxs
  local CODE_Y = CHIP_Y + 13 + S.xxs
  local VALUE = P.role_size("hero")
  local VALUE_H = P.lh(VALUE)

  -- A level's reading: its digits and their sign or, turned off, its icon.
  local function reading(ctx, spec)
    local percent = function() return model.percent(ctx.kind()) end
    local SIGN = math.floor(VALUE * .5)
    local DIGIT = math.floor(VALUE * .62 + .5)
    return ui.Item { x = spec.x, y = spec.y, width = spec.width, height = VALUE_H,
      ui.Item { anchors = { fill = true }, visible = percent,
        kit.morph_number { id = spec.id, anchors = { center_in = true }, digits = 3, size = VALUE, color = ctx.ink,
          weight = 300, value = ctx.digits },
        kit.text { id = spec.id .. "-sign", text = "%", font_size = SIGN, font_weight = 300, color = ctx.ink,
          y = math.floor((VALUE_H - P.lh(SIGN)) / 2) + S.xxs, height = P.lh(SIGN),
          x = function() return math.floor(spec.width / 2 + #ctx.digits() * DIGIT / 2) + S.xxs end },
      },
      kit.icon(ctx.icon, VALUE, ctx.ink, { anchors = { center_in = true },
        visible = function() return not percent() end }),
    }
  end

  local function tall(ctx, tag)
    local W, H = TALL_W, TALL_H
    local COL_W = 26
    local COL_X = math.floor((W - COL_W) / 2)
    local COL_Y = CODE_Y + LABEL_H + S.xs
    local FOOT_Y = H - S.l - S.xs
    local VALUE_Y = FOOT_Y - S.xs - VALUE_H
    local COL_H = VALUE_Y - S.xs - S.xxs - COL_Y
    -- The meter fills from its floor (its origin) when the column arrives.
    local meter = ui.Item { x = COL_X, y = COL_Y, width = COL_W, height = COL_H, transform_origin_y = 1,
      kit.vmeter { id = "levels-meter" .. tag, width = COL_W, height = COL_H, value = ctx.value, color = ctx.ink,
        count = math.floor(COL_H / 7), motion = theme.spring.fast },
    }
    local node = ui.Item { width = W, height = H, visible = function() return ctx.face() == "tall" end,
      P.decor_box("corners", { length = S.s, color = ctx.ink }),
      kit.heading { id = "levels-title" .. tag, x = S.m, y = S.xs + S.xxs, width = W - 2 * S.m, height = TITLE_H,
        level = "caption", reveal_delay = 0, active = ctx.on("tall"), ink = ctx.ink, text = ctx.title },
      kit.chip { x = S.m, y = CHIP_Y, width = W - 2 * S.m, filled = true, color = ctx.ink, text = ctx.chip },
      kit.label { x = S.m, y = CODE_Y, width = W - 2 * S.m, elide = "right",
        text = function() return kit.code(ctx.kind(), "SD. ##.#") end },
      P.decor_box("scale", { x = COL_X - 32, y = COL_Y, height = COL_H, count = 20, major = 5,
        color = kit.stroke("idle") }),
      P.decor_box("scale", { x = COL_X + COL_W + 2, y = COL_Y, height = COL_H, count = 20, major = 5, flip = true,
        color = kit.stroke("idle") }),
      meter,
      reading(ctx, { id = "levels-value" .. tag, x = S.xs, y = VALUE_Y, width = W - 2 * S.xs }),
      P.rule { x = S.m, y = FOOT_Y, width = W - 2 * S.m },
      kit.label { x = S.m, y = FOOT_Y + S.xxs, width = W - 2 * S.m, elide = "right",
        text = function() return kit.code(ctx.kind() .. ".foot", "CH. ##") end },
    }
    return node, meter, "scale_y"
  end

  local function wide(ctx, tag)
    local W, H = WIDE_W, WIDE_H
    local BLOCK_W = 96
    local READ_W = 88
    local BAR_X = S.m + BLOCK_W + S.s
    local BAR_W = W - BAR_X - READ_W - S.s
    local BAR_H = 20
    local BLOCK_Y = math.floor((H - (TITLE_H + S.xxs + 13 + LABEL_H)) / 2)
    local meter = ui.Item { x = BAR_X, y = math.floor((H - BAR_H) / 2), width = BAR_W, height = BAR_H,
      transform_origin_x = 0,
      kit.meter { id = "levels-bar" .. tag, width = BAR_W, height = BAR_H, value = ctx.value, color = ctx.ink,
        count = math.floor(BAR_W / 7), motion = theme.spring.fast },
    }
    local node = ui.Item { width = W, height = H, visible = function() return ctx.face() == "wide" end,
      P.decor_box("corners", { length = S.s, color = ctx.ink }),
      kit.heading { id = "levels-row-title" .. tag, x = S.m, y = BLOCK_Y, width = BLOCK_W, height = TITLE_H,
        level = "caption", reveal_delay = 0, active = ctx.on("wide"), ink = ctx.ink, text = ctx.title },
      kit.chip { x = S.m, y = BLOCK_Y + TITLE_H + S.xxs, width = BLOCK_W, filled = true, color = ctx.ink, text = ctx.chip },
      kit.label { x = S.m, y = BLOCK_Y + TITLE_H + S.xxs + 13, width = BLOCK_W, elide = "right",
        text = function() return kit.code(ctx.kind(), "SD. ##.#") end },
      meter,
      reading(ctx, { id = "levels-row-value" .. tag, x = W - READ_W - S.xs, y = math.floor((H - VALUE_H) / 2),
        width = READ_W }),
    }
    return node, meter, "scale_x"
  end

  local function badge(ctx, x, size)
    return ui.Item { x = x, y = math.floor((PILL_H - size) / 2), width = size, height = size,
      kit.shape { anchors = { fill = true }, shape = "circle", color = function()
        return ctx.lit() and C.primaryContainer or C.surfaceContainerHighest end },
      kit.icon(function() return ctx.reading().icon end, math.floor(size * .58), function()
        return ctx.lit() and C.onPrimaryContainer or C.onSurfaceVariant end,
        { anchors = { center_in = true }, fill = true }) }
  end

  local function pill(ctx, tag)
    local W, H, SIZE = PILL_W, PILL_H, 40
    local TEXT_X = S.m + SIZE + S.m
    local TEXT_W = W - TEXT_X - S.m
    return ui.Item { width = W, height = H, visible = function() return ctx.face() == "pill" end,
      P.decor_box("corners", { length = S.xs + S.xxs, color = ctx.ink }),
      badge(ctx, S.m, SIZE),
      ui.Column { x = TEXT_X, anchors = { vertical_center = true }, gap = S.xxs,
        kit.heading { id = "levels-pill-title" .. tag, level = "section", width = TEXT_W, elide = "right",
          font_weight = 600, reveal_delay = 0, active = ctx.on("pill"), ink = ctx.ink,
          text = function() return ctx.reading().title end },
        kit.subtitle { id = "levels-pill-detail" .. tag, width = TEXT_W, elide = "right", font_size = theme.size.small,
          text = function() return ctx.reading().detail end,
          visible = function() return (ctx.reading().detail or "") ~= "" end },
      },
    }
  end

  local function cover(ctx, tag)
    local W, H, SIZE = MEDIA_W, MEDIA_H, MEDIA_H - 2 * S.m
    local TEXT_X = S.m + SIZE + S.m
    local TEXT_W = W - TEXT_X - S.l
    local art = function() return ctx.face() == "media" and model.artwork() or "" end
    local image = ui.Image { id = "levels-cover" .. tag, anchors = { fill = true }, fill_mode = "preserve_aspect_crop",
      source = art, visible = function() return art() ~= "" end }
    return ui.Item { width = W, height = H, visible = function() return ctx.face() == "media" end,
      P.decor_box("corners", { length = S.s, color = ctx.ink }),
      ui.Item { x = S.m, y = S.m, width = SIZE, height = SIZE,
        mask = ui.Sdf { anchors = { fill = true },
          ui.SdfShape { shape = "box", anchors = { fill = true }, radius = P.control_round(SIZE) } },
        ui.Rect { anchors = { fill = true }, color = function() return C.surfaceContainerHigh end },
        image,
        kit.icon("music_note", math.floor(SIZE * .42), kit.ink("lo"), { anchors = { center_in = true },
          visible = function() return art() == "" end }),
      },
      ui.Column { x = TEXT_X, anchors = { vertical_center = true }, gap = S.xxs,
        kit.heading { id = "levels-media-title" .. tag, level = "section", width = TEXT_W, elide = "right",
          font_weight = 600, reveal_delay = 0, active = ctx.on("media"), ink = ctx.ink,
          text = function() return ctx.reading().title end },
        kit.subtitle { id = "levels-media-artist" .. tag, width = TEXT_W, elide = "right", font_size = theme.size.small,
          text = function() return ctx.reading().detail end },
        kit.label { width = TEXT_W, elide = "right", text = function() return ctx.reading().note or "" end },
      },
    }
  end

  -- ------------------------------------------------------------------- buds --

  local still = ui.Item { id = "levels", anchors = { fill = true } }
  local riding = ui.Item { id = "levels-riding", anchors = { fill = true } }
  ui.reparent(riding, still)
  local shapes = { id = "levels-layers", anchors = { fill = true } }
  local panels = {}

  local function bud(i)
    local tag = i == 1 and "" or "-" .. i
    local name = "eva.levels.bud." .. i
    local kind_signal = morf.signal(name .. ".kind", "volume")
    local phase = morf.signal(name .. ".phase", "gone")
    local function kind() return kind_signal:get() end
    local function place() return spot(kind()) end
    local function is(wanted) return function() return phase:get() == wanted end end
    local gone, out, leaving = is("gone"), is("out"), is("leaving")
    local function floats() return place().edge == nil end
    local function level() return model.family(kind()) == "level" end

    local ctx = { kind = kind }
    function ctx.on(wanted) return function() return out() and ctx.face() == wanted end end
    function ctx.value() local read = model.value[kind()] return read and read() or 0 end
    local function muted() return kind() == "volume" and model.muted() end
    function ctx.reading() return model.read(kind()) end
    function ctx.lit() return ctx.reading().on ~= false end
    function ctx.ink()
      if level() then
        if muted() then return kit.signal("warn")() end
        return kind() == "brightness" and kit.signal("info")() or kit.signal("accent")()
      end
      return ctx.lit() and kit.signal("accent")() or kit.ink("lo")()
    end
    function ctx.title()
      if kind() == "brightness" then return "Brightness" end
      return muted() and "Muted" or "Volume"
    end
    function ctx.chip() return kind() == "brightness" and "Display" or "Output" end
    function ctx.icon() local read = model.icon[kind()] return read and read() or "tune" end
    function ctx.digits() return tostring(math.floor(ctx.value() * 100 + .5)) end
    function ctx.face()
      local family = model.family(kind())
      if family == "status" then return "pill" end
      if family == "media" then return "media" end
      return place().horizontal and "wide" or "tall"
    end

    local tall_face, tall_meter, tall_axis = tall(ctx, tag)
    local wide_face, wide_meter, wide_axis = wide(ctx, tag)

    -- A level answers the pointer: a drag along it sets it, a click mutes.
    local grab
    local function along() return place().horizontal and 1 or -1 end
    local area = kit.action {
      id = "levels-area" .. tag, anchors = { fill = true }, cursor = "pointer",
      visible = level, drag_axis = function() return place().horizontal and "x" or "y" end,
      accessible_name = function() return ctx.title() .. " " .. ctx.digits() .. " percent" end,
      on_pressed = function(sx, sy) grab = { x = sx, y = sy, value = ctx.value() } end,
      on_dragged = function(sx, sy)
        if not grab then return end
        local horizontal = place().horizontal
        local moved = (horizontal and sx - grab.x or sy - grab.y) * along()
        if not grab.moved and math.abs(moved) < S.xs then return end
        grab.moved = true
        local length = horizontal and WIDE_W or TALL_H
        model.adjust(kind(), grab.value + moved / length)
      end,
      on_clicked = function()
        local moved = grab and grab.moved
        grab = nil
        if not moved and kind() == "volume" then model.toggle_mute() end
      end,
    }

    local faces = { tall = tall_face, wide = wide_face, pill = pill(ctx, tag), media = cover(ctx, tag) }
    local body = ui.Item { id = "levels-bud" .. tag, clip = true,
      -- Under the faces, so a finger on a pill is on the bud.
      ui.MouseArea { anchors = { fill = true }, z = -1 },
      faces.tall, faces.wide, faces.pill, faces.media, area }
    local panel = ui.Item { id = "levels-swell" .. tag, visible = function() return not gone() end,
      stretch = STRETCH, body }

    -- A bud on show that takes another face fades it in.
    local face_now = ctx.face()
    morf.effect(name .. ".face", function()
      local now = ctx.face()
      if now == face_now then return end
      face_now = now
      if not out() then return end
      local curve = theme.bounce.effects
      morf.animation.play { { node = faces[now], property = "opacity", from = 0, to = 1,
        duration = curve.duration, easing = curve.easing } }
    end)

    local function x() return place().x end
    local function y() return place().y end
    local function tuck_x() return place().tuck_x end
    local function tuck_y() return place().tuck_y end
    local function w() return place().w end
    local function h() return place().h end
    ui.claims(panel, {
      a_gone = { when = gone, motion = INSTANT, set = { x = tuck_x, y = tuck_y, width = w, height = h, opacity = 0,
        scale = function() return floats() and .92 or 1 end } },
      b_out = { when = out, motion = theme.spring.drawer, set = { x = x, y = y, width = w, height = h, scale = 1 } },
      c_shown = { when = out, motion = theme.spring.effects, set = { opacity = 1 } },
      d_leaving = { when = leaving, motion = LEAVE, set = { x = tuck_x, y = tuck_y, width = w, height = h,
        scale = function() return floats() and .96 or 1 end } },
      e_fading = { when = leaving, motion = FADE, set = { opacity = 0 } },
    })
    -- Swiped toward the edge it swells from, or any way where it floats, it
    -- goes. A meter keeps the drag along it; a pill has none.
    local swipe = require("swipe_dismiss").new { id = "levels." .. i, node = panel, axes = { x = true, y = true },
      ways = function()
        local edge = place().edge
        if not edge then return { left = true, right = true, up = true, down = true } end
        local ways = { [({ left = "left", right = "right", top = "up", bottom = "down" })[edge]] = true }
        if not level() and (edge == "top" or edge == "bottom") then ways.left, ways.right = true, true end
        if not level() and (edge == "left" or edge == "right") then ways.up, ways.down = true, true end
        return ways
      end,
      on_dismiss = function() model.dismiss(i) end,
    }
    panel.on_panned = swipe.on_panned
    morf.effect(name .. ".swipe", function() if gone() then morf.time.timer(1, swipe.reset, false) end end, { owner = panel })
    local function body_x() return place().body_x end
    local function body_y() return place().body_y end
    local function body_w() return place().body_w end
    local function body_h() return place().body_h end
    ui.claims(body, {
      a_gone = { when = gone, motion = INSTANT, set = { x = body_x, y = body_y, width = body_w, height = body_h } },
      b_moving = { when = function() return not gone() end, motion = theme.spring.drawer,
        set = { x = body_x, y = body_y, width = body_w, height = body_h } },
    })

    -- Round as it swells; at rest the theme's corners, square where it joins
    -- the frame, whose seam rounds that side.
    local function round() local p = place() return math.min(p.w, p.h) / 4 end
    local function corner(sides)
      return function()
        local p = place()
        if p.edge == sides[1] or p.edge == sides[2] then return 0 end
        return math.min(theme.ROUNDING, math.min(p.w, p.h) / 2)
      end
    end
    local function ground(shape, on_show)
      local start, rest = {}, {}
      for property, sides in pairs(CORNERS) do start[property], rest[property] = round, corner(sides) end
      start.opacity = 0
      ui.claims(shape, {
        a_gone = { when = gone, motion = INSTANT, set = start },
        b_shown = { when = function() return not gone() end, motion = theme.spring.spatial, set = rest },
        c_fade = { when = out, motion = theme.spring.effects, set = { opacity = on_show } },
        d_fading = { when = leaving, motion = FADE, set = { opacity = 0 } },
      })
    end

    -- At an edge: a layer of the frame's field, with its seam.
    local shape = ui.SdfShape { id = "levels-swell" .. tag .. "-background", shape = "box",
      operation = "smooth_union", blend_group = 1000 + i, track = panel }
    ground(shape, function() return floats() and 0 or 1 end)
    if theme.SEAM > 0 then
      ui.claims(shape, {
        a_gone = { when = gone, motion = INSTANT, set = { blend = theme.SEAM * 1.6 } },
        b_landed = { when = function() return not gone() end, motion = theme.spring.drawer, set = { blend = theme.SEAM } },
      })
    end
    shapes[#shapes + 1] = shape

    -- In the centre: a field of its own, for its shadow.
    local float = ui.SdfShape { id = "levels-float" .. tag .. "-shape", shape = "box", track = panel }
    ground(float, function() return floats() and 1 or 0 end)
    local field = ui.Sdf { id = "levels-float" .. tag, anchors = { fill = true },
      visible = function() return not gone() end,
      fill_color = function() return require("themes.glass").fill(C.surface, 1.1) end,
      shadow_color = function() return C.shadow:alpha(.42) end, shadow_blur = S.xl, shadow_offset_y = S.s,
      float }
    panels[#panels + 1] = panel

    -- On the right it rides out with the sidebar; elsewhere it stays.
    local holder = ui.Item { anchors = { fill = true }, field, panel }
    local on_right
    morf.effect(name .. ".side", function()
      local edge, end_of = model.anchor(model.position(kind()))
      local right = edge == "right" or end_of > 0
      if right == on_right then return end
      on_right = right
      ui.reparent(holder, right and riding or still)
    end)

    local going, starting, filling
    local function arrive()
      if filling then filling:stop() end
      local node, axis = tall_meter, tall_axis
      if ctx.face() == "wide" then node, axis = wide_meter, wide_axis end
      local curve = theme.bounce.spatial
      filling = morf.animation.play { { node = node, property = axis, from = 0, to = 1,
        duration = curve.duration, easing = curve.easing, delay = 80 } }
    end

    local B = { held = function() return area.hovered or area.pressed end }
    function B.showing(wanted) return kind() == wanted and not gone() end
    function B.show(wanted)
      if going then going:cancel() going = nil end
      kind_signal:set(wanted)
      if phase:get() ~= "gone" then phase:set("out") return end
      -- A turn apart: what is tucked away goes to this kind's edge first.
      if starting then starting:cancel() end
      starting = morf.time.timer(1, function()
        starting = nil
        phase:set("out")
        if level() then arrive() end
      end, false)
    end
    function B.hide(done)
      if starting then starting:cancel() starting = nil end
      phase:set("leaving")
      going = morf.time.timer(EXIT_MS, function()
        going = nil
        phase:set("gone")
        done()
      end, false)
    end
    return B
  end

  local buds = {}
  for i = 1, V.BUDS do buds[i] = bud(i) end
  local shape = ui.Item(shapes)

  -- The resting marks in the band of the right edge, for the levels that
  -- swell from it.
  for _, name in ipairs { "volume", "brightness" } do
    local function bright()
      for _, one in ipairs(buds) do if one.showing(name) then return true end end
      return false
    end
    local function ink()
      if name == "volume" and model.muted() then return kit.signal("warn")() end
      return name == "brightness" and kit.signal("info")() or kit.signal("accent")()
    end
    ui.reparent(kit.surface { id = "levels-" .. name, x = function() return geometry().pill_x end,
      y = function() return geometry().tops[name] end, width = 6, height = function() return geometry().pill_h end,
      radius = P.control_round(6),
      visible = function() return not model.portrait and model.position(name) == "center_right" end,
      color = function() return bright() and ink() or kit.stroke("idle")() end,
      opacity = function() return bright() and 1 or .6 end,
      behavior = { color = { duration = 180 }, opacity = { duration = 180 } },
    }, riding)
  end
  kit.ride("levels", riding, model.sidebar.drawer,
    function() return -(theme.SIDE_W + theme.STRIP / 2 + theme.BORDER / 2) end)

  local function overlap(a, b)
    local p, q = spot(a), spot(b)
    return p.x < q.x + q.w and q.x < p.x + p.w and p.y < q.y + q.h and q.y < p.y + p.h
  end
  return { node = still, shape = shape, buds = buds, geometry = geometry, spot = spot, overlap = overlap, panels = panels }
end
return V
