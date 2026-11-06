-- The Settings window (shell/settings_window.lua): every page of the registry
-- over everything, the rest of the screen dimmed under it. On a desk it stands
-- in the middle, seven tenths of the screen each way, with the way round
-- (search, categories, their pages) beside the page; on a phone it fills the
-- screen with one page at a time. The pages are the model's builders.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local C, S = theme.color, theme.space

local V = { SHARE = 0.7, NAV_W = 280, PAGE_MAX = 760 }

local SWITCH = { duration = theme.duration.normal, easing = theme.ease.emphasized_decel }
-- How far in from the page's left edge a pull back may start, and how far it
-- must go to count.
local BACK_EDGE, COMMIT = S.xxl + S.s, .35

--- Where the window stands on a screen `sw` by `sh`: x, y, width, height.
function V.geometry(sw, sh, phone)
  if phone then return 0, 0, sw, sh end
  local w, h = math.floor(sw * V.SHARE), math.floor(sh * V.SHARE)
  return math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h
end

--- The pages, one on show at a time, each built the first time it opens and
--- kept. A pull in from the left edge goes back, the page it goes back to
--- showing beneath.
local function pages(model, w, h)
  local pull_x = model.peek
  local function pull() return pull_x:get() end
  local function peek() return math.min(1, pull() / math.max(1, w)) end
  local parents = {}
  for _, d in ipairs(model.DETAILS) do parents[d.key] = d.parent or "" end
  local function peek_key()
    if pull() <= 0 then return nil end
    local parent = parents[model.detail:get()] or ""
    return parent ~= "" and parent or nil
  end
  -- The pages built so far, a row each: a page is built as it first opens.
  local built, have = morf.list_model({}), {}
  local function want(key)
    if key == "" or have[key] or parents[key] == nil then return end
    have[key] = true
    local rows = {}
    for index = 1, built:len() do rows[index] = built:get(index) end
    rows[#rows + 1] = { id = key }
    built:replace(rows, "id")
  end
  morf.effect("eva.settings.window.pages", function()
    if model.opened:get() then want(model.detail:get()) end
  end)
  local function page(row)
    local key = row.id
    local function current() return model.detail:get() == key end
    local function peeked() return peek_key() == key end
    local node = ui.Item {
      id = "settings-detail-" .. key, width = w, height = h,
      visible = function() return current() or peeked() end,
      opacity = function() return current() and 1 or peeked() and .4 + .6 * peek() or 0 end,
      scale = function()
        if current() then return 1 - .06 * peek() end
        return peeked() and .94 + .06 * peek() or 1
      end,
      z = function() return current() and 1 or 0 end,
      behavior = { opacity = { duration = theme.duration.small } },
      ui.Loader { anchors = { fill = true }, active = true, keep = true,
        source = function() return model.page_content(key, w, h) end },
    }
    -- A page pulled back is the finger's; else it eases in.
    ui.claims(node, { motion = SWITCH,
      a_hand = { when = function() return pull() > 0 and current() and peek_key() ~= nil end,
        motion = { duration = 0 }, set = { translate_x = pull } },
      b_rest = { set = { translate_x = function() return (current() or peeked()) and 0 or 20 end } } })
    return node
  end
  local node = ui.Item { id = "settings-detail", width = w, height = h, clip = true,
    ui.Repeater { model = built, delegate = page } }
  local gesture = require("gesture_motion")
  local pulling
  node.on_panned = function(phase, dx, dy, vx, _, start_x)
    if phase == "begin" then
      pulling = false
      if not model.can_back() or dx <= 0 or math.abs(dx) <= math.abs(dy) * 1.2 then return false end
      if not start_x or start_x - (node.layout_x or 0) > BACK_EDGE then return false end
      want(parents[model.detail:get()] or "")
      pulling = true
      return true
    end
    if not pulling then return end
    if phase == "update" then pull_x:set(math.max(0, dx))
    else
      local done = phase == "end" and (dx >= w * COMMIT or gesture.fling(dx, vx) and (vx or 0) > 0)
      pulling = false
      pull_x:set(0)
      if done then
        require("haptics").fire("commit")
        model.back()
      end
    end
  end
  return node
end

--- `model`: the settings model (shell/settings_model.lua with utilities.lua's
--- `page_content`), plus `phone` (one page at a time), `size()` (the screen's)
--- and `top` (what the screen's top keeps for itself). Returns `node`, the
--- `window` a press outside shuts, and `shown(open)`.
function V.build(model)
  local sw, sh = model.size()
  local x, y, w, h = V.geometry(sw, sh, model.phone)
  local PAD = S.l
  local top = PAD + (model.phone and model.top or 0)
  local nav_w = model.phone and 0 or V.NAV_W
  local pane_x = model.phone and PAD or 2 * PAD + nav_w + 1 + PAD
  local room = w - pane_x - PAD
  local pane_w = math.min(room, V.PAGE_MAX)
  pane_x = pane_x + math.floor((room - pane_w) / 2)
  local head_h = math.max(P.HEADER_H, P.BUTTON_H)
  local body_y = top + head_h + P.GAP
  local body_h = h - body_y - PAD
  local names = {}
  for _, d in ipairs(model.DETAILS) do names[d.key] = d.name end

  local function key() return model.detail:get() end
  -- Under the title: the way down to a page one level into another, else
  -- what the page holds.
  local function subtitle()
    if model.nested() then return model.breadcrumb() end
    return (model.registry.BY_KEY[key()] or {}).summary or ""
  end
  -- The page's head and body, and beside them on a desk the way round.
  local function content()
    local close = L.icon_button { id = "settings-close", icon = "close", name = "Close Settings",
      width = P.BUTTON_H, height = P.BUTTON_H, on_clicked = model.close }
    local head = P.header { id = "settings-window-head", width = pane_w, title_id = "settings-page-title",
      title = function() return names[key()] or "Settings" end,
      subtitle = subtitle,
      back = model.back, back_id = "settings-back", can_back = model.can_back, actions = { close },
      active = function() return require("presentation").active("settings." .. key())() end }
    local parts = { id = "settings-window-content", anchors = { fill = true },
      ui.Item { x = pane_x, y = top, width = pane_w, height = head_h, head },
      ui.Item { x = pane_x, y = body_y, width = pane_w, height = body_h, pages(model, pane_w, body_h) } }
    if not model.phone then
      local nav_h = h - 2 * PAD - L.heading_h(L.SIZE.title) - P.GAP
      parts[#parts + 1] = ui.Column { x = PAD, y = PAD, width = nav_w, gap = P.GAP,
        L.heading { id = "settings-window-title", width = nav_w, text = "Settings", elide = "right",
          active = function() return model.opened:get() end },
        ui.Item { width = nav_w, height = nav_h, ui.Loader { anchors = { fill = true }, active = true,
          source = function() return require("themes").view("settings_home").navigation(model, nav_w, nav_h) end } } }
      parts[#parts + 1] = L.rule { x = 2 * PAD + nav_w, y = PAD, width = 1, height = h - 2 * PAD }
    end
    return ui.Item(parts)
  end

  -- The content is made the first time the window opens, or ahead of that
  -- while the shell is idle.
  local wanted = morf.signal("eva.settings.window.built", model.opened:get())
  morf.effect("eva.settings.window.build", function()
    if model.opened:get() and not wanted:get() then wanted:set(true) end
  end)
  local keys = ui.Item { id = "settings-window-keys", width = 1, height = 1 }
  -- Alt+Left and a mouse's back button go one page up, and shut the window
  -- from All settings. The panels board keeps Alt with the arrows for its tiles.
  local function pop() return model.back() end
  local shortcuts = { back = pop,
    ["alt+Left"] = function() if key() == "panels" then return false end return pop() end }
  local window = ui.Item { id = "settings-window", x = x, y = y, width = w, height = h,
    accessible_role = "dialog", accessible_name = "Settings", shortcuts = shortcuts,
    -- Its empty parts take presses, so they reach nothing under it.
    ui.MouseArea { anchors = { fill = true }, z = -1 },
    kit.surface { id = "settings-window-ground", anchors = { fill = true }, z = -1,
      radius = model.phone and 0 or kit.round(theme.ROUNDING), color = function() return C.surface end,
      border_width = model.phone and 0 or 1, border_color = kit.stroke("quiet") },
    ui.Item { anchors = { fill = true }, L.decor_box("corners", { length = 12 }) },
    ui.Loader { anchors = { fill = true }, keep = true, preload = true, active = function() return wanted:get() end,
      source = content },
    keys }
  local function shown() return model.opened:get() and not (model.covered and model.covered()) end
  local drawn = theme.motion.appear(window, shown, { id = "settings-window", content = false })

  -- The dim: round the window, or the whole of a screen it is not open on.
  local function elsewhere() return model.elsewhere ~= nil and model.elsewhere() end
  local function dim() return shown() or elsewhere() end
  local scrim = kit.surface { id = "settings-scrim", anchors = { fill = true },
    color = function() return C.scrim:alpha(dim() and .55 or 0) end,
    behavior = { color = { duration = theme.duration.normal, easing = theme.ease.standard } } }
  local fading = morf.signal("eva.settings.window.fading", false)
  local fade
  morf.effect("eva.settings.window.fade", function()
    if fade then fade:cancel() fade = nil end
    if dim() then fading:set(true) return end
    fade = morf.time.timer(theme.duration.normal, function() fade = nil fading:set(false) end, false)
  end)
  local root = ui.Item { id = "settings-window-root", anchors = { fill = true },
    visible = function() return dim() or drawn() or fading:get() end,
    scrim,
    ui.MouseArea { id = "settings-scrim-area", anchors = { fill = true }, enabled = dim,
      accessible_name = "Close Settings", on_clicked = model.dismiss or model.close, on_wheel = function() end },
    window }
  morf.effect("eva.settings.window.present", function() model.present(model.detail:get()) end, { owner = root })
  -- Open, the keys go to the window, unless the search takes them; a turn
  -- later, as a panel stepping aside hands focus back as it shuts.
  return { node = root, window = window,
    shown = function(open)
      morf.time.timer(1, function()
        local on = shown() and not model.searching()
        if on or keys.focused then keys.focus = on end
      end, false)
    end }
end

return V
