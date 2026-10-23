-- The window menu (shell/window_menu.lua): five cards in a cross over the
-- focused window, its frame marked on the desk. They fan out from the
-- middle as it opens; a side card chosen glides to the top left as its
-- branch, its pages fall in under it one after another and the chosen
-- page's actions stand beside them. Only kit calls and theme tokens draw.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local P = require("themes.layouts.page")
local C = theme.color
local V = {}

local CW, SH, CH = 272, 112, 88
local GX, GY = 64, 56
local W = 3 * CW + 2 * GX
local H = 3 * SH + 2 * GY
local BW, DW, BG = 256, 400, 36
local BX, BY = math.floor((W - BW - BG - DW) / 2), 42
local SUB_H, SUB_GAP, ROW_H, ROW_GAP = 40, 10, 38, 6
local MAX_SUBS, MAX_ROWS = 3, 10
local DH_TOP = 96
local MAXH = math.max(H, BY + DH_TOP + MAX_ROWS * (ROW_H + ROW_GAP) + 16)
local MARGIN = 16
local GLIDE = { duration = 480, easing = "out_cubic" }
local FADE = { duration = 240, easing = "out_cubic" }

local REST = {
  center = { CW + GX, SH + GY + (SH - CH) / 2 },
  top = { CW + GX, 0 }, bottom = { CW + GX, 2 * (SH + GY) },
  left = { 0, SH + GY }, right = { 2 * (CW + GX), SH + GY },
}
local NUDGE = { center = { 0, 0 }, top = { 0, -8 }, bottom = { 0, 8 }, left = { -8, 0 }, right = { 8, 0 } }
local ARROW = {
  top = { W / 2 - 18, SH + GY / 2 - 18, "arrow_upward", "arrow_downward" },
  bottom = { W / 2 - 18, 2 * SH + GY * 1.5 - 18, "arrow_downward", "arrow_upward" },
  left = { CW + GX / 2 - 18, H / 2 - 18, "arrow_back", "arrow_forward" },
  right = { W - CW - GX / 2 - 18, H / 2 - 18, "arrow_forward", "arrow_back" },
}

local function upper(text) return function() return tostring(text() or ""):upper() end end

--- A row of the branch: a caps label, a reading at its right, the theme's
--- state ground while `on`, and the corner marks while the keys are on it.
local function row(spec)
  local ink = require("themes.layouts.rows").ink(spec.on, true, C.onSurface)
  local area
  area = kit.action { id = spec.id, accessible_name = spec.name, width = spec.width, height = spec.height,
    cursor = "pointer", enabled = spec.enabled, visible = spec.visible,
    on_clicked = spec.on_clicked, on_entered = spec.on_entered,
    L.label { x = 14, anchors = { vertical_center = true }, width = spec.width - 28 - (spec.meta_w or 110),
      elide = "right", font_size = L.SIZE.body, text = upper(spec.label), color = ink },
    L.label { anchors = { right = true, right_margin = 14, vertical_center = true }, width = spec.meta_w or 110,
      horizontal_alignment = "right", elide = "left", font_size = L.SIZE.label, text = spec.meta or "",
      color = function() return ink():alpha(0.75) end },
    ui.Item { anchors = { fill = true }, visible = spec.focused,
      L.decor_box("corners", { length = 6, weight = 2, inset = -2, color = kit.stroke("hot") }) },
  }
  ui.reparent(kit.state_surface { id = spec.id .. "-shape", area = area, on = spec.on, height = spec.height,
    tone = "primary", z = -1 }, area)
  return area
end

function V.build(model)
  local opened, branch = model.opened, model.branch
  local function selected(key) return model.slot:get() == key end
  local function in_branch(key) return branch:get() and selected(key) and key ~= "center" end
  local function shown(key)
    if not opened:get() then return false end
    if branch:get() then return in_branch(key) end
    return true
  end

  -- -------------------------------------------------------------- cards --
  local cards = {}
  for _, slot in ipairs(model.SLOTS) do
    local key, center = slot.key, slot.key == "center"
    local h = center and CH or SH
    local function summary(i) return function() return model.summary(key)[i] or "" end end
    local function width() return in_branch(key) and BW or CW end
    local children = {
      kit.card { anchors = { fill = true } },
      L.label { x = 14, y = 12, width = 22, text = slot.number, font_size = L.SIZE.label, color = kit.ink("lo") },
      kit.text { x = 42, y = 8, width = function() return width() - 56 end, elide = "right", text = slot.title:upper(),
        font_size = theme.size.normal, font_weight = 600, color = kit.ink("hi") },
      L.rule { x = 12, y = 34, width = function() return width() - 24 end },
    }
    if center then
      -- Its header is lit, as the reference's: the window's own card.
      table.insert(children, 2, kit.surface { x = 6, y = 6, height = 26, width = function() return width() - 12 end,
        color = kit.signal("accent") })
      children[3].color = function() return C.onPrimary end
      children[4].color = function() return C.onPrimary end
      children[#children + 1] = kit.text { x = 14, y = 44, width = CW - 28, elide = "right", text = summary(1),
        font_size = theme.size.normal, color = kit.ink("hi"), horizontal_alignment = "center" }
      children[#children + 1] = L.label { x = 14, y = 66, width = CW - 28, elide = "right", text = upper(summary(2)),
        horizontal_alignment = "center", color = kit.ink("lo") }
    else
      children[#children + 1] = kit.text { x = 16, y = 46, width = function() return width() - 32 end, elide = "right",
        text = summary(1), font_size = theme.size.normal, color = kit.ink("hi") }
      children[#children + 1] = L.label { x = 16, y = SH - 28, width = function() return width() / 2 - 20 end,
        elide = "right", text = summary(2), color = kit.ink("lo") }
      children[#children + 1] = L.label { anchors = { right = true, right_margin = 16 }, y = SH - 28,
        width = function() return width() / 2 - 20 end, elide = "left", horizontal_alignment = "right",
        text = summary(3), color = kit.ink("lo") }
    end
    children[#children + 1] = ui.Item { anchors = { fill = true },
      visible = function() return selected(key) and not branch:get() end,
      L.decor_box("corners", { length = 10, weight = 2, inset = -4, color = kit.stroke("hot") }) }
    local area = kit.action { id = "window-menu-card-" .. key, accessible_name = slot.title,
      width = width, height = h, cursor = center and "default" or "pointer",
      enabled = function() return shown(key) end,
      x = function()
        if in_branch(key) then return BX end
        if not opened:get() then return REST.center[1] end
        return REST[key][1] + (selected(key) and not branch:get() and NUDGE[key][1] or 0)
      end,
      y = function()
        if in_branch(key) then return BY end
        if not opened:get() then return REST.center[2] - (h - CH) / 2 end
        return REST[key][2] + (selected(key) and not branch:get() and NUDGE[key][2] or 0)
      end,
      opacity = function() return shown(key) and 1 or 0 end,
      z = function() return in_branch(key) and 4 or 2 end,
      behavior = { x = GLIDE, y = GLIDE, width = GLIDE, opacity = FADE },
      on_entered = function() model.select(key) end,
      on_clicked = function() if branch:get() then model.back() else model.open_slot(key) end end,
      table.unpack(children),
    }
    ui.reparent(kit.state_surface { id = "window-menu-card-" .. key .. "-shape", area = area,
      on = function() return selected(key) end, height = h, tone = "primary", z = -1 }, area)
    cards[#cards + 1] = area
  end

  -- ------------------------------------------------------------- arrows --
  local arrows = {}
  for _, key in ipairs { "top", "left", "right", "bottom" } do
    local a = ARROW[key]
    arrows[#arrows + 1] = ui.Item { id = "window-menu-arrow-" .. key, x = a[1], y = a[2], width = 36, height = 36,
      opacity = function()
        if not opened:get() or branch:get() then return 0 end
        return selected(key) and 1 or 0.6
      end,
      behavior = { opacity = FADE },
      L.decor_box("corners", { width = 36, height = 36, length = 6, color = kit.stroke("mark") }),
      kit.icon(function() return selected(key) and a[4] or a[3] end, 20,
        function() return selected(key) and kit.signal("accent")() or kit.ink("hi")() end,
        { anchors = { center_in = true } }),
    }
  end

  -- ------------------------------------------------------------- branch --
  local function branch_shown() return opened:get() and branch:get() end
  local back = ui.Item { x = BX, y = 0, width = BW, height = 30,
    opacity = function() return branch_shown() and 1 or 0 end, behavior = { opacity = FADE },
    P.button { id = "window-menu-back", label = "Menu", icon = "arrow_back", width = BW, height = 30,
      on_clicked = model.back, enabled = branch_shown } }
  local stem = L.rule { x = BX + BW / 2, y = BY + SH, width = 1, height = 24, strength = "mark",
    opacity = function() return branch_shown() and 1 or 0 end, behavior = { opacity = FADE } }

  local subs = {}
  for i = 1, MAX_SUBS do
    local function sub() return model.subs()[i] end
    subs[i] = row { id = "window-menu-sub-" .. i, width = BW, height = SUB_H,
      name = function() return sub() and sub().label or "" end,
      label = function() return sub() and sub().label or "" end,
      meta = "", meta_w = 20,
      visible = function() return sub() ~= nil end, enabled = branch_shown,
      on = function() return model.sub:get() == i end,
      focused = function() return model.column:get() == "subs" and model.sub:get() == i end,
      on_clicked = function() model.column:set("subs") model.choose_sub(i) end,
      on_entered = function() model.choose_sub(i) end }
    subs[i].x, subs[i].y = BX, BY + SH + 24 + (i - 1) * (SUB_H + SUB_GAP)
  end

  local rows = {}
  for i = 1, MAX_ROWS do
    local function action() return model.actions()[i] end
    rows[i] = row { id = "window-menu-action-" .. i, width = DW - 32, height = ROW_H,
      name = function() return action() and action().label or "" end,
      label = function() return action() and action().label or "" end,
      meta = function() return action() and action().meta or "" end,
      meta_w = 150,
      visible = function() return action() ~= nil end,
      enabled = function() return branch_shown() and action() ~= nil and not action().info end,
      on = function() local a = action() return a ~= nil and (a.selected == true or a.primary == true) end,
      focused = function() return model.column:get() == "actions" and model.action:get() == i end,
      on_clicked = function() model.column:set("actions") model.run(i) end,
      on_entered = function() if model.column:get() == "actions" then model.action:set(i) end end }
  end
  local function slot() return model.slot_spec() or {} end
  local function detail_h() return DH_TOP + #model.actions() * (ROW_H + ROW_GAP) + 10 end
  local details = ui.Item { id = "window-menu-details", x = BX + BW + BG, y = BY, width = DW, height = detail_h,
    opacity = function() return branch_shown() and 1 or 0 end, behavior = { opacity = FADE, height = GLIDE },
    kit.card { anchors = { fill = true } },
    L.label { x = 14, y = 12, width = 22, text = function() return slot().number or "" end, color = kit.ink("lo") },
    kit.text { x = 42, y = 8, width = DW - 100, elide = "right", text = function() return (slot().title or ""):upper() end,
      font_size = theme.size.normal, font_weight = 600, color = kit.ink("hi") },
    L.icon_button { id = "window-menu-close", x = DW - 40, y = 4, width = 32, height = 30, icon = "close", size = 18,
      name = "Back", on_clicked = model.back },
    L.rule { x = 12, y = 36, width = DW - 24 },
    L.label { x = 16, y = 46, width = DW - 32, elide = "right", font_size = L.SIZE.body,
      text = function() local s = model.subs()[model.sub:get()] return s and s.label:upper() or "" end,
      color = kit.ink("lo") },
    L.rule { x = 16, y = 66, width = 34, strength = "mark" },
    kit.text { x = 16, y = 72, width = DW - 32, elide = "right", font_size = L.SIZE.body, color = kit.ink("hi"),
      text = function()
        local m = model.message:get()
        if m ~= "" then return m end
        return model.summary(model.slot:get())[1] or ""
      end },
    ui.Column { x = 16, y = DH_TOP, gap = ROW_GAP, table.unpack(rows) },
  }

  -- ------------------------------------------------------------ the box --
  local keys = ui.Item { id = "window-menu-keys", width = 1, height = 1, tab_navigation = false,
    on_key_pressed = model.key }
  local function rect() return model.rect() or { x = 0, y = 0, width = 0, height = 0 } end
  local box_children = { back, stem }
  for _, n in ipairs(arrows) do box_children[#box_children + 1] = n end
  for _, n in ipairs(cards) do box_children[#box_children + 1] = n end
  for _, n in ipairs(subs) do box_children[#box_children + 1] = n end
  box_children[#box_children + 1] = details
  box_children[#box_children + 1] = keys
  box_children.id = "window-menu"
  box_children.width, box_children.height = W, function() return math.max(H, branch:get() and detail_h() + BY or H) end
  box_children.x = function()
    local r, sw = rect(), model.screen()
    return math.floor(math.max(MARGIN, math.min(sw - W - MARGIN, r.x + r.width / 2 - W / 2)))
  end
  box_children.y = function()
    local r, _, sh = rect(), model.screen()
    return math.floor(math.max(MARGIN, math.min(sh - MAXH - MARGIN, r.y + r.height / 2 - H / 2)))
  end
  box_children.accessible_role, box_children.accessible_name = "dialog", "Window menu"
  local box = ui.Item(box_children)

  -- The window itself, framed on the desk under the menu.
  local frame = ui.Item { id = "window-menu-frame",
    x = function() return rect().x end, y = function() return rect().y end,
    width = function() return rect().width end, height = function() return rect().height end,
    opacity = function() return opened:get() and 1 or 0 end, behavior = { opacity = FADE },
    kit.surface { anchors = { fill = true }, color = "transparent", border_width = 2, radius = theme.ROUNDING,
      border_color = kit.stroke("hot") },
    L.decor_box("corners", { length = 18, weight = 2, inset = -6, color = kit.stroke("hot") }),
  }
  local dim = kit.surface { id = "window-menu-dim", anchors = { fill = true },
    color = function() return C.surface:alpha(opened:get() and .4 or 0) end,
    behavior = { color = { duration = theme.duration.normal, easing = theme.ease.standard } } }

  -- Shown while open, and for the fade after.
  local lingering = morf.signal("eva.window_menu.lingering", false)
  local fade
  morf.effect("material.window_menu.linger", function()
    local open = opened:get()
    if fade then fade:cancel() fade = nil end
    if open then lingering:set(true) return end
    fade = morf.timer(FADE.duration + 80, function() fade = nil lingering:set(false) end, false)
  end)
  local root = ui.Item { id = "window-menu-root", anchors = { fill = true },
    visible = function() return opened:get() or lingering:get() end,
    dim, frame, box }

  -- The pages of a branch fall in one after another, and its actions settle.
  local running = {}
  morf.effect("material.window_menu.branch", function()
    local open, key = branch_shown(), model.slot:get()
    for _, h in ipairs(running) do h:stop() end
    running = {}
    if not open or key == "center" then return end
    for i, node in ipairs(subs) do
      running[#running + 1] = morf.animation.play { { parallel = {
        { node = node, property = "translate_x", from = -12, to = 0, duration = 380, easing = "out_cubic", delay = 280 + (i - 1) * 80 },
        { node = node, property = "translate_y", from = -8, to = 0, duration = 380, easing = "out_cubic", delay = 280 + (i - 1) * 80 },
        { node = node, property = "opacity", from = 0, to = 1, duration = 380, easing = "out_cubic", delay = 280 + (i - 1) * 80 },
      } } }
    end
    running[#running + 1] = morf.animation.play { { node = details, property = "translate_y", from = -8, to = 0,
      duration = 380, easing = "out_cubic", delay = 280 } }
  end)

  return { node = root, box = box, shown = function(open) keys.focus = open end }
end

return V
