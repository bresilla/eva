-- Notification popups: each one a status card.
--
-- The theme's header strip (the source and the card's word), a micro row
-- (the urgency where it is not the usual one, the age at the right), the card's
-- picture with the summary large and the theme's trailing emphasis running from
-- the word to the expand control, the body beneath, and a footer rule with the
-- card's verdict. Urgency and wording pick the card (themes/notification_text.lua:
-- alert, warn, ok, info). What a notification carries stacks between the body
-- and the footer: a picture, a `value` hint's progress fill with a counter,
-- media controls, code and link chips, the sender's buttons, a reply field and
-- the card's tools (themes/layouts/notification_parts.lua).
--
-- The cards are layers of one field: a new one slides in from the edge,
-- grows from a line and its seams melt into the stack, then settle crisp.
-- With the sidebar open beside them a stack on the right moves out of its way.
--
-- The stack stands at any top or bottom anchor (M.position), the newest card
-- nearest its edge. A card goes sideways, or away from that edge, when swiped.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local N = require("themes.layouts.notification_parts")
local text_of = require("themes.notification_text")
local C = theme.color
local V = {}

V.kind, V.progress = text_of.kind, text_of.progress

function V.build(M)
  local WIDTH, CARD_W, GAP = 430, 408, 8
  local TOP, BOTTOM, MAX = 6, 16, 5
  local TEXT_X, EMBLEM = 66, 40
  local plain, progress_of, kind_of = text_of.plain, text_of.progress, text_of.kind
  local function shown() return M.shown(math.min(MAX, M.max_popups())) end
  local is_open = M.expanded

  -- Which edge it hangs from is settled as it is built; where along it is not.
  local at_bottom = M.position():match("^bottom") ~= nil
  local STACK_Y = at_bottom and BOTTOM or TOP
  local AWAY = at_bottom and "up" or "down"
  local function along()
    local column = M.position():match("_(%a+)$")
    return column == "left" and -1 or column == "right" and 1 or 0
  end
  -- Where a new card comes from, and where one goes when nothing says.
  local function outward()
    local side = along()
    if side ~= 0 then return side * 64, 0 end
    return 0, at_bottom and 64 or -64
  end

  local LABEL_H = L.lh(L.role_size("label"))
  local SUM = math.floor(L.role_size("title") * 1.2)
  local SUM_H = L.heading_h(SUM)
  local BODY = theme.size.small
  local BODY_H = L.lh(BODY)
  local HEAD_Y, MICRO_Y = 8, 36
  local SUM_Y = MICRO_Y + math.max(13, LABEL_H) + 4
  local BODY_Y = SUM_Y + SUM_H + 2
  local FOOT_H = 4 + LABEL_H
  local BASE_H = BODY_Y + BODY_H + 6 + FOOT_H + 4
  local OPEN_EXTRA, PROGRESS_H = 3 * BODY_H, 36
  local EXPAND = 26
  local SUM_W = CARD_W - TEXT_X - EXPAND - 16 - 40 - EXPAND
  local PART_W = CARD_W - TEXT_X - 14
  local PARTS_Y = BODY_Y + BODY_H + 4

  local function expanded(n) return n ~= nil and is_open(n.id) and (n.body or "") ~= "" end
  local function masked(n) return n ~= nil and M.redacted(n) and not is_open(n.id) end
  local function replying(n) return n ~= nil and M.replying:get() == n.id end
  local function tooled(n) return n ~= nil and M.tools:get() == n.id end
  local function previewing(n)
    return n ~= nil and not masked(n) and is_open(n.id) and text_of.image_of(n) ~= ""
  end
  local function has_transport(n) return n ~= nil and not masked(n) and #text_of.transport(n) > 0 end
  local function has_chips(n) return n ~= nil and not masked(n) and #N.chips_of(n, M) > 0 end
  -- What a card stacks under its body, in order, with how tall each stands.
  local STACK = {
    { "open", function(n) return expanded(n) and OPEN_EXTRA or 0 end },
    { "preview", function(n) return previewing(n) and N.PREVIEW_H or 0 end },
    { "progress", function(n) return progress_of(n) and PROGRESS_H or 0 end },
    { "transport", function(n) return has_transport(n) and N.ROW_H or 0 end },
    { "chips", function(n) return has_chips(n) and N.ROW_H or 0 end },
    { "buttons", function(n) return masked(n) and 0 or N.button_rows(n, M) * N.ROW_H end },
    { "reply", function(n) return replying(n) and N.ROW_H or 0 end },
    { "tools", function(n) return tooled(n) and N.ROW_H or 0 end },
  }
  local function below(n, part)
    local y = PARTS_Y
    for _, row in ipairs(STACK) do
      if row[1] == part then return y end
      y = y + row[2](n)
    end
    return y
  end
  local function card_height(n)
    local h = BASE_H
    for _, row in ipairs(STACK) do h = h + row[2](n) end
    return h
  end
  local function total()
    local list = shown()
    if #list == 0 then return BASE_H end
    local h = (#list - 1) * GAP
    for _, n in ipairs(list) do h = h + card_height(n) end
    return h
  end
  -- The stack takes what it needs up to the desk's height, and scrolls
  -- past that.
  local function room()
    local _, _, _, h = require("bar").desk()
    return math.max(BASE_H, h - 2 * theme.BORDER - 24 - TOP - BOTTOM)
  end
  local function height() return math.min(total(), room()) + TOP + BOTTOM end

  local dripping = morf.signal("eva.notifications.dripping", false)
  local cards, slots, shapes, parts = {}, {}, {}, {}
  local layers = {
    id = "notifications-field", anchors = { fill = true },
    blend = function() return theme.motion.liquid_cards ~= false and dripping:get() and 14 or 0 end,
    behavior = { blend = { duration = 260 } },
  }
  local dry

  for i = 1, MAX do
    local function n() return shown()[i] end
    local function kind() return kind_of(n()) end
    local function signal() return kit.signal(kind())() end
    local function code(shape) local x = n() return x and kit.code(x.id, shape) or "" end
    local function source() local x = n() return x and (x.app ~= "" and x.app or "Notification") or "" end
    local URGENCY = { [0] = "Low", [1] = "Normal", [2] = "Critical" }
    local motion = { duration = theme.duration.normal, easing = theme.ease.emphasized_decel }
    local card

    local emblem = N.avatar { id = "notification-emblem-" .. i, x = 14, y = SUM_Y + math.floor((SUM_H - EMBLEM) / 2),
      size = EMBLEM, kind = kind, n = n, hidden = function() return masked(n()) end }

    -- The micro row: the urgency when it is not the usual one, how many more
    -- this card folds, and the age at the right (the source and the card's
    -- word are the header's).
    local function urgency() local x = n() return x and x.urgency or 1 end
    local function more() local x = n() return x and x.more or 0 end
    local fold = kit.action { id = "notification-fold-" .. i, width = 40, height = math.max(13, LABEL_H), cursor = "pointer",
      accessible_name = "Show the others", visible = function() return more() > 0 end,
      on_clicked = function() local x = n() if x then M.unfold(x.key) end end,
      kit.chip { anchors = { vertical_center = true }, text = function() return "+" .. more() end, color = signal, width = 34 } }
    local micro = ui.Row { x = TEXT_X, y = MICRO_Y, height = math.max(13, LABEL_H), gap = 4, align = "center",
      ui.Item { width = 58, height = 13, visible = function() return urgency() ~= 1 end,
        kit.chip { text = function() local u = urgency() return L.term("notice.urgency." .. u, URGENCY[u] or "Normal") end,
          color = signal, filled = true, width = 58 } },
      fold,
    }
    local age = kit.label { anchors = { right = true, right_margin = 12 }, y = MICRO_Y, width = 120, color = signal,
      horizontal_alignment = "right", elide = "left",
      text = function()
        local x = n()
        return x and text_of.ago(x.time or morf.time.now()) or ""
      end }

    -- The word: the summary large in its box; the trailing emphasis runs
    -- from where the word ends (measured in the theme's face) to the
    -- expand control.
    local summary_text = function()
      local x = n()
      if not x then return "" end
      return masked(x) and "New notification" or plain(x.summary)
    end
    local summary = kit.heading {
      id = "notification-summary-" .. i, x = TEXT_X, y = SUM_Y, width = SUM_W, height = SUM_H, elide = "right",
      level = "title", font_size = SUM, font_weight = 400, text = summary_text, reveal_delay = 240,
      active = function() return M.opened:get() and n() ~= nil end,
      ink = function() return kit.ink("hi")() end,
    }
    local measure = kit.text { text = function() return summary_text():upper() end, font_size = SUM,
      height = 1, opacity = 0 }
    local function trail_x()
      local w = math.ceil((measure.layout_width or SUM_W) * 1.1) + 18
      return TEXT_X + math.min(SUM_W, w)
    end
    local trail_end = CARD_W - 12 - 2 * EXPAND - 12
    local stripes = ui.Item { x = trail_x, y = SUM_Y + math.floor(SUM_H * .3), height = math.floor(SUM_H * .4),
      width = function() return math.max(0, trail_end - trail_x()) end, clip = true,
      L.decor_box("hatch", { width = trail_end - TEXT_X, height = math.floor(SUM_H * .4), spacing = 9, weight = 4,
        color = signal }),
    }
    parts[i] = { emblem = emblem, stripes = stripes }

    local body_color = function()
      return kind() == "alert" and kit.ink("hi")():mix(kit.signal("alert")(), .25) or kit.ink("lo")()
    end
    local function raw(x) return masked(x) and "Open to read" or x.body end
    local body_line = N.body {
      id = "notification-body-" .. i, n = n, raw = raw, x = TEXT_X, y = BODY_Y, width = CARD_W - TEXT_X - 16, height = BODY_H,
      font_size = BODY, elide = "right", color = body_color,
      visible = function() return not expanded(n()) end,
    }
    local body_open = N.body {
      id = "notification-body-open-" .. i, n = n, raw = raw, x = TEXT_X, y = BODY_Y, width = CARD_W - TEXT_X - 16,
      font_size = BODY, wrap = true, max_lines = 4, color = body_color,
      visible = function() return expanded(n()) end,
    }

    -- What it carries, each standing under the one before.
    local function at(part) return function() return below(n(), part) end end
    local preview = N.preview { id = "notification-preview-" .. i, x = TEXT_X, y = at("preview"), width = PART_W, n = n,
      shown = function() return previewing(n()) end }
    local transport = N.transport { id = "notification-media-" .. i, x = TEXT_X, y = at("transport"), n = n, model = M,
      shown = function() return has_transport(n()) end }
    local chips = N.chips { id = "notification-chip-" .. i, x = TEXT_X, y = at("chips"), width = PART_W, n = n, model = M,
      shown = function() return has_chips(n()) end }
    local buttons = N.buttons { id = "notification-action-" .. i, x = TEXT_X, y = at("buttons"), width = PART_W, n = n,
      model = M, shown = function() return not masked(n()) and N.button_rows(n(), M) > 0 end }
    local reply = N.reply { id = "notification-reply-" .. i, x = TEXT_X, y = at("reply"), width = PART_W, n = n, model = M,
      shown = function() return replying(n()) end }
    local tools = N.tools { id = "notification-tool-" .. i, x = TEXT_X, y = at("tools"), width = PART_W, n = n, model = M,
      shown = function() return tooled(n()) end }

    -- Progress, when the sender reports one: the theme's fill and a counter.
    local COUNT = L.role_size("hero") * .7
    local progress = ui.Item {
      x = TEXT_X, width = CARD_W - TEXT_X - 14, height = PROGRESS_H - 4,
      y = at("progress"),
      visible = function() return progress_of(n()) ~= nil end,
      kit.fill { y = 4, width = CARD_W - TEXT_X - 74, height = 12, color = signal,
        value = function() return progress_of(n()) or 0 end },
      kit.text { anchors = { right = true }, y = 0, width = 52, height = L.lh(COUNT), horizontal_alignment = "right",
        text = function() return ("%d%%"):format(math.min(100, math.floor((progress_of(n()) or 0) * 100 + .5))) end,
        font_size = COUNT, font_weight = 300, color = signal },
      kit.label { y = 18, width = CARD_W - TEXT_X - 74, elide = "right",
        text = function() return text_of.progress_line(n()) end },
    }

    -- The footer rule: the verdict and the theme's code for the card.
    local footer = ui.Item { anchors = { left = true, right = true, bottom = true, left_margin = 8,
      right_margin = 12, bottom_margin = 4 }, height = FOOT_H,
      L.rule { y = 1, width = CARD_W - 22 },
      kit.label { y = 4, width = 250, elide = "right", color = signal, text = function() return text_of.verdict(kind()) end },
      kit.label { anchors = { right = true }, y = 4, width = 100, horizontal_alignment = "right",
        text = function() return code("PT - ###") end },
    }

    local expand_area
    expand_area = kit.action {
      id = "notification-expand-" .. i, anchors = { right = true, right_margin = 12 },
      y = SUM_Y + math.floor((SUM_H - EXPAND) / 2), width = EXPAND, height = EXPAND, cursor = "pointer",
      on_clicked = function() local x = n() if x then M.toggle(x.id) end end,
      kit.icon(function() local x = n() return (x and is_open(x.id)) and "expand_less" or "expand_more" end,
        18, signal, { anchors = { center_in = true } }),
    }
    kit.hover(expand_area, function(hovered) return signal():alpha(hovered and .2 or .06) end, L.control_round(EXPAND))
    local tools_area = kit.action {
      id = "notification-tools-" .. i, accessible_name = "Snooze, mute, rules",
      anchors = { right = true, right_margin = 12 + EXPAND + 4 },
      y = SUM_Y + math.floor((SUM_H - EXPAND) / 2), width = EXPAND, height = EXPAND, cursor = "pointer",
      on_clicked = function() local x = n() if x then M.toggle_tools(x.id) end end,
      kit.icon("more_horiz", 18, signal, { anchors = { center_in = true } }),
    }
    kit.hover(tools_area, function(hovered) return signal():alpha(hovered and .2 or .06) end, L.control_round(EXPAND))

    -- Swiped sideways, or away from the stack's edge, a card follows the
    -- finger and goes past its distance or speed, and springs back short of
    -- them (kit Drags). The first move picks the axis; a stack that scrolls
    -- keeps the vertical one for itself.
    local swiped, axis, start_x, start_y = false, nil, 0, 0
    local function swipe_with(on_axis, go)
      return require("lib.kit.control").headless("Drag", { mode = "swipe", axis = on_axis,
        on_swiped = function(direction) if go(direction) then swiped = true M.dismiss_at(i, direction) end end })
    end
    local across = swipe_with("x", function() return true end)
    local away = swipe_with("y", function(direction) return direction == AWAY end)
    local function held() return axis == "y" and away or across end
    card = kit.action {
      id = "notification-" .. i,
      width = CARD_W, cursor = "pointer", accepted_buttons = { "left", "right", "middle" },
      height = function() return card_height(n()) end,
      translate_x = function() return across.t.delta_x end,
      translate_y = function()
        local moved = away.t.delta_y
        return at_bottom and math.min(0, moved) or math.max(0, moved)
      end,
      behavior = { height = motion, translate_x = { duration = 160, easing = "out_cubic" },
        translate_y = { duration = 160, easing = "out_cubic" } },
      clip = true,
      on_pressed = function(sx, sy, _, _, button)
        -- The right button opens the tools, the middle one dismisses.
        if button == "right" then
          local x = n()
          if x then M.toggle_tools(x.id) end
          return
        end
        if button == "middle" then M.dismiss_at(i) return end
        swiped, axis, start_x, start_y = false, nil, sx, sy
        across.send("pressed", sx, sy)
        away.send("pressed", sx, sy)
      end,
      on_dragged = function(sx, sy)
        if not axis then
          local dx, dy = math.abs(sx - start_x), math.abs(sy - start_y)
          if math.max(dx, dy) < theme.space.s then return end
          axis = dy > dx and total() <= room() and "y" or "x"
        end
        held().send("dragged", sx, sy)
      end,
      on_released = function()
        across.send("released", 0, 0)
        away.send("released", 0, 0)
      end,
      on_swiped = function(_, vx, vy) held().send("fling", vx, vy) end,
      -- A left click runs the sender's default or dismisses -- unless it ended
      -- a swipe that already did. A long press opens the tools.
      on_clicked = function(_, _, _, _, button)
        if button == "right" or button == "middle" then return end
        if swiped then swiped = false return end
        M.click_at(i)
      end,
      on_long_pressed = function() local x = n() if x then M.toggle_tools(x.id) end end,
      ui.Rect { id = "notification-ring-" .. i, anchors = { fill = true }, radius = L.control_round(40), color = "transparent",
        border_color = signal, border_width = function()
          local x = n()
          return (kind() == "alert" or (x and x.highlight)) and 2 or 0
        end },
      L.decor_box("corners", { length = 9, color = function()
        return card and card.hovered and signal() or kit.stroke("mark")()
      end }),
      kit.header { x = 10, y = HEAD_Y, width = CARD_W - 20, key = "notification" .. i, color = signal,
        title = source,
        status = function() return text_of.word(kind()) end },
      micro, age,
      emblem, summary, measure, stripes,
      body_line, body_open,
      preview, progress, transport, chips, buttons, reply, tools,
      footer,
      expand_area, tools_area,
    }
    card.stretch = kit.STRETCH
    -- Its clock stops while it is under the pointer or in use.
    local holding
    morf.effect("eva.notifications.hold." .. i, function()
      local x = n()
      local keep = x ~= nil and (card.contains_pointer or is_open(x.id) or replying(x) or tooled(x))
      local id = keep and x.id or nil
      if id == holding then return end
      if holding then M.hold(holding, false) end
      if id then M.hold(id, true) end
      holding = id
    end, { owner = card })
    -- The slot slides it in and out; the card itself is the finger's.
    slots[i] = ui.Item { width = CARD_W, height = function() return card_height(n()) end,
      visible = function() return n() ~= nil end, behavior = { height = motion }, card }

    -- The card's ground is a layer of the popups' field, in the theme's
    -- corners; seams soften only while a card comes or goes.
    shapes[i] = ui.SdfShape {
      id = "notification-" .. i .. "-shape",
      shape = "box", radius = L.control_round(40), track = card,
      operation = i == 1 and "union" or "smooth_union",
      fill_color = function()
        local base = card.hovered and C.surfaceContainerHigh or C.surfaceContainer
        local x = n()
        return base:mix(signal(), (kind() == "alert" or (x and x.highlight)) and .12 or .04)
      end,
      behavior = { fill_color = { duration = theme.duration.small } },
    }
    layers[#layers + 1] = shapes[i]
    cards[i] = card
  end

  local GONE = { left = { -48, 0 }, right = { 48, 0 }, up = { 0, -48 }, down = { 0, 48 } }

  -- A new card slides in from the edge, grows from a line and fades in;
  -- its emblem pops and the trailing emphasis sweeps in after it.
  -- Dismissed, it collapses to a line and slides away, the way it was sent.
  local function drip(i, coming, direction, done)
    local node, slot, shape, part = cards[i], slots[i], shapes[i], parts[i]
    dripping:set(true)
    if dry then dry:cancel() end
    dry = morf.time.timer(coming and 560 or 260, function() dry = nil dripping:set(false) end, false)
    local steps
    if coming then
      local from_x, from_y = outward()
      steps = {
        { node = slot, property = "translate_x", from = from_x, to = 0, duration = 460, easing = theme.ease.spatial },
        { node = slot, property = "translate_y", from = from_y, to = 0, duration = 460, easing = theme.ease.spatial },
        { node = node, property = "scale_y", from = 0.08, to = 1, duration = 380, easing = theme.ease.spatial },
        { node = node, property = "opacity", from = 0, to = 1, duration = 160 },
        { node = shape, property = "opacity", from = 0, to = 1, duration = 160 },
        { node = part.emblem, property = "scale", from = 0.4, to = 1, duration = 420, delay = 160,
          easing = theme.ease.spatial },
        { node = part.stripes, property = "translate_x", from = -40, to = 0, duration = 520, delay = 140,
          easing = theme.ease.spatial },
        { node = part.stripes, property = "opacity", from = 0, to = 1, duration = 260, delay = 140 },
      }
    else
      local to = GONE[direction]
      local to_x, to_y = 0, 0
      if to then to_x, to_y = to[1], to[2]
      else
        to_x, to_y = outward()
        to_x, to_y = to_x * .75, to_y * .75
      end
      steps = {
        { node = slot, property = "translate_x", to = to_x, duration = 200, easing = theme.ease.emphasized_accel },
        { node = slot, property = "translate_y", to = to_y, duration = 200, easing = theme.ease.emphasized_accel },
        { node = node, property = "scale_y", to = 0.1, duration = 200, easing = theme.ease.emphasized_accel },
        { node = node, property = "opacity", to = 0, duration = 180 },
        { node = shape, property = "opacity", to = 0, duration = 180 },
      }
    end
    morf.animation.play {
      { parallel = steps },
      on_finished = function(reason)
        if not coming then
          slot.translate_x, slot.translate_y, node.scale_y, node.opacity, shape.opacity = 0, 0, 1, 1, 1
        else
          part.emblem.scale, part.stripes.translate_x, part.stripes.opacity = 1, 0, 1
        end
        if done and reason == "completed" then done() end
      end,
    }
  end

  local count = #M.list:get()
  morf.effect("eva.notifications.drip", function()
    local now = #M.list:get()
    if now > count and cards[1] then drip(1, true) end
    count = now
  end)

  local function dismiss(i, direction)
    if cards[i] then drip(i, false, direction) return 200 end
    return 0
  end

  -- The newest nearest the edge the stack hangs from.
  local order = {}
  for i, slot in ipairs(slots) do order[at_bottom and #slots - i + 1 or i] = slot end
  local stack_node, stack, stack_t, stack_ctl = kit.scroll({
    id = "notification-stack", y = STACK_Y, width = CARD_W,
    x = function()
      local side = along()
      return side > 0 and 15 or side < 0 and WIDTH - CARD_W - 15 or (WIDTH - CARD_W) // 2
    end,
    height = function() return height() - TOP - BOTTOM end, clip = true,
  })
  local stacked = ui.Item { width = CARD_W, height = total,
    ui.Sdf(layers),
    ui.Column { gap = GAP, table.unpack(order) },
  }
  ui.reparent(stacked, stack)
  stack_ctl.set_content(stacked)
  local content = ui.Item { anchors = { fill = true }, stack_node }

  if theme.motion.notification_acquire then
    theme.motion.notification_acquire(content, cards, M, shown)
  end
  -- The sidebar opens over the right corner: while it is out a stack there
  -- stands beside it rather than over it.
  local aside = require("presentation").active("sidebar")
  return { content = content, width = WIDTH, height = height, edge = at_bottom and "bottom" or "top", dismiss = dismiss,
    props = { anchors = { [at_bottom and "bottom" or "top"] = true },
      x = function()
        local _, _, w = require("bar").desk()
        local room_w = w - theme.LEFT - theme.BORDER
        local side = along()
        return side < 0 and 0 or side > 0 and room_w - WIDTH or (room_w - WIDTH) // 2
      end,
      translate_x = function() return aside() and along() > 0 and -(theme.SIDE_W + theme.STRIP + theme.GAP) or 0 end,
      behavior = { x = theme.spring.spatial,
        translate_x = { duration = theme.duration.normal, easing = theme.ease.spatial } } } }
end
return V
